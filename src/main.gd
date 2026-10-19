extends Node2D

var port := 27840
const FLOOR = 448.0
const LabKeys = preload("res://src/lab_keys.gd")
var lab_role := ""
var lab_socket: PacketPeerUDP
var bus_port := 0
var control_port := 0
var control_input: Array = [0.0,false,false]
var last_control := 0
var delay_ms := 0
var outbox: Array = []
var rx := 0
var tx := 0
var snapshot_seq := 0
var last_snapshot_seq := 0
var last_snapshot_ms := 0
var snapshot_gaps := 0
var rtt := -1
var debug_label: Label
var ground_tile: Texture2D
var players: Dictionary = {}
var commands: Dictionary = {}
var status: Label
var address: LineEdit
var mode := "solo"
var tick := 0
var elapsed := 0.0
var connected_at := 0.0
var last_input := 0.0
var enemy_hp := 12
var enemy_flash := 0.0
var enemy_x := 720.0
var sprites: Dictionary = {}
var sheet = preload("res://assets/knight.png")
var animations: SpriteFrames
var rtc: WebRTCPeerConnection
var local_signal: Dictionary = {}
var signal_finished := false
var signal_out: TextEdit
var signal_in: TextEdit
var signal_panel: VBoxContainer
var clipboard_callback
var clipboard_error
var setup_menu: PanelContainer
var requested_address := "127.0.0.1"
var capture_at := -1.0
var test_mode := ""
var camera: Camera2D
var test_partner_seen := false

func _ready():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--lab-role="): lab_role = arg.get_slice("=",1)
  if arg.begins_with("--control-port="): control_port = int(arg.get_slice("=",1))
  if arg.begins_with("--bus-port="): bus_port = int(arg.get_slice("=",1))
  if arg.begins_with("--address="): requested_address = arg.get_slice("=",1)
  if arg.begins_with("--port="): port = int(arg.get_slice("=",1))
 if ResourceLoader.exists("res://assets/private/tiles/Tile_02.png"):
  ground_tile = load("res://assets/private/tiles/Tile_02.png")
 camera = Camera2D.new()
 camera.position = Vector2(480,270)
 add_child(camera)
 build_animations()
 var canvas = CanvasLayer.new()
 add_child(canvas)
 var panel = VBoxContainer.new()
 panel.position = Vector2(16,12)
 canvas.add_child(panel)
 var title = Label.new()
 title.text = "Ember Bridge" if lab_role == "" else "P1 / HOST" if lab_role == "host" else "P2 / GUEST"
 title.add_theme_font_size_override("font_size",18)
 panel.add_child(title)
 var menu_button = Button.new()
 menu_button.text = "Menu"
 menu_button.pressed.connect(func(): setup_menu.visible = not setup_menu.visible; signal_panel.hide())
 menu_button.custom_minimum_size = Vector2(88,30)
 panel.add_child(menu_button)
 status = Label.new()
 panel.add_child(status)
 var help = Label.new()
 help.text = "A/D move · W jump · F attack"
 panel.add_child(help)
 setup_menu = PanelContainer.new()
 setup_menu.position = Vector2(16,125)
 setup_menu.custom_minimum_size = Vector2(380,160)
 canvas.add_child(setup_menu)
 var options = VBoxContainer.new()
 options.add_theme_constant_override("separation",8)
 setup_menu.add_child(options)
 var heading = Label.new()
 heading.text = "Play"
 options.add_child(heading)
 for item in [["Play solo",solo],["Host game",host],["Join game",join_game]]:
  var b = Button.new()
  b.text = item[0]
  b.pressed.connect(item[1])
  style_button(b)
  options.add_child(b)
 address = LineEdit.new()
 address.text = requested_address
 address.placeholder_text = "Host address"
 options.add_child(address)
 address.visible = not OS.has_feature("web")
 var hint = Label.new()
 hint.text = "Host creates a session. Join connects to your partner."
 hint.add_theme_font_size_override("font_size",13)
 options.add_child(hint)
 if lab_role != "":
  menu_button.hide()
  help.text = "A/D move · W jump · F attack" if lab_role == "host" else "Left/Right move · Up jump · L attack"
  debug_label = Label.new()
  var debug_panel = PanelContainer.new()
  debug_panel.position = Vector2(12,466)
  var debug_style = StyleBoxFlat.new()
  debug_style.bg_color = Color("101820")
  debug_style.content_margin_left = 8
  debug_style.content_margin_right = 8
  debug_style.content_margin_top = 4
  debug_style.content_margin_bottom = 4
  debug_panel.add_theme_stylebox_override("panel",debug_style)
  canvas.add_child(debug_panel)
  debug_label.add_theme_font_size_override("font_size",14)
  debug_panel.add_child(debug_label)
 signal_panel = VBoxContainer.new()
 signal_panel.position = Vector2(16,125)
 signal_panel.visible = false
 canvas.add_child(signal_panel)
 var explanation = Label.new()
 explanation.text = "1 Host: Create offer -> send code.  2 Guest: paste -> Accept.\n3 Guest sends answer. Host pastes -> Accept. Wait for Connected."
 signal_panel.add_child(explanation)
 var actions = HBoxContainer.new()
 signal_panel.add_child(actions)
 for item in [["Create offer",rtc_offer],["Accept pasted code",rtc_accept],["Copy my code",copy_signal],["Paste and accept",paste_signal]]:
  var button = Button.new()
  button.text = item[0]
  button.pressed.connect(item[1])
  actions.add_child(button)
 signal_out = TextEdit.new()
 signal_out.custom_minimum_size = Vector2(700,66)
 signal_out.editable = false
 signal_out.placeholder_text = "Your code appears here after ICE gathering; select and copy."
 signal_panel.add_child(signal_out)
 signal_in = TextEdit.new()
 signal_in.custom_minimum_size = Vector2(700,66)
 signal_in.placeholder_text = "Paste partner’s code here"
 signal_panel.add_child(signal_in)
 solo()
 setup_menu.visible = lab_role == ""
 if lab_role != "":
  lab_socket = PacketPeerUDP.new()
  var bind_error = lab_socket.bind(control_port,"127.0.0.1")
  if bind_error != OK:
   status.text = "Lab control port failed: " + error_string(bind_error)
  lab_socket.set_dest_address("127.0.0.1",bus_port)
  DisplayServer.window_set_title("Ember Bridge / " + lab_role.to_upper())
  if lab_role == "host": host()
  else: join_game()
 for arg in OS.get_cmdline_user_args():
  if arg == "--capture":
   capture_at = 1.0
   setup_menu.hide()
  if arg == "--test-host":
   test_mode = "host"
   host()
  if arg == "--test-client":
   test_mode = "client"
   join_game()
 multiplayer.peer_connected.connect(peer_joined)
 multiplayer.peer_disconnected.connect(peer_left)
 multiplayer.connected_to_server.connect(func(): signal_panel.hide(); status.text = "Connected • host simulates combat and movement"; connected_at = elapsed)
 multiplayer.connection_failed.connect(func(): solo(); status.text = "Connection failed. Check address / UDP 27840.")
 multiplayer.server_disconnected.connect(func(): solo(); status.text = "Host disconnected • returned to solo")

func build_animations():
 animations = SpriteFrames.new()
 animations.remove_animation("default")
 var metadata = JSON.parse_string(FileAccess.get_file_as_string("res://assets/craftpix-clips.json"))
 for clip in ["Idle","Walk","Run","Jump","Attack 1","Hurt","Dead"]:
  var path = "res://assets/private/character/" + clip + ".png"
  if not ResourceLoader.exists(path): continue
  var texture = load(path) as Texture2D
  animations.add_animation(clip)
  animations.set_animation_speed(clip,12)
  animations.set_animation_loop(clip,clip in ["Idle","Walk","Run"])
  var cells = metadata.get(clip,range(texture.get_width()/128)) if metadata is Dictionary else range(texture.get_width()/128)
  for cell in cells:
   var i = int(cell)
   var frame = AtlasTexture.new()
   frame.atlas = texture
   frame.region = Rect2(i*128,0,128,128)
   animations.add_frame(clip,frame)

func style_button(button: Button):
 for pair in [["normal",""],["hover","-HOVER"],["pressed","-PUSHED"]]:
  var path = "res://assets/private/ui/button"+pair[1]+".png"
  if not ResourceLoader.exists(path): continue
  var style = StyleBoxTexture.new()
  style.texture = load(path)
  style.texture_margin_left = 16
  style.texture_margin_right = 16
  style.texture_margin_top = 16
  style.texture_margin_bottom = 16
  style.content_margin_left = 12
  style.content_margin_right = 12
  style.content_margin_top = 6
  style.content_margin_bottom = 6
  button.add_theme_stylebox_override(pair[0],style)

func rtc_begin(server: bool) -> bool:
 if not OS.has_feature("web"):
  status.text = "WebRTC connection codes run in the browser build. Native Host/Join uses LAN UDP."
  return false
 reset_network()
 rtc = WebRTCPeerConnection.new()
 # No TURN relay is configured. STUN discovers addresses, not a traffic relay.
 var error = rtc.initialize({"iceServers":[{"urls":["stun:stun.l.google.com:19302"]}]})
 if error != OK:
  solo()
  status.text = "WebRTC initialization failed"
  return false
 var peer = WebRTCMultiplayerPeer.new()
 var channels = [MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED]
 if server: peer.create_server(channels)
 else: peer.create_client(2,channels)
 error = peer.add_peer(rtc,2 if server else 1,100)
 if error != OK:
  solo()
  status.text = "WebRTC peer creation failed"
  return false
 multiplayer.multiplayer_peer = peer
 mode = "host" if server else "client"
 if server: spawn(1)
 connected_at = elapsed
 local_signal = {"type":"","sdp":"","ice":[]}
 rtc.session_description_created.connect(func(type, sdp):
  rtc.set_local_description(type,sdp)
  local_signal.type = type
  local_signal.sdp = sdp
 )
 rtc.ice_candidate_created.connect(func(media, index, candidate): local_signal.ice.append([media,index,candidate]))
 status.text = "Gathering connection code…"
 return true

func paste_signal():
 if OS.has_feature("web"):
  clipboard_callback = JavaScriptBridge.create_callback(func(args):
   signal_in.text = str(args[0])
   rtc_accept()
  )
  clipboard_error = JavaScriptBridge.create_callback(func(_args): status.text = "Clipboard permission denied • paste into lower field instead")
  var navigator = JavaScriptBridge.get_interface("navigator")
  var promise = navigator.clipboard.readText()
  promise.then(clipboard_callback).catch(clipboard_error)
 else:
  signal_in.text = DisplayServer.clipboard_get()
  rtc_accept()

func copy_signal():
 if signal_out.text != "":
  DisplayServer.clipboard_set(signal_out.text)
  status.text = "Code copied • send privately to partner"

func rtc_offer():
 if rtc_begin(true): rtc.create_offer()

func rtc_accept():
 if signal_in.text.length() > 65536:
  status.text = "Connection code too large"
  return
 var decoded = Marshalls.base64_to_utf8(signal_in.text.strip_edges())
 var data = JSON.parse_string(decoded)
 if not data is Dictionary or not data.get("sdp") is String or not data.get("ice") is Array or data.get("type") not in ["offer","answer"]:
  status.text = "Invalid connection code"
  return
 if data.type == "offer":
  if not rtc_begin(false): return
 elif rtc == null or mode != "host":
  status.text = "Create an offer before accepting an answer"
  return
 if rtc.set_remote_description(data.type,data.sdp) != OK:
  status.text = "Could not accept session description"
  return
 for candidate in data.ice:
  if candidate is Array and candidate.size() == 3 and candidate[0] is String and candidate[1] is float and candidate[2] is String:
   rtc.add_ice_candidate(candidate[0],int(candidate[1]),candidate[2])
 status.text = "Connecting directly…"

func _process(_dt):
 if rtc != null and not local_signal.is_empty():
  if rtc.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE and local_signal.sdp != "" and not signal_finished:
   signal_finished = true
   if local_signal.ice.is_empty():
    status.text = "No connection candidates • check browser/network; relay unavailable"
    return
   var code = Marshalls.utf8_to_base64(JSON.stringify(local_signal))
   if signal_out.text != code:
    signal_out.text = code
    status.text = "Connection code ready • send it to your partner"
 if capture_at > 0 and elapsed >= capture_at:
  capture_at = -1
  get_viewport().get_texture().get_image().save_png("res://preview.png")
  get_tree().quit()

func reset_network():
 if multiplayer.multiplayer_peer:
  multiplayer.multiplayer_peer.close()
 multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
 if rtc != null: rtc.close()
 rtc = null
 local_signal = {}
 rx = 0
 tx = 0
 rtt = -1
 snapshot_seq = 0
 last_snapshot_seq = 0
 snapshot_gaps = 0
 last_snapshot_ms = 0
 outbox.clear()
 signal_finished = false
 players.clear()
 commands.clear()
 for s in sprites.values(): s.queue_free()
 sprites.clear()
 enemy_hp = 12

func spawn(id: int):
 players[id] = {"x":180.0 if id == 1 else 260.0,"y":FLOOR,"vy":0.0,"face":1.0,"attack":0.0,"moving":false,"jump_held":false,"grounded":true,"attack_id":0}

func solo():
 setup_menu.hide()
 signal_panel.hide()
 reset_network()
 mode = "solo"
 spawn(1)
 status.text = "Solo"

func host():
 setup_menu.hide()
 if OS.has_feature("web"):
  signal_panel.show()
  rtc_offer()
  return
 reset_network()
 var peer = ENetMultiplayerPeer.new()
 var error = peer.create_server(port,1)
 if error != OK:
  solo()
  status.text = "Host failed: " + error_string(error)
  return
 multiplayer.multiplayer_peer = peer
 mode = "host"
 spawn(1)
 status.text = "Host / UDP %d / waiting" % port

func join_game():
 setup_menu.hide()
 if OS.has_feature("web"):
  signal_panel.show()
  status.text = "Paste host offer into connection codes, then Accept"
  return
 reset_network()
 var peer = ENetMultiplayerPeer.new()
 var error = peer.create_client(address.text.strip_edges(),port)
 if error != OK:
  solo()
  status.text = "Join failed: " + error_string(error)
  return
 multiplayer.multiplayer_peer = peer
 mode = "client"
 status.text = "Connecting…"
 connected_at = elapsed

func peer_joined(id: int):
 if mode == "host":
  spawn(id)
  test_partner_seen = true
  signal_panel.hide()
  status.text = "Partner joined • host authority • snapshots 20 Hz"

func peer_left(id: int):
 players.erase(id)
 commands.erase(id)
 if sprites.has(id):
  sprites[id].queue_free()
  sprites.erase(id)
 if mode == "host": status.text = "Partner left • waiting for another"

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_input(axis: float, jump: bool, attack: bool):
 rx += 1
 if mode != "host" or not is_finite(axis): return
 var id = multiplayer.get_remote_sender_id()
 if players.has(id): commands[id] = [clampf(axis,-1,1),jump,attack,elapsed]

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func snapshot(state: Dictionary, hp: int, ex: float, sequence: int):
 rx += 1
 last_snapshot_ms = Time.get_ticks_msec()
 if last_snapshot_seq > 0: snapshot_gaps += maxi(0,sequence-last_snapshot_seq-1)
 last_snapshot_seq = sequence
 if mode != "client": return
 players = state
 enemy_hp = hp
 enemy_x = ex

@rpc("any_peer", "call_remote", "unreliable")
func ping(sent: int):
 rx += 1
 var sender = multiplayer.get_remote_sender_id()
 if sender == 1 or players.has(sender): queue_packet("pong",[sender,sent])

@rpc("any_peer", "call_remote", "unreliable")
func pong(sent: int):
 rx += 1
 rtt = Time.get_ticks_msec()-sent

func queue_packet(kind: String, data: Array):
 if outbox.size() < 256: outbox.append({"due":Time.get_ticks_msec()+delay_ms,"kind":kind,"data":data})

func flush_packets():
 var now = Time.get_ticks_msec()
 while not outbox.is_empty() and outbox[0].due <= now:
  var packet = outbox.pop_front()
  var d = packet.data
  if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED: continue
  tx += 1
  match packet.kind:
   "input": submit_input.rpc_id(1,d[0],d[1],d[2])
   "snapshot": snapshot.rpc(d[0],d[1],d[2],d[3])
   "ping":
    if d[0] in multiplayer.get_peers(): ping.rpc_id(d[0],d[1])
   "pong":
    if d[0] in multiplayer.get_peers(): pong.rpc_id(d[0],d[1])

func lab_control():
 if lab_socket == null: return
 while lab_socket.get_available_packet_count() > 0:
  var data = JSON.parse_string(lab_socket.get_packet().get_string_from_utf8())
  if not data is Dictionary: continue
  if data.get("kind") == "capture": get_viewport().get_texture().get_image().save_png("res://build/lab-"+lab_role+".png")
  if data.get("kind") == "quit": get_tree().quit()
  if data.get("kind") == "input":
   control_input = [clampf(float(data.get("axis",0)),-1,1),bool(data.get("jump",false)),bool(data.get("attack",false))]
   delay_ms = clampi(int(data.get("delay",0)),0,200)
   last_control = Time.get_ticks_msec()
 if get_window().has_focus(): lab_socket.put_packet(JSON.stringify({"kind":"keys","keys":LabKeys.read_keys()}).to_utf8_buffer())
 if Time.get_ticks_msec()-last_control > 250: control_input = [0.0,false,false]
 if tick % 15 == 0:
  var age = Time.get_ticks_msec()-last_snapshot_ms if last_snapshot_ms > 0 else -1
  var info = {"kind":"stats","role":lab_role,"mode":mode,"players":players.size(),"rtt":rtt,"age":age,"seq":snapshot_seq if mode=="host" else last_snapshot_seq,"gaps":snapshot_gaps,"tx":tx,"rx":rx,"delay":delay_ms,"pid":OS.get_process_id(),"x":players.get(1 if lab_role=="host" else multiplayer.get_unique_id(),{}).get("x",-1),"hp":enemy_hp}
  lab_socket.put_packet(JSON.stringify(info).to_utf8_buffer())
  debug_label.text = "RTT %s ms / delay %d ms each way / actors %d\nTX %d RX %d / snapshot %d / age %d ms / gaps %d" % [str(rtt) if rtt>=0 else "--",delay_ms,players.size(),tx,rx,snapshot_seq if mode=="host" else last_snapshot_seq,age,snapshot_gaps]

func _physics_process(dt):
 elapsed += dt
 tick += 1
 lab_control()
 flush_packets()
 if tick % 60 == 0 and mode != "solo":
  for peer_id in multiplayer.get_peers(): queue_packet("ping",[peer_id,Time.get_ticks_msec()])
 var typing = get_viewport().gui_get_focus_owner() is TextEdit or get_viewport().gui_get_focus_owner() is LineEdit
 var keys = LabKeys.read_keys()
 var axis = float(keys.d or keys.right)-float(keys.a or keys.left)
 var jump = keys.w or keys.up or Input.is_physical_key_pressed(KEY_SPACE)
 var attack = keys.f or keys.l or Input.is_physical_key_pressed(KEY_J)
 if lab_role != "":
  axis = control_input[0]
  jump = control_input[1]
  attack = control_input[2]
 if typing or setup_menu.visible or signal_panel.visible: axis = 0; jump = false; attack = false
 if test_mode == "client": axis = 1.0 if elapsed < 2.4 else 0.0; jump = elapsed < 2 and fmod(elapsed,1.2)<0.15; attack = true
 if mode == "client":
  if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
   queue_packet("input",[axis,jump,attack])
  elif elapsed-connected_at > (60 if OS.has_feature("web") else 8):
   solo()
   status.text = "Connection timed out • returned to solo"
 else:
  commands[1] = [axis,jump,attack,elapsed]
  if Input.is_physical_key_pressed(KEY_R): enemy_hp = 12
  enemy_x = 720.0
  for id in players:
   var s = players[id]
   var c = commands.get(id,[0.0,false,false,0.0])
   if elapsed-c[3] > 0.3: c = [0.0,false,false,elapsed]
   s.moving = abs(c[0]) > 0.1
   if s.moving: s.face = sign(c[0])
   s.x = clampf(s.x+c[0]*170*dt,24,936)
   if c[1] and not s.jump_held and s.grounded: s.vy = -340.0
   s.jump_held = c[1]
   s.vy += 900*dt
   s.y = minf(FLOOR,s.y+s.vy*dt)
   s.grounded = s.y == FLOOR
   if s.grounded: s.vy = 0.0
   s.attack = maxf(0,s.attack-dt)
   if c[2] and s.attack == 0:
    s.attack = 0.4
    s.attack_id += 1
    if enemy_hp > 0 and abs(s.x-enemy_x)<65 and abs(s.y-FLOOR)<45 and sign(enemy_x-s.x)==s.face:
     enemy_hp -= 1
     enemy_flash = 0.15
  if mode == "host" and tick % 3 == 0:
   snapshot_seq += 1
   queue_packet("snapshot",[players.duplicate(true),enemy_hp,enemy_x,snapshot_seq])
 enemy_flash = maxf(0,enemy_flash-dt)
 var local_id = multiplayer.get_unique_id() if mode == "client" else 1
 if players.has(local_id): camera.position.x = 480.0
 update_sprites()
 queue_redraw()
 if test_mode != "" and elapsed > (8 if test_mode == "host" else 6):
  if test_mode == "host" and (not test_partner_seen or enemy_hp >= 12):
   push_error("NETWORK TEST: partner missing")
   get_tree().quit(1)
  elif test_mode == "client" and (players.size() != 2 or not players.has(multiplayer.get_unique_id()) or enemy_hp >= 12):
   push_error("NETWORK TEST: authoritative state missing")
   get_tree().quit(1)
  else:
   print("NETWORK TEST PASS ",test_mode," players=",players.size()," hp=",enemy_hp," state=",players)
   get_tree().quit()

func update_sprites():
 for id in players:
  if not sprites.has(id):
   var sprite: Node2D
   if animations.has_animation("Idle"):
    sprite = AnimatedSprite2D.new()
    sprite.sprite_frames = animations
    sprite.scale = Vector2(2,2)
   else:
    sprite = Sprite2D.new()
    sprite.texture = sheet
    sprite.hframes = 5
    sprite.scale = Vector2(3,3)
   sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
   sprite.modulate = Color("ffffff") if id == 1 else Color("8ed9ed")
   add_child(sprite)
   sprites[id] = sprite
  var s = players[id]
  var sprite = sprites[id]
  sprite.flip_h = s.face < 0
  if sprite is AnimatedSprite2D:
   var clip = "Attack 1" if s.attack>0.0 else "Jump" if s.y<FLOOR else "Run" if s.moving else "Idle"
   sprite.position = Vector2(s.x,s.y-(94 if clip == "Attack 1" else 128))
   if sprite.animation != clip or (clip == "Attack 1" and sprite.get_meta("attack_id",-1) != s.attack_id):
    sprite.play(clip)
    sprite.set_frame_and_progress(0,0)
    sprite.set_meta("attack_id",s.attack_id)
  else:
   sprite.position = Vector2(s.x,s.y-34)
   sprite.frame = 4 if s.attack>0.22 else 3 if s.y<FLOOR else 1+int(elapsed*10)%2 if s.moving else 0

func _draw():
 draw_rect(Rect2(0,0,960,540),Color("17212d"))
 for x in range(0,960,32):
  for y in range(448,480,32):
   if ground_tile: draw_texture_rect(ground_tile,Rect2(x,y,32,32),false)
   else:
    draw_rect(Rect2(x,y,32,32),Color("43545d"))
    draw_rect(Rect2(x+1,y+1,30,30),Color("4d626a"),false,1)
 if enemy_hp > 0:
  draw_rect(Rect2(enemy_x-14,398,28,50),Color("fff1cc") if enemy_flash>0 else Color("ad677b"))
  draw_rect(Rect2(enemy_x-25,382,50,4),Color("442c45"))
  draw_rect(Rect2(enemy_x-25,382,50*enemy_hp/12.0,4),Color("f5b46c"))
 for s in players.values():
  if s.attack>0.22: draw_arc(Vector2(s.x+s.face*20,s.y-30),32,-1.4 if s.face>0 else 1.7,1.4 if s.face>0 else 4.5,12,Color("ffe5ad"),4)
