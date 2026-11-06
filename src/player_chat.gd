extends Node
# Presentation/session metadata travels reliably beside opaque simulation bytes.
# The portable movement core never receives names, chat text or UI state.
const SpeechBubble = preload("res://src/speech_bubble.gd")
const MAX_NAME := 24
const MAX_TEXT := 200
const MAX_HISTORY := 100
const SEND_INTERVAL_MS := 500
signal outgoing(peer: int, packet: Dictionary)
var game
var panel: PanelContainer
var log_view: RichTextLabel
var entry: LineEdit
var footer: Label
var composing := false
var names := ["", ""]
var history: Array = []
var tags := {}
var bubbles := {}
var session := ""
var guest_named := false
var next_id := 0
var seen_id := 0
var client_id := 0
var seen_client_id := 0
var last_send_ms := -100000
var last_guest_ms := -100000
var guest_budget := 8.0
var observer
var browser_composer
var composer_callback
var composer_rect := Rect2()
var compose_generation := 0

static func clean_text(value, limit: int) -> String:
 if not value is String: return ""
 var text: String = value.strip_edges()
 if text.is_empty() or text.length() > limit or text.to_utf8_buffer().size() > limit*4: return ""
 for i in text.length():
  var code = text.unicode_at(i)
  if code < 32 or (code >= 127 and code < 160) or (code >= 0x202a and code <= 0x202e) or (code >= 0x2066 and code <= 0x2069): return ""
 return text

static func shape(packet: Dictionary, fields: Array) -> bool:
 if packet.size() != fields.size(): return false
 for key in fields:
  if not packet.has(key): return false
 return true

func now_ms() -> int: return Time.get_ticks_msec()
func local_slot() -> int: return 2 if game.mode == "client" else 1
func display_name(slot: int) -> String:
 if slot == local_slot(): return game.player_name
 return names[slot-1] if not names[slot-1].is_empty() else "Partner"

func plate(alpha := 0.65) -> StyleBoxFlat:
 var style = StyleBoxFlat.new()
 style.bg_color = Color(0.055,0.065,0.08,alpha)
 style.border_color = Color(0.65,0.65,0.65,0.16)
 style.set_border_width_all(1)
 style.content_margin_left = 8
 style.content_margin_right = 8
 style.content_margin_top = 6
 style.content_margin_bottom = 6
 return style

func setup(owner_game, canvas):
 game = owner_game
 var root = Control.new()
 root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 root.mouse_filter = Control.MOUSE_FILTER_IGNORE
 canvas.add_child(root)
 panel = PanelContainer.new()
 panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
 panel.offset_left = -336
 panel.offset_right = -16
 panel.offset_top = 16
 panel.add_theme_stylebox_override("panel",plate())
 root.add_child(panel)
 var column = VBoxContainer.new()
 column.add_theme_constant_override("separation",5)
 panel.add_child(column)
 var heading = Label.new()
 heading.text = "Chat"
 heading.add_theme_font_size_override("font_size",14)
 heading.add_theme_color_override("font_color",Color("d7c49c"))
 column.add_child(heading)
 log_view = RichTextLabel.new()
 log_view.name = "ChatHistory"
 log_view.bbcode_enabled = false
 log_view.custom_minimum_size = Vector2(0,112)
 log_view.selection_enabled = true
 log_view.scroll_active = true
 log_view.add_theme_font_size_override("normal_font_size",14)
 log_view.add_theme_color_override("default_color",Color("e6e6e6"))
 column.add_child(log_view)
 entry = LineEdit.new()
 entry.name = "ChatInput"
 entry.placeholder_text = "Message…"
 entry.max_length = MAX_TEXT
 entry.add_theme_font_size_override("font_size",14)
 entry.custom_minimum_size.y = 28
 entry.hide()
 column.add_child(entry)
 footer = Label.new()
 footer.text = "Enter to chat"
 footer.add_theme_font_size_override("font_size",12)
 footer.add_theme_color_override("font_color",Color("b8b8b8"))
 column.add_child(footer)
 if OS.has_feature("web"):
  observer = JavaScriptBridge.get_interface("EmberSocialObserver")
  browser_composer = JavaScriptBridge.get_interface("EmberChatComposer")
  if browser_composer != null: entry.editable = false; entry.focus_mode = Control.FOCUS_NONE
 panel.hide()
 publish_observation()

func available() -> bool:
 return not game.setup_menu.visible and not game.signal_panel.visible and not (game.lobby != null and game.lobby.panel.visible)

func _input(event):
 if not event is InputEventKey or not event.pressed or event.echo: return
 if composing and event.keycode == KEY_ESCAPE:
  finish_composing()
  get_viewport().set_input_as_handled()
 elif event.keycode in [KEY_ENTER,KEY_KP_ENTER] and available():
  if composing:
   if browser_composer != null:
    browser_composer.focus()
   elif submit(entry.text):
    entry.clear()
    finish_composing()
  else:
   composing = true
   entry.show()
   if browser_composer == null: entry.grab_focus()
   footer.text = "Enter to send · Esc to cancel"
   if browser_composer != null: call_deferred("open_browser_composer")
   publish_observation()
  get_viewport().set_input_as_handled()

func open_browser_composer():
 if not composing or browser_composer == null: return
 var generation = compose_generation
 composer_callback = JavaScriptBridge.create_callback(func(args):
  if not composing or generation != compose_generation or args.size()<2: return
  if str(args[0]) == "cancel": finish_composing()
  elif str(args[0]) == "send" and submit(str(args[1])): finish_composing()
 )
 browser_composer.open(composer_callback,MAX_TEXT)
 place_browser_composer()

func place_browser_composer():
 if browser_composer == null or not composing: return
 var rect = entry.get_global_rect()
 if rect.size.x<=0 or rect.size.y<=0: return
 var viewport = get_viewport().get_visible_rect().size
 browser_composer.place(rect.position.x,rect.position.y,rect.size.x,rect.size.y,viewport.x,viewport.y)
 composer_rect = rect

func finish_composing():
 compose_generation += 1
 if browser_composer != null: browser_composer.close()
 composing = false
 entry.clear()
 entry.release_focus()
 entry.hide()
 footer.text = "Enter to chat"
 publish_observation()

func clear_session():
 if entry != null:
  entry.clear()
  finish_composing()
 names = ["", ""]
 history.clear()
 session = ""
 guest_named = false
 next_id = 0
 seen_id = 0
 client_id = 0
 seen_client_id = 0
 last_send_ms = -100000
 last_guest_ms = -100000
 guest_budget = 8.0
 for tag in tags.values(): tag.queue_free()
 tags.clear()
 for bubble in bubbles.values(): bubble.node.queue_free()
 bubbles.clear()
 if log_view != null: log_view.clear()
 publish_observation()

func connected():
 if game.mode != "host": return
 session = str(game.local_signal.get("session",""))
 if session.is_empty(): session = Crypto.new().generate_random_bytes(16).hex_encode()
 names[0] = game.player_name
 names[1] = "Partner"
 guest_named = false
 seen_client_id = 0
 last_guest_ms = -100000
 guest_budget = 8.0
 send_state()
 publish_observation()

func peer_left():
 names[1] = ""
 guest_named = false
 seen_client_id = 0
 if tags.has(2): tags[2].queue_free(); tags.erase(2)
 if bubbles.has(2): bubbles[2].node.queue_free(); bubbles.erase(2)
 publish_observation()

func send_state():
 for peer in game.social_peers():
  outgoing.emit(peer,{"v":1,"kind":"state","session":session,"names":names.duplicate()})

func receive(sender: int, packet: Dictionary):
 if sender not in game.social_peers() or packet.get("v") != 1: return
 var kind = packet.get("kind","")
 if game.mode == "client":
  if sender != 1: return
  if kind == "state":
   if not shape(packet,["v","kind","session","names"]): return
   if not packet.session is String or packet.session.length()!=32 or not packet.session.is_valid_hex_number(false): return
   var expected = str(game.local_signal.get("session",""))
   if not expected.is_empty() and packet.session != expected: return
   if not session.is_empty() and session != packet.session: return
   if not packet.names is Array or packet.names.size()!=2: return
   var first = clean_text(packet.names[0],MAX_NAME)
   var second = clean_text(packet.names[1],MAX_NAME)
   if first.is_empty() or second.is_empty(): return
   var first_state = session.is_empty()
   session = packet.session
   names = [first,second]
   if first_state: outgoing.emit(1,{"v":1,"kind":"name","session":session,"name":game.player_name})
   publish_observation()
  elif kind == "message":
   if not shape(packet,["v","kind","session","id","slot","name","text"]): return
   if session.is_empty() or packet.session != session: return
   if not packet.id is int or packet.id<=seen_id or packet.id>0x7fffffff: return
   if not packet.slot is int or packet.slot not in [1,2]: return
   var author = clean_text(packet.name,MAX_NAME)
   var text = clean_text(packet.text,MAX_TEXT)
   if author.is_empty() or author != names[packet.slot-1] or text.is_empty(): return
   seen_id = packet.id
   append_message(packet.id,packet.slot,author,text)
  return
 if game.mode != "host" or session.is_empty() or packet.get("session") != session: return
 if kind == "name":
  if not shape(packet,["v","kind","session","name"]): return
  var chosen = clean_text(packet.name,MAX_NAME)
  if chosen.is_empty() or (guest_named and chosen != names[1]): return
  names[1] = chosen
  guest_named = true
  send_state()
  publish_observation()
 elif kind == "submit":
  if not shape(packet,["v","kind","session","id","text"]) or not guest_named: return
  if not packet.id is int or packet.id<=seen_client_id or packet.id>0x7fffffff: return
  var text = clean_text(packet.text,MAX_TEXT)
  if text.is_empty(): return
  var now = now_ms()
  # Permit legitimate reliable messages bunched by network delay, while
  # bounding sustained peer spam independently of the local composer throttle.
  guest_budget = minf(8.0,guest_budget+maxi(0,now-last_guest_ms)/float(SEND_INTERVAL_MS))
  last_guest_ms = now
  if guest_budget<1.0: return
  guest_budget -= 1.0
  seen_client_id = packet.id
  broadcast(2,names[1],text)

func submit(value: String) -> bool:
 var text = clean_text(value,MAX_TEXT)
 if text.is_empty():
  footer.text = "Use 1–%d characters" % MAX_TEXT
  return false
 if now_ms()-last_send_ms<SEND_INTERVAL_MS:
  footer.text = "Wait a moment before sending"
  return false
 if game.mode == "client":
  if session.is_empty() or game.social_peers().is_empty():
   footer.text = "Waiting for your partner…"
   return false
  client_id += 1
  outgoing.emit(1,{"v":1,"kind":"submit","session":session,"id":client_id,"text":text})
 elif game.mode == "host":
  broadcast(1,game.player_name,text)
 else:
  next_id += 1
  append_message(next_id,1,game.player_name,text)
 last_send_ms = now_ms()
 return true

func broadcast(slot: int, author: String, text: String):
 next_id += 1
 append_message(next_id,slot,author,text)
 var packet = {"v":1,"kind":"message","session":session,"id":next_id,"slot":slot,"name":author,"text":text}
 for peer in game.social_peers(): outgoing.emit(peer,packet)

func append_message(id: int, slot: int, author: String, text: String):
 history.append({"id":id,"slot":slot,"name":author,"text":text})
 while history.size()>MAX_HISTORY: history.pop_front()
 var scroll = log_view.get_v_scroll_bar()
 var follow = scroll.value >= scroll.max_value-scroll.page-2
 var saved = scroll.value
 # Literal text only: player strings never pass through a markup parser.
 log_view.clear()
 for message in history:
  log_view.push_color(Color("d7c49c") if message.slot==local_slot() else Color("a9d8df"))
  log_view.add_text(message.name+": ")
  log_view.pop()
  log_view.add_text(message.text+"\n")
 if follow: log_view.call_deferred("scroll_to_line",maxi(0,log_view.get_line_count()-1))
 else: scroll.set_deferred("value",saved)
 if bubbles.has(slot): bubbles[slot].node.queue_free()
 var bubble = SpeechBubble.new()
 bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
 bubble.z_index = 20
 bubble.configure(plate(0.68))
 var label = Label.new()
 label.text = text
 label.mouse_filter = Control.MOUSE_FILTER_IGNORE
 label.add_theme_font_size_override("font_size",14)
 label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 var font = label.get_theme_font("font")
 label.custom_minimum_size.x = clampf(font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x,56,216)
 bubble.add_child(label)
 game.add_child(bubble)
 bubbles[slot] = {"node":bubble,"until":now_ms()+clampi(4000+text.length()*30,4000,10000)}
 publish_observation()

func update_positions():
 if panel == null: return
 if composing and browser_composer != null and entry.get_global_rect()!=composer_rect: place_browser_composer()
 var visible_now = available()
 if panel.visible != visible_now:
  panel.visible = visible_now
  if composing and not visible_now: finish_composing()
  publish_observation()
 for slot in tags.keys():
  if not game.sprites.has(slot) or slot==local_slot(): tags[slot].queue_free(); tags.erase(slot)
 for slot in game.sprites:
  var sprite = game.sprites[slot]
  var feet = sprite.position + (Vector2(0,17) if sprite is Sprite2D else Vector2.ZERO)
  if slot != local_slot():
   if not tags.has(slot):
    var label = Label.new()
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size",13)
    label.add_theme_color_override("font_shadow_color",Color(0,0,0,0.9))
    label.add_theme_constant_override("shadow_offset_x",1)
    label.add_theme_constant_override("shadow_offset_y",1)
    label.z_index = 15
    game.add_child(label)
    tags[slot] = label
   var label = tags[slot]
   label.text = display_name(slot)
   label.reset_size()
   label.position = Vector2(clampf(feet.x-label.size.x/2,4,956-label.size.x),feet.y-92)
  if bubbles.has(slot):
   var bubble = bubbles[slot].node
   bubble.reset_size()
   bubble.position = Vector2(clampf(feet.x-bubble.size.x/2,4,956-bubble.size.x),clampf(feet.y-102-bubble.size.y,4,maxf(4,536-bubble.size.y-SpeechBubble.TAIL_LENGTH)))
 for slot in bubbles.keys():
  if now_ms()>=bubbles[slot].until or not game.sprites.has(slot):
   bubbles[slot].node.queue_free()
   bubbles.erase(slot)

 # Nearby players can speak at once. Prefer the smallest move above/alongside
 # the other plate, while keeping both messages inside the arena.
 var occupied: Array[Rect2] = []
 var slots = bubbles.keys()
 slots.sort()
 for slot in slots:
  var bubble = bubbles[slot].node
  var rect = bubble.footprint()
  for other in occupied:
   if not rect.grow(4).intersects(other): continue
   var options = [Vector2(rect.position.x,other.position.y-rect.size.y-8),Vector2(other.end.x+8,rect.position.y),Vector2(other.position.x-rect.size.x-8,rect.position.y)]
   var best = rect.position
   var distance = INF
   for option in options:
    if option.x<4 or option.y<4 or option.x+rect.size.x>956: continue
    var candidate = Rect2(option,rect.size)
    if candidate.grow(4).intersects(other): continue
    var delta = rect.position.distance_squared_to(option)
    if delta<distance: best=option;distance=delta
   bubble.position = best
   rect.position = best
  occupied.append(rect)
  var sprite = game.sprites[slot]
  var feet = sprite.position + (Vector2(0,17) if sprite is Sprite2D else Vector2.ZERO)
  bubble.point_to(feet+Vector2(0,-76)-bubble.position)

func _process(_dt): update_positions()

func publish_observation():
 if observer != null:
  observer.publish(JSON.stringify({"localSlot":local_slot(),"names":[display_name(1),display_name(2)],"messages":history,"composing":composing,"available":available()}))
