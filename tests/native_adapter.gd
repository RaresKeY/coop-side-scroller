extends SceneTree
func _initialize():
 var adapter = load("res://adapters/godot/portable_core.gd").new()
 if not adapter.valid:
  push_error("Native core extension failed")
  quit(1)
  return
 adapter.configure(1)
 adapter.step(1,false,false)
 print("GODOT C ABI ADAPTER ",adapter.actors())
 if adapter.command(10,3,1) != 182833: quit(1)
 else: quit()
 adapter.close()
