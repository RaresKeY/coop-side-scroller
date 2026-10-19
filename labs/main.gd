extends Control

const LabKeys = preload("res://src/lab_keys.gd")
var bus := PacketPeerUDP.new()
var workers: Array = []
var keys: Dictionary = {}
var keys_at := 0
var delay: OptionButton
var address: LineEdit
var port: SpinBox
var message: Label
var telemetry: Label
var menu: VBoxContainer
var active: VBoxContainer
var starting := false
var boot_time := 0
var stop_at := 0
var stats := {}
var capture := false
var auto_test := false
var had_pair := false
var auto_started := 0
var driving_at := 0
var test_captured := false

func _ready():
 get_tree().auto_accept_quit = false
 get_window().content_scale_size = Vector2i.ZERO
 get_window().size = Vector2i(780,250)
 get_window().position = Vector2i(20,40)
 DisplayServer.window_set_title("Ember Bridge / Labs")
 var error = bus.bind(0,"127.0.0.1")
 var scroll = ScrollContainer.new()
 scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 scroll.offset_left = 12
 scroll.offset_top = 12
 scroll.offset_right = -12
 scroll.offset_bottom = -12
 add_child(scroll)
 var box = VBoxContainer.new()
 box.add_theme_constant_override("separation",4)
 scroll.add_child(box)
 var title = Label.new()
 title.text = "Labs"
 box.add_child(title)
 menu = VBoxContainer.new()
 box.add_child(menu)
 var row = HBoxContainer.new()
 row.add_theme_constant_override("separation",6)
 menu.add_child(row)
 var caption = Label.new()
 caption.text = "Network"
 caption.custom_minimum_size.x = 64
 row.add_child(caption)
 var first = button(row,"Local pair",func(): launch("pair"),"Two independent Godot processes, real ENet loopback, both keyboard schemes.")
 button(row,"Host only",func(): launch("host"),"Host on this machine; partner uses Join only on another machine.")
 button(row,"Join only",func(): launch("client"),"Join the address below. Direct UDP reachability required; no relay.")
 var target = HBoxContainer.new()
 menu.add_child(target)
 var label = Label.new()
 label.text = "Address"
 label.custom_minimum_size.x = 64
 target.add_child(label)
 address = LineEdit.new()
 address.text = "127.0.0.1"
 address.custom_minimum_size.x = 200
 target.add_child(address)
 port = SpinBox.new()
 port.min_value = 1024
 port.max_value = 65535
 port.value = 27840
 target.add_child(port)
 active = VBoxContainer.new()
 active.visible = false
 box.add_child(active)
 var controls = HBoxContainer.new()
 active.add_child(controls)
 button(controls,"Back to labs",stop_workers,"Close only this lab's owned workers and return to chooser.")
 var d = Label.new()
 d.text = "Delay each way"
 controls.add_child(d)
 delay = OptionButton.new()
 for ms in [0,50,100,200]: delay.add_item("%d ms"%ms,ms)
 controls.add_child(delay)
 delay.item_selected.connect(func(_index): delay.release_focus())
 var help = Label.new()
 help.text = "P1: A/D, W jump, F attack   |   P2: arrows, Up jump, L attack\nEither game window or this panel can have focus. World state crosses ENet only."
 active.add_child(help)
 telemetry = Label.new()
 telemetry.text = "Waiting for worker telemetry…"
 active.add_child(telemetry)
 message = Label.new()
 message.text = "Choose a lab. First connection/relay services are deferred."
 message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 message.custom_minimum_size.x = 660
 box.add_child(message)
 if error != OK: message.text = "Lab input bus failed: " + error_string(error)
 first.grab_focus()
 boot_time = Time.get_ticks_msec()
 for arg in OS.get_cmdline_user_args():
  if arg == "--capture": capture = true
  if arg == "--lab-test": auto_test = true
  if arg == "--lab-pair": call_deferred("launch","pair")
 if auto_test:
  delay.select(1)
  call_deferred("launch","pair")

func button(row: HBoxContainer, text: String, action: Callable, tooltip: String) -> Button:
 var b = Button.new()
 b.text = text
 b.tooltip_text = tooltip
 b.custom_minimum_size = Vector2(104,32)
 b.pressed.connect(action)
 row.add_child(b)
 return b

func available_port() -> int:
 var socket = PacketPeerUDP.new()
 if socket.bind(0,"127.0.0.1") != OK: return 0
 var result = socket.get_local_port()
 socket.close()
 return result

func launch(route: String):
 if not workers.is_empty() or starting: return
 starting = true
 stats.clear()
 var roles = ["host","client"] if route == "pair" else [route]
 # Local pair gets its own ephemeral game port; remote routes use the configured port.
 var game_port = available_port() if route == "pair" else int(port.value)
 for role in roles:
  var control_port = available_port()
  var index = 0 if role == "host" else 1
  var args = ["--path",ProjectSettings.globalize_path("res://"),"--audio-driver","Dummy","--resolution","800x450","--position",str(20+index*820)+",340","res://main.tscn","--","--lab-role="+role,"--control-port="+str(control_port),"--bus-port="+str(bus.get_local_port()),"--port="+str(game_port),"--address="+("127.0.0.1" if route=="pair" else address.text.strip_edges())]
  var pid = OS.create_process(OS.get_executable_path(),args)
  if pid <= 0:
   message.text = "Worker launch failed: " + role
   starting = false
   stop_workers()
   return
  workers.append({"role":role,"pid":pid,"control":control_port})
 menu.hide()
 active.show()
 starting = false
 auto_started = Time.get_ticks_msec()
 message.text = "Live separate processes / UDP %d. Close either game or Back to labs to stop the pair." % game_port
 get_window().grab_focus()

func stop_workers():
 for worker in workers:
  bus.set_dest_address("127.0.0.1",worker.control)
  bus.put_packet(JSON.stringify({"kind":"quit"}).to_utf8_buffer())
 stop_at = Time.get_ticks_msec()+700
 active.hide()
 menu.show()
 keys.clear()
 message.text = "Stopping owned workers…"

func finish_stop():
 for worker in workers:
  if OS.is_process_running(worker.pid): OS.kill(worker.pid)
 workers.clear()
 stats.clear()
 stop_at = 0
 message.text = "Stopped. Choose another lab."

func _physics_process(_dt):
 var now = Time.get_ticks_msec()
 while bus.get_available_packet_count() > 0:
  var data = JSON.parse_string(bus.get_packet().get_string_from_utf8())
  if not data is Dictionary: continue
  if data.get("kind") == "keys" and data.get("keys") is Dictionary:
   keys = data["keys"]
   keys_at = now
  if data.get("kind") == "stats": stats[data.get("role","")] = data
 if get_window().has_focus():
  keys = LabKeys.read_keys()
  keys_at = now
 if now-keys_at>200: keys = {}
 if stop_at > 0:
  if now >= stop_at: finish_stop()
  return
 if auto_test:
  if driving_at == 0 and stats.has("host") and stats.has("client") and stats.host.players == 2 and stats.client.players == 2: driving_at = now
  var t = now-driving_at
  keys = {} if driving_at == 0 else {"d":t<900,"a":t>=900 and t<1500,"w":t>500 and t<650,"right":t<2400,"l":true}
 for worker in workers:
  if not OS.is_process_running(worker.pid):
   stop_workers()
   return
  var input = LabKeys.split(keys,1 if worker.role=="host" else 2)
  bus.set_dest_address("127.0.0.1",worker.control)
  bus.put_packet(JSON.stringify({"kind":"input","axis":input[0],"jump":input[1],"attack":input[2],"delay":delay.get_selected_id()}).to_utf8_buffer())
 if now%250<18 and not workers.is_empty():
  var lines: Array[String] = []
  for role in ["host","client"]:
   if not stats.has(role): continue
   var s = stats[role]
   lines.append("%s / PID %d / %s / actors %d / RTT %d ms / TX %d RX %d / snap age %d ms" % [role.to_upper(),s.pid,s.mode,s.players,s.rtt,s.tx,s.rx,s.age])
   if s.players == 2: had_pair = true
  telemetry.text = "\n".join(lines)
 if capture and now-boot_time > 1200 and workers.is_empty():
  get_viewport().get_texture().get_image().save_png("res://build/labs.png")
  get_tree().quit()
 if auto_test and driving_at > 0 and now-driving_at > 6500 and not test_captured:
  test_captured = true
  for worker in workers:
   bus.set_dest_address("127.0.0.1",worker.control)
   bus.put_packet(JSON.stringify({"kind":"capture"}).to_utf8_buffer())
  get_viewport().get_texture().get_image().save_png("res://build/lab-controller.png")
 if auto_test and ((driving_at > 0 and now-driving_at > 7000) or (auto_started > 0 and now-auto_started > 20000)):
  var passed = had_pair and stats.has("client") and stats.client.rtt>=0 and stats.client.rx>0 and stats.client.hp<12 and stats.client.x>600 and stats.has("host") and abs(stats.host.x-180)>10
  print("LAB TEST ","PASS" if passed else "FAIL", " ",stats)
  for worker in workers:
   if OS.is_process_running(worker.pid): OS.kill(worker.pid)
  workers.clear()
  get_tree().quit(0 if passed else 1)

func _notification(what):
 if what == NOTIFICATION_WM_CLOSE_REQUEST:
  for worker in workers:
   if OS.is_process_running(worker.pid): OS.kill(worker.pid)
  workers.clear()
  get_tree().quit()

func _exit_tree():
 for worker in workers:
  if OS.is_process_running(worker.pid): OS.kill(worker.pid)
