extends Node
# HTTP signaling adapter only. The portable core never sees room/auth data.
const ENDPOINT := "https://ember-coop-credentials.ember-bridge-playtests.workers.dev/v1/lobby"
var game
var panel: VBoxContainer
var rows: VBoxContainer
var room_name: LineEdit
var hint: Label
var create_button: Button
var refresh_button: Button
var generation := 0
var active := false
var busy := false
var next_poll := 0
var room_id := ""
var seat := ""
var role := ""
var accepted := false
var published := false
var failures := 0
var listed_rooms := ""

func setup(owner_game, canvas):
 game = owner_game
 panel = VBoxContainer.new()
 panel.position = Vector2(16,125)
 panel.custom_minimum_size.x = 380
 panel.add_theme_constant_override("separation",8)
 canvas.add_child(panel)
 panel.hide()
 hint = Label.new()
 hint.text = "Private playtest rooms"
 hint.custom_minimum_size.x = 380
 hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 panel.add_child(hint)
 room_name = LineEdit.new()
 room_name.placeholder_text = "Room name"
 room_name.text = "Co-op room"
 room_name.max_length = 32
 panel.add_child(room_name)
 create_button = Button.new()
 create_button.text = "Create room"
 create_button.custom_minimum_size.y = 36
 create_button.pressed.connect(func(): enter_room("create"))
 panel.add_child(create_button)
 refresh_button = Button.new()
 refresh_button.text = "Refresh rooms"
 refresh_button.custom_minimum_size.y = 36
 refresh_button.pressed.connect(refresh)
 panel.add_child(refresh_button)
 rows = VBoxContainer.new()
 panel.add_child(rows)
 var back = Button.new()
 back.text = "Back / leave room"
 back.custom_minimum_size.y = 36
 back.pressed.connect(func(): game.solo(); game.setup_menu.show())
 panel.add_child(back)

func request_data(data: Dictionary, request_generation: int) -> Dictionary:
 var request = HTTPRequest.new()
 request.timeout = 10
 request.body_size_limit = 70000
 request.max_redirects = 0
 add_child(request)
 data.version = 1
 var error = request.request(ENDPOINT,["Authorization: Bearer "+game.relay_access.text.strip_edges(),"Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify(data))
 if error != OK:
  request.queue_free()
  return {"error":"Network unavailable"}
 var response = await request.request_completed
 request.queue_free()
 if request_generation != generation: return {}
 if response[0] != HTTPRequest.RESULT_SUCCESS: return {"error":"Network unavailable"}
 var value = JSON.parse_string(response[3].get_string_from_utf8())
 if not value is Dictionary: return {"error":"Room service unavailable"}
 if response[1] != 200:
  return {"error":"Access code invalid or expired" if response[1] in [401,403] else "Too many requests; wait a minute" if response[1]==429 else "Room full, closed or expired; refresh and try again" if response[1] in [404,409] else "Room service unavailable"}
 if value.get("version") != 1: return {"error":"Incompatible room service"}
 return value

func open():
 game.solo()
 var code = game.relay_access.text.strip_edges()
 if code.length()<32 or code.length()>128:
  game.setup_menu.show()
  game.status.text = "Enter your private playtest access code first"
  game.relay_access.grab_focus()
  return
 active = true
 panel.show()
 room_name.show()
 create_button.show()
 refresh_button.show()
 room_name.grab_focus()
 hint.text = "Loading private rooms…"
 game.status.text = "Private playtest lobby"
 refresh()

func clear_rows():
 for row in rows.get_children():
  rows.remove_child(row)
  row.queue_free()

func refresh():
 if not active or busy or room_id != "": return
 busy = true
 var attempt = generation
 var result = await request_data({"action":"list"},attempt)
 if attempt != generation: return
 busy = false
 next_poll = Time.get_ticks_msec()+5000
 if result.has("error"):
  hint.text = result.error
  next_poll = 1 << 60 # Explicit Refresh retries authentication/service failures.
  return
 var rooms = result.get("rooms",[])
 if not rooms is Array: return
 hint.text = "Private rooms · choose one or create yours" if not rooms.is_empty() else "No open rooms · create one for your partner"
 var listing = JSON.stringify(rooms)
 if listing == listed_rooms: return
 listed_rooms = listing
 clear_rows()
 # Keep the small game viewport bounded; server supports 32, show a scroll list.
 var scroll = ScrollContainer.new()
 scroll.custom_minimum_size.y = 100
 scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
 rows.add_child(scroll)
 var list = VBoxContainer.new()
 list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 scroll.add_child(list)
 for item in rooms:
  if not item is Dictionary or not item.get("id") is String or not item.get("name") is String: continue
  var button = Button.new()
  button.text = "Join %s · 1/2 · %s" % [item.id,item.name]
  button.custom_minimum_size.y = 32
  button.clip_text = true
  button.tooltip_text = button.text
  button.pressed.connect(func(): enter_room("join",item.id))
  list.add_child(button)

func enter_room(action: String, id: String = ""):
 if busy or room_id != "" or not active: return
 if action == "create" and room_name.text.strip_edges().is_empty():
  hint.text = "Enter a room name first"
  room_name.grab_focus()
  return
 hint.text = "Creating room…" if action == "create" else "Joining room…"
 busy = true
 create_button.disabled = true
 var attempt = generation
 # Each new attempt receives an unguessable membership token, never displayed.
 seat = Crypto.new().generate_random_bytes(16).hex_encode()
 var result = await request_data({"action":action,"id":id,"name":room_name.text.strip_edges(),"seat":seat},attempt)
 if attempt != generation: return
 busy = false
 create_button.disabled = false
 if result.has("error"):
  hint.text = result.error
  return
 if not result.get("id") is String or result.get("role") not in ["host","client"]:
  hint.text = "Invalid room response"
  return
 room_id = result.id
 role = result.role
 accepted = false
 published = false
 failures = 0
 clear_rows()
 room_name.hide()
 create_button.hide()
 refresh_button.hide()
 hint.text = "Room %s · waiting for partner…" % room_id
 game.pairing_role = role
 game.status.text = "Preparing private room…"
 busy = true
 if role == "host": await game.rtc_offer()
 if attempt != generation: return
 busy = false
 next_poll = 0

func _process(_dt):
 if not active or busy or Time.get_ticks_msec()<next_poll: return
 if room_id.is_empty():
  if panel.visible: refresh()
 else: sync_room()

func sync_room():
 busy = true
 var attempt = generation
 var connected = game.rtc != null and game.rtc.get_connection_state() == WebRTCPeerConnection.STATE_CONNECTED
 var signal_code = game.signal_out.text if game.signal_finished and not published else ""
 var result = await request_data({"action":"sync","id":room_id,"seat":seat,"signal":signal_code,"ready":connected},attempt)
 if attempt != generation: return
 busy = false
 next_poll = Time.get_ticks_msec()+2000
 if result.has("error"):
  # A connected game no longer depends on its signaling room. The other peer
  # may already have completed cleanup; never tear gameplay down for this.
  if connected:
   active = false
   panel.hide()
   return
  failures += 1
  hint.text = result.error + " · retrying…"
  if failures >= 3: game.rtc_fail("Room setup failed · open Private rooms and retry")
  return
 failures = 0
 if not signal_code.is_empty(): published = true
 if connected:
  panel.hide()
  # Continue briefly until both peers acknowledge; the server clears signals.
  if result.get("complete",false): active = false
  return
 hint.text = "Room %s · %s" % [room_id,"connecting automatically…" if result.get("players",1)==2 else "waiting for partner…"]
 game.status.text = "Private room · automatic connection setup"
 var incoming = result.get("signal","")
 if not accepted and incoming is String and not incoming.is_empty():
  if game.ConnectionCodes.decode(incoming).is_empty():
   game.rtc_fail("Invalid room connection data · try a new room")
   return
  accepted = true
  game.signal_in.text = incoming
  busy = true
  await game.rtc_accept()
  if attempt != generation: return
  busy = false

func close():
 var old_room = room_id
 var old_seat = seat
 generation += 1
 active = false
 busy = false
 room_id = ""
 seat = ""
 role = ""
 accepted = false
 published = false
 panel.hide()
 listed_rooms = ""
 clear_rows()
 create_button.disabled = false
 if not old_room.is_empty():
  # Best effort; leases/alarm clean up when the tab/network disappears.
  request_data({"action":"leave","id":old_room,"seat":old_seat},generation)
