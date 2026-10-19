extends Node
# Bounded, deliberately selected connection metadata only.
const BUILD := "diagnostics-v3"
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
var sample_busy := false
var sample_callback
var copy_callback
var legacy_upload := false
var online_state := true
var context := {"commit":"unknown","payload":"unknown","built":"unknown","dirty":false,"site":"other","test":"none"}

func begin():
 if OS.has_feature("web"):
  var helper = JavaScriptBridge.get_interface("EmberConnectionDiagnostics")
  if helper != null:
   helper.reset()
   var build_context = JSON.parse_string(str(helper.context()))
   if build_context is Dictionary: context = build_context
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
 if OS.has_feature("web"):
  online_state = bool(JavaScriptBridge.eval("navigator.onLine"))
  record("network",{"online":online_state})

func record(kind: String, values := {}):
 if id.is_empty(): return
 sequence += 1
 var item = {"seq":sequence,"event":kind,"ms":mini(Time.get_ticks_msec()-started,86400000),"role":game.mode}
 item.merge(values)
 events.append(item)
 if events.size()>64:
  events.pop_front()

func failure_context(source: String) -> Dictionary:
 return {"source":source,"state":game.rtc.get_connection_state() if game.rtc != null else -1,"established":game.lobby != null and game.lobby.transport_established}

func report() -> String:
 return JSON.stringify({"version":1,"build":BUILD,"attempt":id,"context":context,"events":events})

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
 # Negotiate legacy uploads only on an explicit schema rejection. Rich local
 # reports remain intact; network/service/auth failures never trigger downgrade.
 var upload_events: Array = []
 for event in events:
  if event.seq <= sent: continue
  if legacy_upload and event.event in ["network","lobby_end"]: continue
  var upload = event.duplicate(true)
  if legacy_upload and upload.event == "transport":
   for field in upload.keys():
    if field not in ["seq","event","ms","role","local","remote","protocol","rtt"]: upload.erase(field)
  if legacy_upload and upload.event == "failure":
   for field in ["source","state","established"]: upload.erase(field)
  upload_events.append(upload)
 if upload_events.is_empty():
  sent = count
  request.queue_free()
  busy = false
  return
 var payload = {"version":1,"build":"diagnostics-v2" if legacy_upload else BUILD,"attempt":id,"events":upload_events}
 if not legacy_upload: payload.context = context
 var error = request.request(ENDPOINT,["Authorization: Bearer "+game.relay_access.text.strip_edges(),"Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify(payload))
 var retry_legacy := false
 if error == OK:
  var response = await request.request_completed
  if attempt == id and response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200: sent = count
  if attempt == id and not legacy_upload and response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 400:
   var rejection = JSON.parse_string(response[3].get_string_from_utf8())
   if rejection is Dictionary and rejection.get("error") == "invalid_diagnostics":
    legacy_upload = true
    retry_legacy = true
 request.queue_free()
 busy = false
 if retry_legacy: flush()

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
 if sample_busy or not OS.has_feature("web"): return
 var helper = JavaScriptBridge.get_interface("EmberConnectionDiagnostics")
 if helper == null: return
 var attempt = id
 var sampled_role = game.mode
 sample_busy = true
 sample_callback = JavaScriptBridge.create_callback(func(args):
  sample_busy = false
  if id != attempt or args.size() == 0: return
  var result = JSON.parse_string(str(args[0]))
  if result is Dictionary:
   result.role = sampled_role
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
  var online = bool(JavaScriptBridge.eval("navigator.onLine"))
  if online != online_state:
   online_state = online
   record("network",{"online":online})
   flush()
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
