extends Node
# HTTP signaling adapter only. The portable core never sees room/auth data.
const ENDPOINT := "https://ember-coop-credentials.ember-bridge-playtests.workers.dev/v1/lobby"
const FAST_SYNC_MS := 500
const FAST_SYNC_WINDOW_MS := 8000
const SYNC_MS := 2000
var game
var panel: VBoxContainer
var rows: VBoxContainer
var room_name: LineEdit
var player_name_input: LineEdit
var player_name_row: HBoxContainer
var hint: Label
var create_button: Button
var refresh_button: Button
var generation := 0
var active := false
var busy := false
var listing_busy := false
var directory_generation := 0
var next_poll := 0
var room_id := ""
var seat := ""
var role := ""
var accepted := false
var published := false
var transport_established := false
var failures := 0
var listed_rooms := ""
var fast_poll_until := 0
var retry_supported := false
var retry_requested := false
var setup_failed := false
var epoch := 0

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
 game.bind_browser_entry(room_name,"Room name",32)
 player_name_input = LineEdit.new()
 player_name_input.placeholder_text = "Your name"
 player_name_input.text = game.player_name
 player_name_input.max_length = 24
 player_name_row = HBoxContainer.new()
 var name_label = Label.new()
 name_label.text = "Name"
 name_label.custom_minimum_size.x = 48
 player_name_row.add_child(name_label)
 player_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 player_name_row.add_child(player_name_input)
 panel.add_child(player_name_row)
 game.bind_browser_entry(player_name_input,"Your player name",24)
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

func now_ms() -> int: return Time.get_ticks_msec()

func start_fast_sync():
 # One bounded burst per epoch keeps the two-player polling budget finite.
 if fast_poll_until == 0: fast_poll_until = now_ms()+FAST_SYNC_WINDOW_MS

func sync_delay_ms() -> int:
 return FAST_SYNC_MS if now_ms()<fast_poll_until else SYNC_MS

func request_data(data: Dictionary, request_generation: int) -> Dictionary:
 var request = HTTPRequest.new()
 request.timeout = 10
 request.body_size_limit = 70000
 request.max_redirects = 0
 add_child(request)
 data.version = 1
 data.retryCapable = true
 if game.diagnostics != null: data.diagnostic = game.diagnostics.id
 var error = request.request(ENDPOINT,["Authorization: Bearer "+game.invite_key(),"Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify(data))
 if error != OK:
  request.queue_free()
  return {"error":"Network unavailable"}
 var response = await request.request_completed
 request.queue_free()
 if request_generation != generation or (game.diagnostics != null and data.get("diagnostic", "") != game.diagnostics.id): return {}
 if response[0] != HTTPRequest.RESULT_SUCCESS:
  if game.diagnostics != null:
   game.diagnostics.record("http",{"action":str(data.get("action","unknown")),"status":-1,"code":"unknown_error"})
   game.diagnostics.flush()
  return {"error":"Network unavailable"}
 var value = JSON.parse_string(response[3].get_string_from_utf8())
 if not value is Dictionary: return {"error":"Room service unavailable"}
 if game.diagnostics != null:
  game.diagnostics.record("http",{"action":str(data.get("action","unknown")),"status":int(response[1]),"code":safe_code(value.get("error","ok"))})
 if response[1] != 200:
  if game.diagnostics != null: game.diagnostics.flush()
  return {"error":service_error(response[1],value.get("error","unknown_error")),"status":int(response[1]),"code":safe_code(value.get("error","unknown_error"))}
 if value.get("version") != 1: return {"error":"Incompatible room service"}
 return value

# Display only bounded machine codes, never arbitrary response bodies or secrets.
func safe_code(code) -> String:
 var known = ["access_denied","origin_denied","rate_limited","limiter_unavailable","issuer_not_configured","lobby_not_configured","lobby_unavailable","invalid_lobby_request","relay_provider_failed","room_expired","room_full","own_room","signal_already_set","session_mismatch","seat_denied","invitation_expired","invalid_request","invalid_seat","invalid_room","invalid_name","invalid_signal","invalid_ready","rooms_full","retry_unsupported"]
 return str(code) if code is String and (code in known or code == "ok") else "unknown_error"

func service_error(status: int, code) -> String:
 var reason = safe_code(code)
 if reason == "retry_unsupported": return "Both players must reload the game before a compatibility retry (HTTP %d · %s)" % [status,reason]
 var message = "Access code invalid or expired" if status in [401,403] else "Too many requests; wait a minute" if status == 429 else "Room full, closed or expired; refresh and try again" if status in [404,409] else "Room service unavailable"
 return "%s (HTTP %d · %s)" % [message,status,reason]

func open():
 game.solo()
 var code = game.invite_key()
 if code.length()<32 or code.length()>128:
  game.invite.open("Enter your invite key.")
  return
 game.diagnostics.begin()
 active = true
 panel.show()
 room_name.show()
 player_name_row.show()
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
 if not active or busy or listing_busy or room_id != "": return
 listing_busy = true
 var directory_attempt = directory_generation
 var attempt = generation
 var result = await request_data({"action":"list"},attempt)
 if attempt != generation or directory_attempt != directory_generation: return
 listing_busy = false
 next_poll = now_ms()+5000
 if result.has("error"):
  hint.text = result.error + " · refreshing…" if int(result.get("status",0)) not in [401,403,429] else result.error
  # Failed refreshes invalidate the buttons too. Never offer rooms from a
  # previous successful response after their freshness can no longer be checked.
  listed_rooms = ""
  clear_rows()
  if int(result.get("status",0)) in [401,403,429]: next_poll = 1 << 60
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
 var chosen_name = preload("res://src/player_chat.gd").clean_text(player_name_input.text,24)
 if chosen_name.is_empty():
  hint.text = "Enter your player name (1–24 characters)"
  player_name_input.grab_focus()
  return
 # Directory reads must not swallow a Join/Create click. Retire their UI
 # callbacks before starting membership, including late errors from that read.
 directory_generation += 1
 listing_busy = false
 game.player_name = chosen_name
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
  if result.get("code","") == "room_expired":
   listed_rooms = ""
   clear_rows()
   next_poll = 0
  return
 if not result.get("id") is String or result.get("role") not in ["host","client"]:
  hint.text = "Invalid room response"
  return
 room_id = result.id
 role = result.role
 fast_poll_until = 0
 if role == "client": start_fast_sync()
 retry_supported = result.get("retrySupported",false) == true
 accepted = false
 published = false
 transport_established = false
 failures = 0
 clear_rows()
 room_name.hide()
 player_name_row.hide()
 create_button.hide()
 refresh_button.hide()
 game.diagnostics.record("room",{"room":room_id,"role":role})
 hint.text = "Room %s · waiting for partner… · diagnostic %s" % [room_id,game.diagnostics.id]
 game.pairing_role = role
 game.status.text = "Preparing private room…"
 # Reserve/discover first. Allocate TURN and gather an offer only when the
 # partner joins, so a long wait never leaves stale relay credentials in a room.
 next_poll = 0

func can_retry_compatibility() -> bool:
 if not active or room_id.is_empty(): return false
 remember_connection()
 return not transport_established and epoch == 0 and game.rtc_route_mode != 3 and retry_supported

func retry_compatibility(source: String) -> bool:
 if source not in ["rtc_terminal","connect_timeout","gather_timeout","no_candidates","disconnect_timeout","multiplayer_connect_failed"] or not can_retry_compatibility():
  return false
 if setup_failed: return true
 game.reset_network()
 game.mode = "solo"
 game.core.configure(1)
 game.sync_core_view()
 setup_failed = true
 retry_requested = true
 next_poll = 0
 game.setup_menu.hide()
 game.signal_panel.hide()
 panel.visible = not game.settings_menu.visible
 hint.text = "Switching both players to Compatibility (TLS 443)…"
 return true

func restart_compatibility(attempt: int):
 epoch = 1
 fast_poll_until = now_ms()+FAST_SYNC_WINDOW_MS
 setup_failed = false
 retry_requested = false
 accepted = false
 published = false
 transport_established = false
 game.reset_network()
 game.mode = "solo"
 game.core.configure(1)
 game.sync_core_view()
 if not game.setup_menu.visible and not game.settings_menu.visible: panel.show()
 game.pairing_role = role
 hint.text = "Retrying both players with Compatibility (TLS 443)…"
 busy = true
 if role == "host": await game.rtc_offer()
 if attempt != generation: return
 busy = false
 next_poll = 0

func remember_connection():
 # Room readiness is sticky on the server; retain it here as well. A brief
 # ICE interruption must not make an established game depend on setup again.
 if game.rtc != null and game.rtc.get_connection_state() == WebRTCPeerConnection.STATE_CONNECTED:
  transport_established = true
  panel.hide()

func _process(_dt):
 if active: remember_connection()
 if not active or busy or now_ms()<next_poll: return
 if room_id.is_empty():
  if panel.visible: refresh()
 else: sync_room()

func sync_room():
 busy = true
 var attempt = generation
 remember_connection()
 var signal_code = game.signal_out.text if game.signal_finished and not published else ""
 var requesting_retry = retry_requested
 var result = await request_data({"action":"sync","id":room_id,"seat":seat,"signal":signal_code,"ready":transport_established,"epoch":epoch,"retryTls":requesting_retry},attempt)
 if attempt != generation: return
 # ICE can connect while HTTP is in flight, then temporarily disconnect.
 # Keep established sessions under the transport's own liveness deadlines.
 remember_connection()
 busy = false
 next_poll = now_ms()+sync_delay_ms()
 if result.has("error"):
  # A connected game no longer depends on its signaling room. The other peer
  # may already have completed cleanup; never tear gameplay down for this.
  if transport_established:
   game.diagnostics.record("lobby_end",{"cause":"error_after_connected"})
   active = false
   panel.hide()
   return
  if result.get("code","") == "room_expired":
   game.rtc_fail("Room expired or closed · choose a fresh room","lobby_errors")
   open()
   hint.text = "Previous room expired or closed · choose another or create one"
   return
  if int(result.get("status",0)) in [401,403,429] or result.get("code","") == "retry_unsupported":
   game.rtc_fail("Room setup failed: "+str(result.error),"lobby_errors")
   return
  next_poll = now_ms()+SYNC_MS
  failures += 1
  hint.text = result.error + " · diagnostic " + game.diagnostics.id + " · retrying…"
  if failures >= 3: game.rtc_fail("Room setup failed: " + str(result.error) + " · open Private rooms and retry","lobby_errors")
  return
 failures = 0
 retry_supported = result.get("retrySupported",false) == true
 if result.get("players",1) == 2: start_fast_sync()
 next_poll = now_ms()+sync_delay_ms()
 # A failure or completed gathering can arrive while this old sync is in flight.
 # Send its newly queued work immediately, without overlapping HTTP requests.
 if (retry_requested and not requesting_retry) or (signal_code.is_empty() and game.signal_finished and not published):
  next_poll = 0
 if result.get("epoch",0) == 1 and epoch == 0:
  await restart_compatibility(attempt)
  return
 if setup_failed:
  if not retry_supported or requesting_retry:
   game.rtc_fail("Both players must reload the game before a compatibility retry","retry_unsupported")
  return
 if not signal_code.is_empty(): published = true
 if transport_established:
  panel.hide()
  # Continue briefly until both peers acknowledge; the server clears signals.
  if result.get("complete",false):
   game.diagnostics.record("lobby_end",{"cause":"complete"})
   active = false
  return
 var route_hint = "Compatibility (TLS 443)" if epoch == 1 else "connecting automatically…"
 hint.text = "Room %s · %s" % [room_id,route_hint if result.get("players",1)==2 else "waiting for partner · up to one hour"]
 game.status.text = "Private room · Compatibility (TLS 443)" if epoch == 1 else "Private room · automatic connection setup"
 if role == "host" and result.get("players",1) == 2 and game.rtc == null:
  busy = true
  await game.rtc_offer()
  if attempt != generation: return
  busy = false
  next_poll = 0
  return
 var incoming = result.get("signal","")
 if not accepted and incoming is String and not incoming.is_empty():
  if game.ConnectionCodes.decode(incoming).is_empty():
   game.rtc_fail("Incompatible room · reload both players and create a fresh room")
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
 directory_generation += 1
 listing_busy = false
 epoch = 0
 fast_poll_until = 0
 retry_supported = false
 retry_requested = false
 setup_failed = false
 active = false
 busy = false
 room_id = ""
 seat = ""
 role = ""
 accepted = false
 published = false
 transport_established = false
 panel.hide()
 listed_rooms = ""
 clear_rows()
 create_button.disabled = false
 if not old_room.is_empty():
  # Best effort; leases/alarm clean up when the tab/network disappears.
  request_data({"action":"leave","id":old_room,"seat":old_seat},generation)
