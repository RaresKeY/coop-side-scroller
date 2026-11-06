extends SceneTree
const Chat = preload("res://src/player_chat.gd")
class Fixture extends Node2D:
 var mode := "host"
 var player_name := "Terra"
 var setup_menu := Control.new()
 var signal_panel := Control.new()
 var lobby = null
 var sprites := {}
 var local_signal := {}
 var peers := PackedInt32Array([37])
 func social_peers() -> PackedInt32Array: return peers
class ClockedChat extends "res://src/player_chat.gd":
 var clock := 1000
 func now_ms() -> int: return clock
var failed := false
func check(value: bool, message: String):
 if not value: failed = true; push_error(message)
func make_game(role: String, chosen: String):
 var game = Fixture.new()
 game.mode = role
 game.player_name = chosen
 game.peers = PackedInt32Array([1] if role=="client" else [37])
 root.add_child(game)
 game.add_child(game.setup_menu);game.setup_menu.hide()
 game.add_child(game.signal_panel);game.signal_panel.hide()
 for slot in [1,2]:
  var body = Node2D.new();body.position = Vector2(180 if slot==1 else 260,448)
  game.add_child(body);game.sprites[slot] = body
 return game
func check_tail(chat, fixture, slot: int):
 var bubble = chat.bubbles[slot].node
 var points = bubble.tail_points()
 check(points.size()==3,"Missing bottom speech triangle")
 if points.size()!=3: return
 var base = (points[0]+points[2])/2
 var aim = fixture.sprites[slot].position+Vector2(0,-76)-bubble.position-base
 var ray = points[1]-base
 check(is_equal_approx(base.y,bubble.size.y),"Triangle detached from bubble bottom")
 check(absf(base.x-(fixture.sprites[slot].position.x-bubble.position.x))>1,"Tail lost side offset")
 check(ray.dot(aim)>0 and absf(ray.cross(aim))<0.02,"Tail does not point toward its rendered speaker")
 check(ray.length()<=24.01 and points[1].y>base.y,"Tail length/direction escaped bounds")
 for point in points: check(point.x>=0 and point.x<=bubble.size.x,"Tail escaped horizontal bounds")
 check(bubble.footprint().position.y>=4 and bubble.footprint().end.y<=536,"Speech escaped arena")
func _initialize(): call_deferred("run")
func run():
 for bad in ["", "a".repeat(25),"bad\nname","bad"+String.chr(0x202e),42]:
  check(Chat.clean_text(bad,24).is_empty(),"Invalid name accepted")
 check(Chat.clean_text("  Terra  ",24)=="Terra","Name trimming")
 check(Chat.clean_text("騎士 ✨",24)=="騎士 ✨","Unicode name lost")
 var host = make_game("host","Terra")
 var guest = make_game("client","Rae")
 var hc = ClockedChat.new();host.add_child(hc)
 var gc = ClockedChat.new();guest.add_child(gc)
 var a = CanvasLayer.new();host.add_child(a);hc.setup(host,a)
 var b = CanvasLayer.new();guest.add_child(b);gc.setup(guest,b)
 hc.outgoing.connect(func(_peer,packet): gc.receive(1,packet.duplicate(true)))
 gc.outgoing.connect(func(_peer,packet): hc.receive(37,packet.duplicate(true)))
 hc.connected()
 check(hc.names==["Terra","Rae"] and gc.names==hc.names,"Names did not replicate from authenticated slots")
 hc.update_positions();gc.update_positions()
 check(hc.tags.has(2) and not hc.tags.has(1) and hc.tags[2].text=="Rae","Host perspective name tag ownership")
 check(gc.tags.has(1) and not gc.tags.has(2) and gc.tags[1].text=="Terra","Guest perspective name tag ownership")
 check(gc.submit("Hello, Terra!"),"Guest submit failed")
 check(hc.history.size()==1 and gc.history.size()==1,"Sender echo was lost or duplicated")
 check(hc.history[0].slot==2 and hc.history[0].name=="Rae","Guest forged or lost identity")
 check(hc.bubbles.has(2) and gc.bubbles.has(2),"Speech bubble missing from sender or partner")
 var replay = {"v":1,"kind":"message","session":hc.session,"id":1,"slot":2,"name":"Rae","text":"Hello, Terra!"}
 gc.receive(1,replay)
 gc.receive(37,{"v":1,"kind":"message","session":hc.session,"id":9,"slot":1,"name":"Terra","text":"spoof"})
 hc.receive(99,{"v":1,"kind":"submit","session":hc.session,"id":5,"text":"spoof"})
 hc.receive(37,{"v":1,"kind":"submit","session":"0".repeat(32),"id":5,"text":"stale"})
 hc.receive(37,{"v":1,"kind":"submit","session":hc.session,"id":5,"slot":1,"text":"spoof"})
 check(hc.history.size()==1 and gc.history.size()==1,"Replay, stale session or spoof accepted")
 check(not gc.submit("Too fast"),"Sender throttle missing")
 hc.clock+=1000;gc.clock+=1000
 check(hc.submit("[b]I am moving right.[/b]"),"Host action description failed")
 check(hc.log_view.get_parsed_text().contains("[b]I am moving right.[/b]"),"Player text was parsed as markup")
 check(gc.bubbles.has(1) and hc.bubbles.has(1),"Host speech missing from both views")
 await process_frame;await process_frame
 hc.update_positions();gc.update_positions()
 check(not hc.bubbles[1].node.get_rect().intersects(hc.bubbles[2].node.get_rect()),"Nearby speech bubbles overlap")
 check(not hc.bubbles[1].node.footprint().intersects(hc.bubbles[2].node.footprint()),"Tail overlaps another speech plate")
 for fixture in [host,guest]:
  var chat = hc if fixture==host else gc
  for slot in [1,2]: check_tail(chat,fixture,slot)
  # Exercise actual placement at both arena edges and while a speaker jumps.
  for place in [Vector2(4,308),Vector2(956,448)]:
   fixture.sprites[1].position=place
   fixture.sprites[2].position=place+Vector2(-24 if place.x>480 else 24,0)
   chat.update_positions()
   for slot in [1,2]: check_tail(chat,fixture,slot)
   check(not chat.bubbles[1].node.footprint().intersects(chat.bubbles[2].node.footprint()),"Stacked speech/tails overlap at an arena edge")
 var input = InputEventKey.new();input.pressed=true;input.keycode=KEY_ENTER
 gc._input(input)
 check(gc.composing and gc.entry.visible,"Enter did not focus chat")
 gc.clock+=1000;hc.clock+=1000;gc.entry.text="Which way next?"
 gc._input(input)
 check(not gc.composing and gc.entry.text.is_empty() and hc.history.back().text=="Which way next?","Enter did not send/close composer")
 gc._input(input);gc.entry.text="draft"
 input.keycode=KEY_ESCAPE;gc._input(input)
 check(not gc.composing and hc.history.size()==3,"Escape sent a draft")
 for i in 110:
  hc.clock+=1000;gc.clock+=1000;hc.submit("History line %03d" % i)
 await process_frame;await process_frame
 check(hc.history.size()==100 and gc.history.size()==100,"Chat history is unbounded")
 check(hc.log_view.get_v_scroll_bar().max_value>hc.log_view.get_v_scroll_bar().page,"Chat history does not scroll")
 hc.log_view.get_v_scroll_bar().value=0
 hc.clock+=1000;hc.submit("Keep reading older messages")
 await process_frame;await process_frame
 check(hc.log_view.get_v_scroll_bar().value<2,"Incoming chat stole scroll position")
 var expired_bubble = weakref(hc.bubbles[1].node)
 hc.clock+=11000;gc.clock+=11000;hc.update_positions();gc.update_positions()
 check(hc.bubbles.is_empty() and gc.bubbles.is_empty(),"Speech bubbles did not expire")
 await process_frame
 check(expired_bubble.get_ref()==null,"Expired speech retained its drawn tail")
 gc.clear_session();hc.clear_session()
 check(gc.history.is_empty() and gc.names==["",""] and gc.session.is_empty() and gc.tags.is_empty(),"Session reset leaked identity/chat")
 host.free();guest.free()
 print("PLAYER CHAT CONTRACTS ","FAIL" if failed else "PASS")
 quit(1 if failed else 0)
