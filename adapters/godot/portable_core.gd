class_name PortableCoreAdapter
extends RefCounted

signal outgoing_message(bytes: PackedByteArray)
signal core_event(type: int, slot: int, value: int, fixed_tick: int)

var native: Object
var web: JavaScriptObject
var web_handle := 0
var valid := false

func _init():
 if OS.has_feature("web"):
  web = JavaScriptBridge.get_interface("EmberCoreWeb")
  if web != null: web_handle = int(web.create())
  valid = web_handle != 0
 else:
  if not ClassDB.class_exists("EmberCoreNative"):
   GDExtensionManager.load_extension("res://build/native/ember.gdextension")
  if ClassDB.class_exists("EmberCoreNative"): native = ClassDB.instantiate("EmberCoreNative")
  valid = native != null
 if valid: valid = command(14,0,0) == 0x00010000

func command(operation: int, a: int = 0, b: int = 0) -> int:
 if web != null: return int(web.command(web_handle,operation,a,b))
 if native != null: return int(native.command(operation,a,b))
 return -1

func configure(role: int):
 command(0,role,role)
 drain_events()

func peer_active(active: bool):
 command(3,2,int(active))
 drain_events()

func receive_message(sender_slot: int, bytes: PackedByteArray) -> int:
 if bytes.size() > 104: return -4
 if command(4,sender_slot,bytes.size()) != 0: return -4
 for index in bytes.size(): command(5,index,bytes[index])
 var result = command(6)
 drain_events()
 return result

func step(axis: float, jump: bool, attack: bool):
 command(1,roundi(clampf(axis,-1,1)*1000),int(jump) | (int(attack)<<1))
 command(2)
 while command(7) > 0:
  var bytes = PackedByteArray()
  bytes.resize(command(7))
  for index in bytes.size(): bytes[index] = command(8,index)
  command(9)
  outgoing_message.emit(bytes)
 drain_events()

func drain_events():
 while command(12,0) > 0:
  core_event.emit(command(12,0),command(12,1),command(12,2),command(12,3))
  command(13)

func actors() -> Dictionary:
 var result := {}
 for slot in [1,2]:
  if command(10,2,slot) == 0: continue
  result[slot] = {"x":command(10,3,slot)/1000.0,"y":command(10,4,slot)/1000.0,"vy":command(10,5,slot)/1000.0,"face":command(10,6,slot),"attack":command(10,7,slot)/60.0,"attack_id":command(10,8,slot),"animation":command(10,9,slot),"grounded":command(10,10,slot)!=0}
 return result

func close():
 if web != null and web_handle != 0: web.destroy(web_handle)
 web_handle = 0
 web = null
 native = null
 valid = false

func _notification(what):
 if what == NOTIFICATION_PREDELETE:
  if web != null and web_handle != 0: web.destroy(web_handle)
  web_handle = 0
  native = null
