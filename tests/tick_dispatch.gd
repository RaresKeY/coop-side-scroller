extends SceneTree

class Probe extends "res://src/main.gd":
 var dispatched: Array = []
 func flush_packets():
  var now = Time.get_ticks_msec()
  while not outbox.is_empty() and outbox[0].due <= now:
   dispatched.append(outbox.pop_front())

func check(ok: bool, message: String):
 if not ok:
  push_error(message)
  quit(1)
  assert(ok,message)

func _initialize():
 run.call_deferred()

func run():
 var game = Probe.new()
 root.add_child(game)
 game.set_process(false)
 game.set_physics_process(false)
 game.setup_menu.hide()
 game.core.configure(2)
 game.mode = "client"
 game._physics_process(1.0/60.0)
 check(game.dispatched.size() == 1,"current tick input waited for the next physics callback")
 check(game.dispatched[0].data[0].decode_u32(4) == 1,"expected a real core input packet")
 game.dispatched.clear()
 game.delay_ms = 100
 game._physics_process(1.0/60.0)
 check(game.dispatched.is_empty() and game.outbox.size() == 1,"configured artificial delay was bypassed")
 var due: int = game.outbox[0].due
 var deadline = Time.get_ticks_msec()+2000
 while Time.get_ticks_msec() < due and Time.get_ticks_msec() < deadline:
  await process_frame
 game._physics_process(1.0/60.0)
 check(game.dispatched.size() == 1 and game.outbox.size() == 1,"delayed old input dispatch or current tick scheduling broke")
 game.queue_free()
 await process_frame
 print("Tick dispatch PASS: immediate output and preserved artificial delay")
 quit(0)
