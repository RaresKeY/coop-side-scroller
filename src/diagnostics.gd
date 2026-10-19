extends Node
# Bounded, deliberately selected connection metadata only.
const BUILD := "diagnostics-v2"
const ENDPOINT := "https://ember-coop-credentials.ember-bridge-playtests.workers.dev/v1/diagnostics"
var game
var copy_button: Button
var id := ""
var events: Array = []
var started := 0
var rtc_state := -1
var visible_state := true
var next_flush := 0
var next_ice_sample := 0
var next_ice_drain := 0
var sent := 0
var sequence := 0
var busy := false
var batches := 0
var sample_callback
var copy_callback

func begin():
 if OS.has_feature("web"):
  var helper = JavaScriptBridge.get_interface("EmberConnectionDiagnostics")
  if helper != null: helper.reset()
 id = Crypto.new().generate_random_bytes(8).hex_encode()
 if copy_button != null: copy_button.text = "Copy diagnostics · " + id
 events.clear()
 sent = 0
 sequence = 0
 batches = 0
 started = Time.get_ticks_msec()
 rtc_state = -1
 next_flush = started + 15000
 next_ice_sample = 0
 next_ice_drain = 0
 record("begin")

func record(kind: String, values := {}):
 if id.is_empty(): return
 sequence += 1
 var item = {"seq":sequence,"event":kind,"ms":mini(Time.get_ticks_msec()-started,86400000),"role":game.mode}
 item.merge(values)
 events.append(item)
 if events.size()>64:
  events.pop_front()

func report() -> String:
 return JSON.stringify({"version":1,"build":BUILD,"attempt":id,"events":events})

func flush():
 if batches >= 240 or busy or id.is_empty() or sent >= sequence or game.relay_access.text.strip_edges().is_empty(): return
 busy = true
 batches += 1
 var attempt = id
 var count = sequence
 var request = HTTPRequest.new()
 request.timeout = 8
 request.body_size_limit = 1024
 request.max_redirects = 0
 add_child(request)
 var payload = {"version":1,"build":BUILD,"attempt":id,"events":events.filter(func(event): return event.seq > sent)}
 var error = request.request(ENDPOINT,["Authorization: Bearer "+game.relay_access.text.strip_edges(),"Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify(payload))
 if error == OK:
  var response = await request.request_completed
  if attempt == id and response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200: sent = count
 request.queue_free()
 busy = false

func copy_report():
 capture_ice()
 if id.is_empty(): return
 if OS.has_feature("web"):
  var helper = JavaScriptBridge.get_interface("EmberClipboard")
  if helper != null:
   copy_callback = JavaScriptBridge.create_callback(func(_args): pass)
   helper.copy(report(),copy_callback)
 else: DisplayServer.clipboard_set(report())

func capture_ice():
 if not OS.has_feature("web") or id.is_empty(): return
 var helper = JavaScriptBridge.get_interface("EmberConnectionDiagnostics")
 if helper == null: return
 var pending = JSON.parse_string(str(helper.drain()))
 if not pending is Array: return
 for value in pending:
  if value is Dictionary and value.get("event") in ["ice_state","ice_error","ice_candidates","ice_stats","ice_stats_unavailable"]:
   var kind = str(value.event)
   value.erase("event")
   record(kind,value)

func sample_transport():
 if not OS.has_feature("web"): return
 var helper = JavaScriptBridge.get_interface("EmberConnectionDiagnostics")
 if helper == null: return
 var attempt = id
 sample_callback = JavaScriptBridge.create_callback(func(args):
  if id != attempt or args.size() == 0: return
  var result = JSON.parse_string(str(args[0]))
  if result is Dictionary:
   record("transport",result)
   flush()
 )
 helper.sample(sample_callback)

func _process(_dt):
 if game == null or id.is_empty(): return
 var now = Time.get_ticks_msec()
 if now >= next_ice_drain:
  next_ice_drain = now+500
  capture_ice()
 if game.rtc != null and now >= next_ice_sample and game.rtc.get_connection_state() != WebRTCPeerConnection.STATE_CONNECTED:
  next_ice_sample = now+2000
  sample_transport()
 var state = game.rtc.get_connection_state() if game.rtc != null else -1
 if state != rtc_state:
  rtc_state = state
  record("rtc",{"state":state})
  sample_transport()
  flush()
 if OS.has_feature("web"):
  var visible = not JavaScriptBridge.eval("document.hidden")
  if visible != visible_state:
   visible_state = visible
   record("visibility",{"visible":visible})
 if Time.get_ticks_msec() >= next_flush:
  next_flush = Time.get_ticks_msec()+15000
  if game.mode != "solo":
   sample_transport()
   record("summary",{"rtt":int(game.rtt),"rx":game.rx,"tx":game.tx,"gaps":game.snapshot_gaps,"actors":game.players.size()})
  flush()
