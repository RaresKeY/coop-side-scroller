extends SceneTree
const Codes = preload("res://src/connection_codes.gd")
class FakeRTC extends WebRTCPeerConnectionExtension:
 var state := WebRTCPeerConnection.STATE_NEW
 var gathering := WebRTCPeerConnection.GATHERING_STATE_NEW
 func _get_connection_state() -> WebRTCPeerConnection.ConnectionState: return state
 func _get_gathering_state() -> WebRTCPeerConnection.GatheringState: return gathering
 func _get_signaling_state() -> WebRTCPeerConnection.SignalingState: return WebRTCPeerConnection.SIGNALING_STATE_HAVE_LOCAL_OFFER
 func _close(): state = WebRTCPeerConnection.STATE_CLOSED

var failed := false
func check(value: bool, message: String):
 if not value:
  failed = true
  push_error(message)

func _initialize():
 var data = {"game":"ember-coop","version":1,"protocol":1,"session":"0123456789abcdef0123456789abcdef","type":"offer","sdp":"v=0\r\ns=test\r\n","ice":[["0",0,"candidate:1 1 UDP 1 192.0.2.1 5000 typ host"]]}
 check(not Codes.decode(Codes.encode(data)).is_empty(),"Offer round trip")
 data.type = "answer"
 check(not Codes.decode(Codes.encode(data)).is_empty(),"Answer round trip")
 for text in ["", "!not-base64!", "A".repeat(65540),Marshalls.utf8_to_base64("[]")]:
  check(Codes.decode(text).is_empty(),"Invalid code accepted")
 for patch in [{"version":2},{"protocol":2},{"game":"other"},{"session":"old"},{"sdp":23},{"sdp":"x"},{"ice":[]},{"ice":[["0",0.5,"candidate:x"]]},{"ice":[["0",-1,"candidate:x"]]},{"ice":[["0",0,"invalid"]]},{"ice":[[[],0,"candidate:x"]]}]:
  var invalid = data.duplicate(true)
  invalid.merge(patch,true)
  check(Codes.decode(Codes.encode(invalid)).is_empty(),"Invalid envelope accepted: " + str(patch))
 var relay = load("res://src/relay_credentials.gd")
 var now = Time.get_unix_time_from_system()
 var credentials = {"version":1,"expiresAt":int(now)+3600,"iceServers":[{"urls":["turns:turn.cloudflare.com:443?transport=tcp"],"username":"temporary-user","credential":"temporary-password"}]}
 check(not relay.decode(JSON.stringify(credentials).to_utf8_buffer(),now).is_empty(),"Valid temporary relay credentials rejected")
 for patch in [{"expiresAt":int(now)-1},{"iceServers":[]},{"iceServers":[{"urls":["turn:evil.invalid:3478"],"username":"u","credential":"c"}]},{"iceServers":[{"urls":["turn:turn.cloudflare.com:53"],"username":"u","credential":"c"}]}]:
  var invalid = credentials.duplicate(true)
  invalid.merge(patch,true)
  check(relay.decode(JSON.stringify(invalid).to_utf8_buffer(),now).is_empty(),"Invalid relay credentials accepted")
 call_deferred("scene_checks")

func scene_checks():
 var scene = load("res://main.tscn").instantiate()
 root.add_child(scene)
 scene.signal_out.text = "stale code"
 scene.signal_in.text = "stale answer"
 scene.solo()
 check(scene.signal_out.text.is_empty() and scene.signal_in.text.is_empty(),"Old codes survived reset")
 scene.signal_in.text = "invalid"
 scene.rtc_accept()
 check(scene.rtc == null and scene.status.text.begins_with("Invalid/incompatible"),"Invalid code changed session")
 scene.signal_in.text = Codes.encode({"game":"ember-coop","version":1,"protocol":1,"session":"0123456789abcdef0123456789abcdef","type":"answer","sdp":"v=0\r\n","ice":[["0",0,"candidate:x"]]})
 scene.rtc_accept()
 check(scene.rtc == null and scene.status.text.begins_with("Answer does not match"),"Answer without offer accepted")
 # Mismatched session cannot replace a pending host offer.
 scene.rtc = FakeRTC.new()
 scene.mode = "host"
 scene.local_signal = {"session":"ffffffffffffffffffffffffffffffff"}
 var pending = scene.rtc
 scene.rtc_accept()
 check(scene.rtc == pending and scene.status.text.begins_with("Answer does not match"),"Stale answer replaced pending offer")
 scene.solo()
 # Exercise failure branches without pretending to test actual NAT traversal.
 for reason in ["gather", "empty", "connect", "failed", "disconnect", "wait"]:
  var fake = FakeRTC.new()
  scene.rtc = fake
  scene.local_signal = {"sdp":"v=0", "ice":[]}
  var now = 120000
  scene.rtc_started_ms = now
  match reason:
   "gather": scene.rtc_started_ms -= 31000
   "empty": fake.gathering = WebRTCPeerConnection.GATHERING_STATE_COMPLETE
   "connect":
    scene.signal_finished = true
    scene.rtc_connect_ms = now-61000
    fake.state = WebRTCPeerConnection.STATE_CONNECTING
   "failed": fake.state = WebRTCPeerConnection.STATE_FAILED
   "disconnect":
    scene.rtc_disconnected_ms = now-11000
    fake.state = WebRTCPeerConnection.STATE_DISCONNECTED
   "wait":
    scene.signal_finished = true
    scene.rtc_started_ms -= 120000
  scene.rtc_update(now)
  if reason == "wait": check(scene.rtc == fake,"Waiting host offer incorrectly timed out")
  else: check(scene.rtc == null and scene.setup_menu.visible,"Connection failure not handled: " + reason)
  scene.solo()
 # A connection deadline must not kill a later brief interruption.
 var connected = FakeRTC.new()
 connected.state = WebRTCPeerConnection.STATE_CONNECTED
 scene.rtc = connected
 scene.local_signal = {"sdp":"v=0", "ice":[]}
 scene.signal_finished = true
 scene.rtc_connect_ms = 1000
 scene.rtc_update(120000)
 connected.state = WebRTCPeerConnection.STATE_DISCONNECTED
 scene.rtc_update(120001)
 check(scene.rtc == connected,"Established connection skipped disconnect grace")
 scene.rtc_fail("Connection test failure")
 check(scene.mode == "solo" and scene.setup_menu.visible and scene.status.text == "Connection test failure","Failure did not return to setup")
 print("CONNECTION CODE/SETUP TEST ","FAIL" if failed else "PASS")
 scene.free()
 quit(1 if failed else 0)
