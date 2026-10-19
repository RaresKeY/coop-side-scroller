extends Node2D

const PORT = 27840
const FLOOR = 440.0
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
var signal_out: TextEdit
var signal_in: TextEdit
var signal_panel: VBoxContainer
var preview_clip := ""
var capture_at := -1.0
var test_mode := ""
var camera: Camera2D
var test_partner_seen := false

func _ready():
 camera = Camera2D.new()
 camera.position = Vector2(480,270)
 add_child(camera)
 build_animations()
 var canvas = CanvasLayer.new()
 add_child(canvas)
 var panel = VBoxContainer.new()
 panel.position = Vector2(26,18)
 canvas.add_child(panel)
 var title = Label.new()
 title.text = "EMBER BRIDGE   /   PROTOTYPE"
 title.add_theme_font_size_override("font_size",24)
 panel.add_child(title)
 var row = HBoxContainer.new()
 panel.add_child(row)
 for item in [["Solo",solo],["Host",host],["Join",join_game]]:
  var b = Button.new()
  b.text = item[0]
  b.pressed.connect(item[1])
  style_button(b)
  row.add_child(b)
 address = LineEdit.new()
 address.text = "127.0.0.1"
 address.custom_minimum_size.x = 200
 row.add_child(address)
 address.visible = not OS.has_feature("web")
 status = Label.new()
 panel.add_child(status)
 var help = Label.new()
 help.text = "A/D or arrows: move   •   Space: jump   •   J: strike   •   R: reset dummy"
 panel.add_child(help)
 var clips = HBoxContainer.new()
 panel.add_child(clips)
 for clip in ["Auto", "Idle", "Walk", "Run", "Jump", "Attack 1", "Hurt", "Dead"]:
  var button = Button.new()
  button.text = clip
  button.pressed.connect(func(): preview_clip = "" if clip == "Auto" else clip)
  style_button(button)
  clips.add_child(button)
 var net_button = Button.new()
 net_button.text = "P2P connection codes (Web)"
 net_button.pressed.connect(func(): signal_panel.visible = not signal_panel.visible)
 panel.add_child(net_button)
 signal_panel = VBoxContainer.new()
 signal_panel.position = Vector2(26,218)
 signal_panel.visible = false
 canvas.add_child(signal_panel)
 var explanation = Label.new()
 explanation.text = "1 Host: Create offer -> send code.  2 Guest: paste -> Accept.\n3 Guest sends answer. Host pastes -> Accept. Wait for Connected."
 signal_panel.add_child(explanation)
 var actions = HBoxContainer.new()
 signal_panel.add_child(actions)
 for item in [["Create offer",rtc_offer],["Accept pasted code",rtc_accept],["Copy my code",copy_signal]]:
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
 for arg in OS.get_cmdline_user_args():
  if arg == "--capture": capture_at = 1.0
  if arg == "--test-host":
   test_mode = "host"
   host()
  if arg == "--test-client":
   test_mode = "client"
   join_game()
 multiplayer.peer_connected.connect(peer_joined)
 multiplayer.peer_disconnected.connect(peer_left)
 multiplayer.connected_to_server.connect(func(): status.text = "Connected • host simulates combat and movement"; connected_at = elapsed)
 multiplayer.connection_failed.connect(func(): solo(); status.text = "Connection failed. Check address / UDP 27840.")
 multiplayer.server_disconnected.connect(func(): solo(); status.text = "Host disconnected • returned to solo")

func build_animations():
 animations = SpriteFrames.new()
 animations.remove_animation("default")
 for clip in ["Idle","Walk","Run","Jump","Attack 1","Hurt","Dead"]:
  var path = "res://assets/private/character/" + clip + ".png"
  if not ResourceLoader.exists(path): continue
  var texture = load(path) as Texture2D
  animations.add_animation(clip)
  animations.set_animation_speed(clip,12)
  animations.set_animation_loop(clip,clip in ["Idle","Walk","Run"])
  for i in range(texture.get_width()/128):
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
 if server: peer.create_server()
 else: peer.create_client(2)
 error = peer.add_peer(rtc,2 if server else 1)
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
  if rtc.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE and local_signal.sdp != "":
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
 players.clear()
 commands.clear()
 for s in sprites.values(): s.queue_free()
 sprites.clear()
 enemy_hp = 12

func spawn(id: int):
 players[id] = {"x":180.0 if id == 1 else 260.0,"y":FLOOR,"vy":0.0,"face":1.0,"attack":0.0,"moving":false,"jump_held":false}

func solo():
 reset_network()
 mode = "solo"
 spawn(1)
 status.text = "Solo • Host/Join to try direct P2P" if OS.has_feature("web") else "Solo • start Host, then Join from a second instance"

func host():
 if OS.has_feature("web"):
  signal_panel.show()
  rtc_offer()
  return
 reset_network()
 var peer = ENetMultiplayerPeer.new()
 var error = peer.create_server(PORT,1)
 if error != OK:
  solo()
  status.text = "Host failed: " + error_string(error)
  return
 multiplayer.multiplayer_peer = peer
 mode = "host"
 spawn(1)
 status.text = "Hosting • UDP 27840 • waiting for one partner"

func join_game():
 if OS.has_feature("web"):
  signal_panel.show()
  status.text = "Paste host offer into connection codes, then Accept"
  return
 reset_network()
 var peer = ENetMultiplayerPeer.new()
 var error = peer.create_client(address.text.strip_edges(),PORT)
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
 if mode != "host" or not is_finite(axis): return
 var id = multiplayer.get_remote_sender_id()
 if players.has(id): commands[id] = [clampf(axis,-1,1),jump,attack,elapsed]

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func snapshot(state: Dictionary, hp: int, ex: float):
 if mode != "client": return
 players = state
 enemy_hp = hp
 enemy_x = ex

func _physics_process(dt):
 elapsed += dt
 tick += 1
 var typing = get_viewport().gui_get_focus_owner() is TextEdit or get_viewport().gui_get_focus_owner() is LineEdit
 var axis = float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
 var jump = Input.is_physical_key_pressed(KEY_SPACE)
 var attack = Input.is_physical_key_pressed(KEY_J)
 if typing: axis = 0; jump = false; attack = false
 if test_mode == "client": axis = 1.0 if elapsed < 2.4 else 0.0; jump = elapsed < 2 and fmod(elapsed,1.2)<0.15; attack = true
 if mode == "client":
  if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
   submit_input.rpc_id(1,axis,jump,attack)
  elif elapsed-connected_at > (60 if OS.has_feature("web") else 8):
   solo()
   status.text = "Connection timed out • returned to solo"
 else:
  commands[1] = [axis,jump,attack,elapsed]
  if Input.is_physical_key_pressed(KEY_R): enemy_hp = 12
  enemy_x = 720 + sin(elapsed*0.8)*35
  for id in players:
   var s = players[id]
   var c = commands.get(id,[0.0,false,false,0.0])
   if elapsed-c[3] > 0.3: c = [0.0,false,false,elapsed]
   s.moving = abs(c[0]) > 0.1
   if s.moving: s.face = sign(c[0])
   s.x = clampf(s.x+c[0]*170*dt,24,1896)
   if c[1] and not s.jump_held and s.y >= FLOOR: s.vy = -340.0
   s.jump_held = c[1]
   s.vy += 900*dt
   s.y = minf(FLOOR,s.y+s.vy*dt)
   if s.y == FLOOR: s.vy = 0.0
   s.attack = maxf(0,s.attack-dt)
   if c[2] and s.attack == 0:
    s.attack = 0.4
    if enemy_hp > 0 and abs(s.x-enemy_x)<65 and abs(s.y-FLOOR)<45 and sign(enemy_x-s.x)==s.face:
     enemy_hp -= 1
     enemy_flash = 0.15
  if mode == "host" and tick % 3 == 0: snapshot.rpc(players,enemy_hp,enemy_x)
 enemy_flash = maxf(0,enemy_flash-dt)
 var local_id = multiplayer.get_unique_id() if mode == "client" else 1
 if players.has(local_id): camera.position.x = clampf(players[local_id].x,480,1440)
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
   sprite.modulate = Color("ffffff") if id == 1 else Color("8ed9ed")
   add_child(sprite)
   sprites[id] = sprite
  var s = players[id]
  var sprite = sprites[id]
  sprite.flip_h = s.face < 0
  if sprite is AnimatedSprite2D:
   sprite.position = Vector2(s.x,s.y-128)
   var clip = "Attack 1" if s.attack>0.0 else "Jump" if s.y<FLOOR else "Run" if s.moving else "Idle"
   if preview_clip != "": clip = preview_clip
   if sprite.animation != clip: sprite.play(clip)
  else:
   sprite.position = Vector2(s.x,s.y-34)
   sprite.frame = 4 if s.attack>0.22 else 3 if s.y<FLOOR else 1+int(elapsed*10)%2 if s.moving else 0

func _draw():
 draw_rect(Rect2(0,0,1920,540),Color("101a2d"))
 for i in range(60):
  draw_circle(Vector2(fmod(i*137.0,1920),145+fmod(i*37.0,210)),1,Color("718aa2"))
 draw_circle(Vector2(800,205),42,Color("e6bf87"))
 for i in range(22):
  draw_rect(Rect2(i*96,260+sin(i*2.0)*40,56,200),Color("1b2e41"))
  draw_rect(Rect2(i*96+12,270+sin(i*2.0)*40,7,180),Color("253c50"))
 draw_rect(Rect2(0,440,1920,100),Color("283841"))
 draw_rect(Rect2(0,440,1920,5),Color("71a299"))
 for x in range(0,1920,32):
  draw_rect(Rect2(x+2,451,28,14),Color("3c4b50"))
  draw_rect(Rect2(x+17,471,28,14),Color("34434c"))
 if enemy_hp > 0:
  draw_rect(Rect2(enemy_x-14,390,28,50),Color("fff1cc") if enemy_flash>0 else Color("ad677b"))
  draw_rect(Rect2(enemy_x-23,401,46,8),Color("b68886"))
  draw_rect(Rect2(enemy_x-25,375,50,4),Color("442c45"))
  draw_rect(Rect2(enemy_x-25,375,50*enemy_hp/12.0,4),Color("f5b46c"))
 for s in players.values():
  if s.attack>0.22:
   draw_arc(Vector2(s.x+s.face*20,s.y-30),32,-1.4 if s.face>0 else 1.7,1.4 if s.face>0 else 4.5,12,Color("ffe5ad"),4)
