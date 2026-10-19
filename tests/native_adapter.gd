extends SceneTree
var event_count := 0
var failed := false

func _initialize():
 var adapter = load("res://adapters/godot/portable_core.gd").new()
 if not adapter.valid:
  push_error("Native core extension failed")
  quit(1)
  return
 # A callback may drain again: the event must already have been consumed.
 adapter.core_event.connect(func(_type, _slot, _value, _tick):
  event_count += 1
  if event_count == 1: adapter.drain_events()
 )
 adapter.configure(1)
 failed = event_count != 1
 # Godot ints are 64-bit; neither operations nor inputs may wrap to int32.
 failed = failed or adapter.command(1,4294967296,0) != -2
 failed = failed or adapter.native.callv("command",[4294967298,0,0]) != -2
 failed = failed or adapter.command(10,0) != 0
 adapter.step(1,false,false)
 failed = failed or adapter.command(10,3,1) != 182833
 print("GODOT C ABI ADAPTER ","FAIL" if failed else "PASS"," ",adapter.actors())
 adapter.close()
 quit(1 if failed else 0)
