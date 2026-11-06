extends Node
# The invite exists only for this page/session. Persistent verification is server-side.
var game
var panel: Control
var entry: LineEdit
var confirm: Button
var hint: Label
var key := ""
var pending_key := ""
var generation := 0
# Field callbacks survive retries; every HTTP attempt has its own fence.
var validation_id := 0
var request: HTTPRequest
var helper
var callback
var last_rect := Rect2()

func setup(owner_game, canvas):
 game = owner_game
 panel = Control.new()
 panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 canvas.add_child(panel)
 var shade = ColorRect.new()
 shade.color = Color(0.02,0.025,0.03,0.85)
 shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 panel.add_child(shade)
 var center = CenterContainer.new()
 center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 panel.add_child(center)
 var frame = PanelContainer.new()
 frame.custom_minimum_size.x = 380
 game.style_panel(frame)
 center.add_child(frame)
 var column = VBoxContainer.new()
 column.add_theme_constant_override("separation",12)
 frame.add_child(column)
 var title = Label.new()
 title.text = "Playtest invite"
 title.add_theme_font_size_override("font_size",24)
 column.add_child(title)
 entry = LineEdit.new()
 entry.placeholder_text = "Invite key"
 entry.secret = true
 entry.max_length = 128
 entry.custom_minimum_size.y = 42
 column.add_child(entry)
 confirm = Button.new()
 confirm.text = "Continue"
 game.style_button(confirm)
 confirm.custom_minimum_size.y = 42
 column.add_child(confirm)
 hint = Label.new()
 hint.custom_minimum_size.x = 340
 hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 hint.add_theme_font_size_override("font_size",14)
 column.add_child(hint)
 confirm.pressed.connect(submit)
 entry.text_submitted.connect(func(_value): submit())
 if OS.has_feature("web"):
  helper = JavaScriptBridge.get_interface("EmberInviteField")
  entry.editable = false
  entry.focus_mode = Control.FOCUS_NONE
  confirm.gui_input.connect(func(event):
   if event is InputEventKey and event.pressed and event.keycode == KEY_TAB and helper != null:
    confirm.accept_event()
    helper.focus()
  )
 panel.hide()

func active() -> bool: return panel != null and panel.visible
func busy() -> bool: return not pending_key.is_empty()

static func valid_key(value: String) -> bool:
 if value.length()<32 or value.length()>128: return false
 for i in value.length():
  if value.unicode_at(i)<33 or value.unicode_at(i)>126: return false
 return true

func open(message := ""):
 cancel_request()
 key = ""
 game.solo()
 game.setup_menu.hide()
 game.signal_panel.hide()
 game.settings_menu.hide()
 game.header.hide()
 game.settings_button.hide()
 panel.show()
 hint.text = message
 entry.clear()
 confirm.disabled = false
 if helper != null:
  var attempt = generation
  callback = JavaScriptBridge.create_callback(func(args):
   if attempt != generation or not active() or args.size()<2: return
   if str(args[0]) == "submit": begin(str(args[1]))
   elif str(args[0]) == "focus":
    helper.blur()
    confirm.grab_focus()
  )
  helper.open(callback,128)
  call_deferred("place_field")
 else: entry.grab_focus()

func submit():
 if busy(): return
 if helper != null: helper.submit()
 else: begin(entry.text)

func begin(value: String):
 if not active() or busy(): return
 var candidate = value.strip_edges()
 if not valid_key(candidate):
  hint.text = "Enter a valid invite key."
  if helper != null: helper.focus()
  return
 pending_key = candidate
 confirm.disabled = true
 if helper != null: helper.setBusy(true)
 hint.text = "Checking invite…"
 validation_id += 1
 send_validation(validation_id)

func send_validation(attempt: int):
 request = HTTPRequest.new()
 request.timeout = 10
 request.body_size_limit = 70000
 request.max_redirects = 0
 add_child(request)
 request.request_completed.connect(complete.bind(attempt))
 var error = request.request(preload("res://src/private_lobby.gd").ENDPOINT,["Authorization: Bearer "+pending_key,"Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify({"version":1,"action":"list"}))
 if error != OK: complete(HTTPRequest.RESULT_CANT_CONNECT,0,PackedStringArray(),PackedByteArray(),attempt)

func complete(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray, attempt: int):
 if attempt != validation_id or not active() or not busy(): return
 var candidate = pending_key
 pending_key = ""
 if request != null: request.queue_free(); request = null
 confirm.disabled = false
 if helper != null: helper.setBusy(false)
 var response = null
 if result == HTTPRequest.RESULT_SUCCESS:
  var json = JSON.new()
  if json.parse(body.get_string_from_utf8()) == OK: response = json.data
 var reason := ""
 if response is Dictionary and response.get("error") is String: reason = response.error
 var version = response.get("version") if response is Dictionary else null
 var valid_response: bool = (version is int or version is float) and version == 1 and response.get("rooms") is Array
 if result != HTTPRequest.RESULT_SUCCESS:
  hint.text = "Cannot reach the playtest service. Try again."
 elif status == 403 and reason == "origin_denied":
  hint.text = "This page is not allowed by the playtest service."
 elif status == 403 and reason == "invitation_expired":
  hint.text = "Invite expired. Enter a fresh invite key."
 elif status == 401:
  hint.text = "Invite key not accepted. Try again."
 elif status == 429:
  hint.text = "Too many attempts. Wait a moment and try again."
 elif status != 200 or not valid_response:
  hint.text = "Cannot check the invite right now. Try again."
 else:
  key = candidate
  generation += 1
  entry.clear()
  if helper != null: helper.close()
  panel.hide()
  game.header.show()
  game.settings_button.show()
  game.setup_menu.show()
  game.focus_play_menu()

func cancel_request():
 generation += 1
 validation_id += 1
 pending_key = ""
 if request != null:
  request.cancel_request()
  request.queue_free()
  request = null
 if helper != null: helper.close()

func place_field():
 if helper == null or not active(): return
 var rect = entry.get_global_rect()
 var viewport = get_viewport().get_visible_rect().size
 if rect.size.x>0 and rect.size.y>0:
  helper.place(rect.position.x,rect.position.y,rect.size.x,rect.size.y,viewport.x,viewport.y)
  last_rect = rect

func _process(_dt):
 if active() and helper != null and entry.get_global_rect() != last_rect: place_field()

func _exit_tree():
 cancel_request()
 key = ""
 if is_instance_valid(entry): entry.clear()
 if is_instance_valid(panel): panel.queue_free()
