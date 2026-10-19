extends Node2D

var port := 27840
const CharacterView = preload("res://src/character_view.gd")
const PortableCore = preload("res://adapters/godot/portable_core.gd")
var core
const RelayCredentials = preload("res://src/relay_credentials.gd")
const ConnectionCodes = preload("res://src/connection_codes.gd")
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
var status: Label
var address: LineEdit
var mode := "solo"
var tick := 0
var elapsed := 0.0
var connected_at := 0.0
var enemy_hp := 12
var enemy_flash := 0.0
var enemy_x := 720.0
var sprites: Dictionary = {}
var sheet = preload("res://assets/knight.png")
var animations: SpriteFrames
var rtc: WebRTCPeerConnection
var local_signal: Dictionary = {}
var signal_finished := false
var rtc_started_ms := 0
var rtc_connect_ms := 0
var rtc_disconnected_ms := 0
var relay_access: LineEdit
var connection_route: OptionButton
var connection_generation := 0
var rtc_issuing := false
var rtc_route_mode := 2
var signal_out: TextEdit
var signal_in: TextEdit
var signal_panel: VBoxContainer
var pairing_role := ""
var pairing_hint: Label
var pairing_copy: Button
var pairing_paste: Button
var pairing_retry: Button
var clipboard_callback
var clipboard_copy_callback
var clipboard_copy_pending := false
var setup_menu: PanelContainer
var requested_address := "127.0.0.1"
var capture_at := -1.0
var test_mode := ""
var camera: Camera2D
var test_partner_seen := false

func _ready():
 Engine.physics_ticks_per_second = 60
 core = PortableCore.new()
 if not core.valid:
  push_error("Portable C++ core unavailable. Run python3 tools/build_core.py (native) or use the prepared Web build.")
  get_tree().quit(1)
  return
 core.outgoing_message.connect(func(bytes):
  if mode != "solo": queue_packet("gameplay",[bytes])
 )
 core.core_event.connect(func(type,_slot,_value,_fixed_tick):
  if type == 4: enemy_flash = 0.15
 )
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
 var relay_setup = VBoxContainer.new()
 relay_setup.visible = OS.has_feature("web")
 options.add_child(relay_setup)
 relay_access = LineEdit.new()
 relay_access.placeholder_text = "Private playtest access code"
 relay_access.secret = true
 relay_setup.add_child(relay_access)
 connection_route = OptionButton.new()
 for route_title in ["Direct + relay fallback","Relay only (test)","Direct only (no relay)"]: connection_route.add_item(route_title)
 relay_setup.add_child(connection_route)
 if lab_role != "":
  menu_button.hide()
  help.text = "A/D move · W jump · F attack" if lab_role == "host" else "Left/Right move · Up jump · L attack"
 if lab_role != "" or OS.has_feature("web"):
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
 pairing_hint = Label.new()
 pairing_hint.custom_minimum_size = Vector2(700,0)
 pairing_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 signal_panel.add_child(pairing_hint)
 var actions = HBoxContainer.new()
 signal_panel.add_child(actions)
 pairing_copy = Button.new()
 pairing_copy.pressed.connect(copy_signal)
 actions.add_child(pairing_copy)
 pairing_paste = Button.new()
 pairing_paste.pressed.connect(paste_signal)
 actions.add_child(pairing_paste)
 pairing_retry = Button.new()
 pairing_retry.text = "Start again"
 pairing_retry.pressed.connect(func():
  if pairing_role == "host": host()
  else: join_game()
 )
 actions.add_child(pairing_retry)
 for button in [pairing_copy,pairing_paste,pairing_retry]: button.custom_minimum_size.y = 40
 signal_out = TextEdit.new()
 signal_out.custom_minimum_size = Vector2(700,66)
 signal_out.editable = false
 signal_out.placeholder_text = "Your code appears here after ICE gathering; select and copy."
 signal_panel.add_child(signal_out)
 signal_in = TextEdit.new()
 signal_in.custom_minimum_size = Vector2(700,66)
 signal_in.placeholder_text = "Paste partner’s code here"
 signal_panel.add_child(signal_in)
 # Raw codes remain available to native tests, but browser pairing uses a normal
 # DOM text field so nested remote desktops need no Clipboard API permission.
 signal_out.visible = false
 signal_in.visible = false
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
 animations = CharacterView.make_frames()

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

func rtc_fail(message: String):
 var role = pairing_role
 solo()
 if OS.has_feature("web") and role != "":
  pairing_role = role
  signal_panel.show()
  pairing_copy.disabled = true
  pairing_paste.disabled = true
  pairing_hint.text = "Could not connect. Start again and exchange fresh codes.\nBoth players must finish: host invitation → guest reply → host accepts reply."
 else: setup_menu.show()
 status.text = message

func show_pairing(role: String):
 pairing_role = role
 pairing_copy.text = "Copy invitation" if role == "host" else "Copy reply"
 pairing_paste.text = "Enter guest reply" if role == "host" else "Enter host invitation"
 pairing_copy.disabled = true
 pairing_paste.disabled = role == "host"
 pairing_hint.text = "HOST · 1 of 2\nPreparing your invitation…" if role == "host" else "JOIN · 1 of 2\nEnter the invitation from your host. You will then send a reply back."
 setup_menu.hide()
 signal_panel.show()

func request_relay_credentials(generation: int) -> Dictionary:
 var code = relay_access.text.strip_edges()
 if code.length()<32 or code.length()>128:
  rtc_fail("Enter the private playtest access code, or choose Direct only")
  return {}
 var request = HTTPRequest.new()
 request.timeout = 12
 request.body_size_limit = 65536
 request.max_redirects = 0
 add_child(request)
 status.text = "Getting temporary relay access…"
 var error = request.request(RelayCredentials.ENDPOINT,["Authorization: Bearer "+code],HTTPClient.METHOD_POST)
 if error != OK:
  request.queue_free()
  rtc_fail("Could not request relay access")
  return {}
 var reply = await request.request_completed
 request.queue_free()
 if generation != connection_generation: return {}
 if reply[0] != HTTPRequest.RESULT_SUCCESS:
  rtc_fail("Relay endpoint unavailable • check network and retry")
  return {}
 if reply[1] != 200:
  rtc_fail("Relay access invalid or expired" if reply[1] in [401,403] else "Too many attempts • wait a minute" if reply[1]==429 else "Relay service unavailable • retry later")
  return {}
 var credentials = RelayCredentials.decode(reply[3],Time.get_unix_time_from_system())
 if credentials.is_empty(): rtc_fail("Relay returned invalid or expired credentials")
 return credentials

func rtc_begin(server: bool, session: String = "") -> bool:
 if not OS.has_feature("web"):
  status.text = "WebRTC connection codes run in the browser build. Native Host/Join uses LAN UDP."
  return false
 if rtc_issuing:
  status.text = "Getting relay access • please wait"
  return false
 reset_network()
 var generation = connection_generation
 rtc_route_mode = connection_route.selected
 var configuration = {"iceServers":[{"urls":["stun:stun.l.google.com:19302"]}],"iceTransportPolicy":"all"}
 if rtc_route_mode != 2:
  rtc_issuing = true
  var credentials = await request_relay_credentials(generation)
  if generation != connection_generation: return false
  rtc_issuing = false
  if credentials.is_empty(): return false
  configuration.iceServers = credentials.iceServers
  configuration.iceTransportPolicy = "relay" if rtc_route_mode == 1 else "all"
 rtc = WebRTCPeerConnection.new()
 var error = rtc.initialize(configuration)
 if error != OK:
  rtc_fail("WebRTC initialization failed: " + error_string(error))
  return false
 var peer = WebRTCMultiplayerPeer.new()
 error = peer.create_server() if server else peer.create_client(2)
 if error == OK: error = peer.add_peer(rtc,2 if server else 1,100)
 if error != OK:
  rtc_fail("WebRTC peer creation failed: " + error_string(error))
  return false
 multiplayer.multiplayer_peer = peer
 mode = "host" if server else "client"
 core.configure(1 if server else 2)
 sync_core_view()
 connected_at = elapsed
 rtc_started_ms = Time.get_ticks_msec()
 local_signal = {"game":"ember-coop","version":ConnectionCodes.VERSION,"protocol":ConnectionCodes.PROTOCOL,"session":Crypto.new().generate_random_bytes(16).hex_encode() if server else session,"type":"","sdp":"","ice":[]}
 rtc.session_description_created.connect(func(type, sdp):
  var description_error = rtc.set_local_description(type,sdp)
  if description_error != OK:
   rtc_fail("Local session description failed: " + error_string(description_error))
   return
  local_signal.type = type
  local_signal.sdp = sdp
 )
 rtc.ice_candidate_created.connect(func(media, index, candidate): local_signal.ice.append([media,index,candidate]))
 status.text = "Gathering connection code…"
 return true

func paste_signal():
 if OS.has_feature("web"):
  var generation = connection_generation
  clipboard_callback = JavaScriptBridge.create_callback(func(args):
   if generation != connection_generation or args.size() == 0 or str(args[0]) == "": return
   signal_in.text = str(args[0])
   rtc_accept()
  )
  var helper = JavaScriptBridge.get_interface("EmberClipboard")
  helper.paste("Enter guest reply" if pairing_role == "host" else "Enter host invitation",clipboard_callback)
 else:
  signal_in.text = DisplayServer.clipboard_get()
  rtc_accept()

func copy_signal():
 if signal_out.text == "" or clipboard_copy_pending: return
 if OS.has_feature("web"):
  var browser_clipboard = JavaScriptBridge.get_interface("EmberClipboard")
  if browser_clipboard == null:
   status.text = "Clipboard unavailable • select the upper code and use your browser’s Copy command"
   return
  var generation = connection_generation
  clipboard_copy_pending = true
  clipboard_copy_callback = JavaScriptBridge.create_callback(func(args):
   clipboard_copy_pending = false
   if generation != connection_generation: return
   var copied = args.size()>0 and args[0]==true
   status.text = "Copied • send to your partner" if copied else "Copy cancelled • try again"
   if copied:
    pairing_hint.text = "HOST · 2 of 2\nSend the invitation to your guest. Then enter their reply here." if pairing_role == "host" else "JOIN · 2 of 2\nSend this reply to your host now. Keep this page open while they accept it."
  )
  status.text = "Copying connection code…"
  browser_clipboard.copy(signal_out.text,clipboard_copy_callback)
 else:
  DisplayServer.clipboard_set(signal_out.text)
  status.text = "Code copied • send privately to partner"

func rtc_offer():
 if await rtc_begin(true):
  var error = rtc.create_offer()
  if error != OK: rtc_fail("Offer creation failed: " + error_string(error))

func rtc_accept():
 var data = ConnectionCodes.decode(signal_in.text)
 if data.is_empty():
  status.text = "Invalid/incompatible code • use a fresh code from the same game version"
  return
 if pairing_role == "client" and data.type != "offer":
  status.text = "That is a reply. Ask your host for an invitation."
  return
 if pairing_role == "host" and data.type != "answer":
  status.text = "That is an invitation. Enter your guest’s reply instead."
  return
 if data.type == "offer":
  if not await rtc_begin(false,data.session): return
 elif rtc == null or mode != "host" or local_signal.get("session") != data.session or rtc.get_signaling_state() != WebRTCPeerConnection.SIGNALING_STATE_HAVE_LOCAL_OFFER:
  status.text = "Answer does not match a pending offer • exchange fresh codes"
  return
 var error = rtc.set_remote_description(data.type,data.sdp)
 if error != OK:
  rtc_fail("Could not accept session description: " + error_string(error))
  return
 if rtc == null: return # A synchronous description callback may have failed.
 for candidate in data.ice:
  error = rtc.add_ice_candidate(candidate[0],int(candidate[1]),candidate[2])
  if error != OK:
   rtc_fail("Could not accept connection candidate: " + error_string(error))
   return
 rtc_connect_ms = Time.get_ticks_msec()
 if data.type == "answer":
  pairing_hint.text = "HOST · Connecting\nGuest reply accepted. Keep both pages open."
  pairing_paste.disabled = true
 status.text = "Connecting • relay only" if rtc_route_mode == 1 else "Connecting • direct / relay fallback" if rtc_route_mode == 0 else "Connecting directly • relay disabled"

func rtc_update(now: int):
 if rtc != null and not local_signal.is_empty():
  var state = rtc.get_connection_state()
  if state == WebRTCPeerConnection.STATE_CONNECTED: rtc_connect_ms = 0
  if state in [WebRTCPeerConnection.STATE_FAILED,WebRTCPeerConnection.STATE_CLOSED]:
   rtc_fail("Connection failed • check network and exchange fresh codes")
   return
  if state == WebRTCPeerConnection.STATE_DISCONNECTED:
   if rtc_disconnected_ms == 0: rtc_disconnected_ms = now
   if now-rtc_disconnected_ms > 10000:
    rtc_fail("Connection lost • exchange fresh codes; automatic reconnect is deferred")
    return
  else: rtc_disconnected_ms = 0
  if rtc_connect_ms > 0 and state != WebRTCPeerConnection.STATE_CONNECTED and now-rtc_connect_ms > 60000:
   rtc_fail("Connection timed out • check answer exchange and relay access")
   return
  if not signal_finished:
   if now-rtc_started_ms > 30000:
    rtc_fail("Connection gathering timed out • check browser/network and relay access")
    return
   if rtc.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE and local_signal.sdp != "":
    signal_finished = true
    if local_signal.ice.is_empty():
     rtc_fail("No connection candidates • check browser/network and connection mode")
     return
    var code = ConnectionCodes.encode(local_signal)
    if code.length() > ConnectionCodes.MAX_CODE:
     rtc_fail("Connection code too large • automatic signaling is deferred")
     return
    if ConnectionCodes.decode(code).is_empty():
     rtc_fail("Generated connection code exceeds prototype limits • automatic signaling deferred")
     return
    signal_out.text = code
    pairing_copy.disabled = false
    pairing_paste.disabled = mode != "host"
    pairing_hint.text = "HOST · 1 of 2\nCopy your invitation and send it to your guest. Then enter their reply." if mode == "host" else "JOIN · 2 of 2\nCopy your reply and send it to the host now. They must accept it to connect."
    if state != WebRTCPeerConnection.STATE_CONNECTED:
     status.text = "Connection code ready • send privately to partner"

func _process(_dt):
 rtc_update(Time.get_ticks_msec())
 if capture_at > 0 and elapsed >= capture_at:
  capture_at = -1
  get_viewport().get_texture().get_image().save_png("res://preview.png")
  get_tree().quit()

func reset_network():
 connection_generation += 1
 if OS.has_feature("web"):
  var browser_clipboard = JavaScriptBridge.get_interface("EmberClipboard")
  if browser_clipboard != null: browser_clipboard.cancel()
 rtc_issuing = false
 if multiplayer.multiplayer_peer:
  multiplayer.multiplayer_peer.close()
 multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
 if rtc != null: rtc.close()
 rtc = null
 local_signal = {}
 rtc_started_ms = 0
 rtc_connect_ms = 0
 rtc_disconnected_ms = 0
 signal_out.clear()
 signal_in.clear()
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
 for s in sprites.values(): s.queue_free()
 sprites.clear()
 enemy_hp = 12

func sync_core_view():
 var state = core.actors()
 for id in sprites.keys():
  if not state.has(id):
   sprites[id].queue_free()
   sprites.erase(id)
 players = state
 enemy_hp = core.command(10,1)
 snapshot_seq = core.command(10,11)

func _exit_tree():
 if core != null: core.close()

func solo():
 setup_menu.hide()
 signal_panel.hide()
 reset_network()
 pairing_role = ""
 mode = "solo"
 core.configure(1)
 sync_core_view()
 status.text = "Solo"

func host():
 setup_menu.hide()
 if OS.has_feature("web"):
  show_pairing("host")
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
 core.configure(1)
 sync_core_view()
 status.text = "Host / UDP %d / waiting" % port

func join_game():
 setup_menu.hide()
 if OS.has_feature("web"):
  solo()
  show_pairing("client")
  status.text = "Join your host"
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
 core.configure(2)
 sync_core_view()
 status.text = "Connecting…"
 connected_at = elapsed

func peer_joined(id: int):
 if mode == "host":
  core.peer_active(true)
  sync_core_view()
  test_partner_seen = true
  signal_panel.hide()
  status.text = "Partner joined • relay-only" if rtc != null and rtc_route_mode == 1 else "Partner joined • host authority • snapshots 20 Hz"

func peer_left(_id: int):
 if mode == "host":
  core.peer_active(false)
  sync_core_view()
  status.text = "Partner left • waiting for another"

@rpc("any_peer", "call_remote", "unreliable_ordered")
func gameplay_message(bytes: PackedByteArray):
 rx += 1
 var sender = multiplayer.get_remote_sender_id()
 var sender_slot = 0
 if mode == "host" and sender in multiplayer.get_peers(): sender_slot = 2
 if mode == "client" and sender == 1: sender_slot = 1
 if sender_slot == 0: return
 var before = core.command(10,11)
 var result = core.receive_message(sender_slot,bytes)
 if mode == "client" and result == 0:
  var sequence = core.command(10,11)
  last_snapshot_ms = Time.get_ticks_msec()
  if before > 0: snapshot_gaps += maxi(0,sequence-before-1)
  last_snapshot_seq = sequence
 sync_core_view()

@rpc("any_peer", "call_remote", "unreliable")
func ping(sent: int):
 rx += 1
 var sender = multiplayer.get_remote_sender_id()
 if sender in multiplayer.get_peers(): queue_packet("pong",[sender,sent])

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
   "gameplay":
    if mode == "client": gameplay_message.rpc_id(1,d[0])
    elif mode == "host" and not multiplayer.get_peers().is_empty(): gameplay_message.rpc(d[0])
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
  var info = {"kind":"stats","role":lab_role,"mode":mode,"players":players.size(),"rtt":rtt,"age":age,"seq":snapshot_seq if mode=="host" else last_snapshot_seq,"gaps":snapshot_gaps,"tx":tx,"rx":rx,"delay":delay_ms,"pid":OS.get_process_id(),"x":players.get(1 if lab_role=="host" else 2,{}).get("x",-1),"hp":enemy_hp}
  lab_socket.put_packet(JSON.stringify(info).to_utf8_buffer())
  debug_label.text = "RTT %s ms / delay %d ms each way / actors %d\nTX %d RX %d / snapshot %d / age %d ms / gaps %d" % [str(rtt) if rtt>=0 else "--",delay_ms,players.size(),tx,rx,snapshot_seq if mode=="host" else last_snapshot_seq,age,snapshot_gaps]

func _physics_process(dt):
 elapsed += dt
 tick += 1
 lab_control()
 flush_packets()
 if tick % 60 == 0 and mode != "solo":
  for peer_id in multiplayer.get_peers(): queue_packet("ping",[peer_id,Time.get_ticks_msec()])
 if OS.has_feature("web") and debug_label != null:
  debug_label.get_parent().visible = mode != "solo" and rtc_route_mode == 1 and not signal_panel.visible and not setup_menu.visible
  if tick % 15 == 0:
   var age = Time.get_ticks_msec()-last_snapshot_ms if last_snapshot_ms > 0 else -1
   debug_label.text = "RTT %s ms / actors %d / dummy HP %d / tick %d\nTX %d RX %d / snapshot %d / age %d ms" % [str(rtt) if rtt>=0 else "--",players.size(),enemy_hp,core.command(10,0),tx,rx,snapshot_seq if mode=="host" else last_snapshot_seq,age]
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
 if mode == "client" and rtc == null and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED and elapsed-connected_at > (60 if OS.has_feature("web") else 8):
  solo()
  status.text = "Connection timed out • returned to solo"
 if mode != "client" and Input.is_physical_key_pressed(KEY_R): core.command(11)
 core.step(axis,jump,attack)
 sync_core_view()
 enemy_flash = maxf(0,enemy_flash-dt)
 var local_id = 2 if mode == "client" else 1
 if players.has(local_id): camera.position.x = 480.0
 update_sprites()
 queue_redraw()
 if test_mode != "" and elapsed > (8 if test_mode == "host" else 6):
  if test_mode == "host" and (not test_partner_seen or enemy_hp >= 12):
   push_error("NETWORK TEST: host failed mode=%s actors=%s hp=%d tx=%d rx=%d" % [mode,str(players),enemy_hp,tx,rx])
   get_tree().quit(1)
  elif test_mode == "client" and (players.size() != 2 or not players.has(2) or enemy_hp >= 12):
   push_error("NETWORK TEST: guest failed mode=%s actors=%s hp=%d tx=%d rx=%d" % [mode,str(players),enemy_hp,tx,rx])
   get_tree().quit(1)
  else:
   print("NETWORK TEST PASS ",test_mode," players=",players.size()," hp=",enemy_hp," state=",players)
   get_tree().quit()

func update_sprites():
 for id in players:
  if not sprites.has(id):
   var sprite: Node2D
   if animations.has_animation("Idle"):
    sprite = CharacterView.new()
    sprite.sprite_frames = animations
   else:
    sprite = Sprite2D.new()
    sprite.texture = sheet
    sprite.hframes = 5
    sprite.scale = Vector2(1.5,1.5)
   if not sprite is AnimatedSprite2D: sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
   sprite.modulate = Color("ffffff") if id == 1 else Color("8ed9ed")
   add_child(sprite)
   sprites[id] = sprite
  var s = players[id]
  var sprite = sprites[id]
  sprite.flip_h = s.face < 0
  if sprite is AnimatedSprite2D:
   sprite.present(s)
  else:
   sprite.position = Vector2(s.x,s.y-17)
   sprite.frame = 4 if s.animation == 3 else 3 if s.animation == 2 else 1+int(elapsed*10)%2 if s.animation in [1,4] else 0

func _draw():
 draw_rect(Rect2(0,0,960,540),Color("17212d"))
 for x in range(0,960,32):
  for y in range(448,480,32):
   if ground_tile: draw_texture_rect(ground_tile,Rect2(x,y,32,32),false)
   else:
    draw_rect(Rect2(x,y,32,32),Color("43545d"))
    draw_rect(Rect2(x+1,y+1,30,30),Color("4d626a"),false,1)
 if enemy_hp > 0:
  draw_rect(Rect2(enemy_x-14,384,28,64),Color("fff1cc") if enemy_flash>0 else Color("ad677b"))
  draw_rect(Rect2(enemy_x-25,370,50,4),Color("442c45"))
  draw_rect(Rect2(enemy_x-25,370,50*enemy_hp/12.0,4),Color("f5b46c"))
