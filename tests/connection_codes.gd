extends SceneTree
const Codes = preload("res://src/connection_codes.gd")
class FakeRTC extends WebRTCPeerConnectionExtension:
 var descriptions := 0
 var state := WebRTCPeerConnection.STATE_NEW
 var gathering := WebRTCPeerConnection.GATHERING_STATE_NEW
 func _get_connection_state() -> WebRTCPeerConnection.ConnectionState: return state
 func _get_gathering_state() -> WebRTCPeerConnection.GatheringState: return gathering
 func _get_signaling_state() -> WebRTCPeerConnection.SignalingState: return WebRTCPeerConnection.SIGNALING_STATE_HAVE_LOCAL_OFFER
 func _close(): state = WebRTCPeerConnection.STATE_CLOSED
 func _set_local_description(_type: String, _sdp: String) -> Error:
  descriptions += 1
  return OK

class FakeLobby extends "res://src/private_lobby.gd":
 signal complete_request
 var response := {}
 var sent := {}
 func request_data(_data: Dictionary, _generation: int) -> Dictionary:
  sent = _data.duplicate(true)
  await complete_request
  return response

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
 var mixed = [{"urls":["stun:stun.cloudflare.com:3478","turn:turn.cloudflare.com:3478?transport=udp","turns:turn.cloudflare.com:5349?transport=tcp","turns:turn.cloudflare.com:443?transport=tcp"],"username":"u","credential":"c"}]
 var tls = relay.tls_only(mixed)
 check(tls.size()==1 and tls[0].urls==["turns:turn.cloudflare.com:443?transport=tcp"] and tls[0].credential=="c","TLS route allowed another transport or lost credentials")
 check(mixed[0].urls.size()==4,"TLS filtering modified shared credentials")
 check(relay.tls_only([{"urls":["turn:turn.cloudflare.com:443?transport=tcp"]}]).is_empty(),"TLS route silently accepted non-TLS server")
 call_deferred("scene_checks")

func scene_checks():
 var scene = load("res://main.tscn").instantiate()
 root.add_child(scene)
 # A closed connection can still deliver queued browser callbacks.
 var previous = FakeRTC.new()
 scene.rtc = previous
 scene.local_signal = {"type":"", "sdp":"", "ice":[]}
 scene.bind_rtc_callbacks(scene.connection_generation)
 scene.solo()
 var current = FakeRTC.new()
 scene.rtc = current
 scene.local_signal = {"type":"", "sdp":"", "ice":[]}
 previous.session_description_created.emit("offer","v=0 old")
 previous.ice_candidate_created.emit("0",0,"candidate:old")
 check(current.descriptions == 0 and scene.local_signal.sdp == "" and scene.local_signal.ice.is_empty(),"Late callbacks corrupted replacement connection")
 scene.bind_rtc_callbacks(scene.connection_generation)
 current.session_description_created.emit("offer","v=0 current")
 current.ice_candidate_created.emit("0",0,"candidate:current")
 check(current.descriptions == 1 and scene.local_signal.sdp == "v=0 current" and scene.local_signal.ice.size() == 1,"Current callbacks were discarded")
 scene.show_pairing("host")
 scene.toggle_menu()
 check(scene.setup_menu.visible and not scene.signal_panel.visible,"Menu did not open over pending pairing")
 scene.toggle_menu()
 check(not scene.setup_menu.visible and scene.signal_panel.visible,"Pending pairing could not resume from Menu")
 current.state = WebRTCPeerConnection.STATE_CONNECTED
 scene.signal_panel.hide()
 scene.toggle_menu()
 scene.toggle_menu()
 check(not scene.signal_panel.visible,"Menu reopened pairing for an established connection")
 scene.solo()
 scene.signal_out.text = "stale code"
 scene.signal_in.text = "stale answer"
 scene.solo()
 check(scene.signal_out.text.is_empty() and scene.signal_in.text.is_empty(),"Old codes survived reset")
 scene.show_pairing("host")
 var invitation = {"game":"ember-coop","version":1,"protocol":1,"session":"0123456789abcdef0123456789abcdef","type":"offer","sdp":"v=0\r\n","ice":[["0",0,"candidate:x"]]}
 scene.signal_in.text = Codes.encode(invitation)
 scene.rtc_accept()
 check(scene.rtc == null and scene.status.text.begins_with("That is an invitation"),"Host accepted its own invitation")
 scene.show_pairing("client")
 invitation.type = "answer"
 scene.signal_in.text = Codes.encode(invitation)
 scene.rtc_accept()
 check(scene.rtc == null and scene.status.text.begins_with("That is a reply"),"Guest accepted a reply as an invitation")
 scene.solo()
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
 check(scene.mode == "solo" and scene.setup_menu.visible and scene.status.text.begins_with("Connection test failure"),"Failure did not return to setup")
 scene.diagnostics.begin()
 for i in range(100): scene.diagnostics.record("rtc",{"state":i % 6})
 check(scene.diagnostics.events.size()==64,"Diagnostic buffer is not bounded")
 check(scene.diagnostics.events[0].seq==38,"Diagnostic event sequence lost")
 check(not scene.diagnostics.report().contains("Bearer"),"Diagnostic report contains authorization")
 # Cancelling a lobby entry while HTTP is in flight must not resurrect it.
 var canvas = scene.lobby.panel.get_parent()
 scene.lobby.panel.free()
 scene.lobby.free()
 var fake_lobby = FakeLobby.new()
 scene.add_child(fake_lobby)
 fake_lobby.setup(scene,canvas)
 fake_lobby.set_process(false)
 check(fake_lobby.service_error(404,"room_expired").contains("HTTP 404 · room_expired"),"Missing room error diagnostic")
 check(fake_lobby.service_error(409,"session_mismatch").contains("HTTP 409 · session_mismatch"),"Missing signaling conflict diagnostic")
 check(not fake_lobby.service_error(500,"private response body").contains("private response body"),"Untrusted service response exposed")
 check(fake_lobby.service_error(409,"retry_unsupported").contains("reload") and fake_lobby.service_error(409,"retry_unsupported").contains("HTTP 409 · retry_unsupported"),"Unsupported retry lost reload guidance or diagnostics")
 scene.lobby = fake_lobby
 fake_lobby.active = true
 fake_lobby.response = {"version":1,"id":"ABCDEF12","role":"client"}
 fake_lobby.enter_room("join","ABCDEF12")
 check(fake_lobby.busy,"Lobby request did not start")
 scene.solo()
 fake_lobby.complete_request.emit()
 check(not fake_lobby.active and fake_lobby.room_id == "" and scene.rtc == null,"Cancelled lobby response resurrected a session")
 fake_lobby.active = true
 fake_lobby.panel.show()
 scene.toggle_menu()
 check(scene.setup_menu.visible and not fake_lobby.panel.visible,"Menu did not hide lobby")
 scene.toggle_menu()
 check(fake_lobby.panel.visible and not scene.setup_menu.visible,"Menu did not restore lobby")
 # A connected session survives the peer completing directory cleanup first.
 var live_peer = FakeRTC.new()
 live_peer.state = WebRTCPeerConnection.STATE_CONNECTED
 scene.rtc = live_peer
 fake_lobby.room_id = "ABCDEF12"
 fake_lobby.response = {"error":"Room full, closed or expired; refresh and try again"}
 fake_lobby.sync_room()
 fake_lobby.complete_request.emit()
 check(scene.rtc == live_peer and not fake_lobby.active and not fake_lobby.panel.visible,"Signaling cleanup terminated connected gameplay")
 check(scene.diagnostics.events.back().event == "lobby_end" and scene.diagnostics.events.back().cause == "error_after_connected","Cleanup decision not diagnosed")
 # ICE may finish after sync starts but before a missing-room response arrives.
 fake_lobby.active = true
 fake_lobby.panel.show()
 fake_lobby.failures = 2
 live_peer.state = WebRTCPeerConnection.STATE_CONNECTING
 fake_lobby.sync_room()
 live_peer.state = WebRTCPeerConnection.STATE_CONNECTED
 fake_lobby.complete_request.emit()
 check(scene.rtc == live_peer and not fake_lobby.active and not fake_lobby.panel.visible,"In-flight signaling cleanup terminated newly connected gameplay")
 # Once established, lobby cleanup must not shorten the ICE recovery grace.
 # A sync sent while connected can finish during a brief disconnection.
 scene.local_signal = {"sdp":"v=0", "ice":[]}
 scene.signal_finished = true
 scene.mode = "client"
 fake_lobby.active = true
 fake_lobby.failures = 2
 live_peer.state = WebRTCPeerConnection.STATE_CONNECTED
 fake_lobby.sync_room()
 live_peer.state = WebRTCPeerConnection.STATE_DISCONNECTED
 scene.rtc_update(120000)
 fake_lobby.complete_request.emit()
 check(scene.rtc == live_peer and not fake_lobby.active,"Lobby error bypassed established transport disconnect grace")
 # A successful but incomplete acknowledgement also retains establishment
 # across polls; the next request can start during a temporary interruption.
 if scene.rtc == live_peer:
  fake_lobby.active = true
  fake_lobby.response = {"version":1,"complete":false}
  live_peer.state = WebRTCPeerConnection.STATE_CONNECTED
  fake_lobby.sync_room()
  fake_lobby.complete_request.emit()
  fake_lobby.response = {"error":"Room closed"}
  fake_lobby.failures = 2
  live_peer.state = WebRTCPeerConnection.STATE_DISCONNECTED
  fake_lobby.sync_room()
  fake_lobby.complete_request.emit()
  check(scene.rtc == live_peer and not fake_lobby.active,"Lobby forgot established transport between sync polls")
  scene.rtc_update(131001)
  check(scene.rtc == null,"Established lobby bypassed terminal disconnect timeout")
  var failure_events = scene.diagnostics.events.filter(func(e): return e.event == "failure")
  check(failure_events.back().source == "disconnect_timeout" and failure_events.back().established,"Failure lost pre-teardown source/establishment")
 check(not fake_lobby.transport_established,"Lobby close retained establishment for the next attempt")
 # Before the first connection, setup still fails after three sync errors.
 var unconnected = FakeRTC.new()
 unconnected.state = WebRTCPeerConnection.STATE_CONNECTING
 scene.rtc = unconnected
 fake_lobby.active = true
 fake_lobby.room_id = "ABCDEF12"
 fake_lobby.failures = 2
 fake_lobby.response = {"error":"Room closed"}
 fake_lobby.sync_room()
 fake_lobby.complete_request.emit()
 check(scene.rtc == null and not fake_lobby.active,"Unestablished setup ignored its sync failure limit")
 var setup_failures = scene.diagnostics.events.filter(func(e): return e.event == "failure")
 check(setup_failures.back().source == "lobby_errors" and not setup_failures.back().established,"Setup failure attribution incorrect")
 # Entry advertises support before the first sync so immediate ICE failures
 # still offer a retry. A later sync must not be required to learn this.
 fake_lobby.active = true
 fake_lobby.response = {"version":1,"id":"ABCDEF12","role":"client","retrySupported":true}
 fake_lobby.enter_room("join","ABCDEF12")
 fake_lobby.complete_request.emit()
 scene.rtc_route_mode = 0
 check(fake_lobby.retry_supported and fake_lobby.sent.action == "join","Entry did not retain retry capability")
 check(fake_lobby.offer_compatibility_retry("No candidates","no_candidates"),"Failure before first sync lost retry offer")
 fake_lobby.room_id = "" # This fixture teardown has no server room to leave.
 scene.solo()
 # Failed setup retains membership only when the service supports retry.
 fake_lobby.active = true
 fake_lobby.room_id = "ABCDEF12"
 fake_lobby.role = "client"
 scene.connection_route.select(0)
 scene.rtc_route_mode = 0
 check(not fake_lobby.offer_compatibility_retry("Connection failed","rtc_terminal"),"Old service offered unsupported retry")
 fake_lobby.retry_supported = true
 check(not fake_lobby.offer_compatibility_retry("Relay denied","setup"),"Credential failure offered transport retry")
 var established_peer = FakeRTC.new()
 established_peer.state = WebRTCPeerConnection.STATE_CONNECTED
 scene.rtc = established_peer
 check(not fake_lobby.offer_compatibility_retry("Disconnected","disconnect_timeout"),"Established transport offered setup retry before lobby sampled it")
 check(scene.rtc == established_peer,"Rejected retry closed connected transport")
 scene.reset_network()
 fake_lobby.transport_established = false
 var failed_peer = FakeRTC.new()
 scene.rtc = failed_peer
 check(fake_lobby.offer_compatibility_retry("Disconnected before connecting","disconnect_timeout"),"Unestablished disconnect did not offer compatibility retry")
 check(scene.rtc == null and fake_lobby.active and fake_lobby.retry_button.visible,"Retry did not retain room and tear down failed transport")
 fake_lobby.retry_button.pressed.emit()
 fake_lobby.response = {"version":1,"epoch":1,"retrySupported":true,"signal":""}
 fake_lobby.sync_room()
 check(fake_lobby.sent.retryTls and fake_lobby.sent.epoch == 0 and not fake_lobby.sent.ready,"Retry request did not fence old attempt")
 fake_lobby.complete_request.emit()
 check(fake_lobby.epoch == 1 and scene.connection_route.selected == 0 and scene.selected_connection_route() == 3 and not fake_lobby.setup_failed and not fake_lobby.accepted and not fake_lobby.published,"Retry did not reset client for fresh TLS offer")
 check(not fake_lobby.offer_compatibility_retry("Failed again","rtc_terminal"),"TLS retry offered repeatedly")
 # Compatibility status survives normal polling instead of reverting to an
 # ordinary route label.
 check(fake_lobby.panel.visible,"Coordinated retry did not restore setup panel")
 fake_lobby.response = {"version":1,"epoch":1,"retrySupported":true,"players":2,"signal":""}
 fake_lobby.sync_room()
 fake_lobby.complete_request.emit()
 check(scene.status.text.contains("Compatibility (TLS 443)"),"Polling hid active compatibility route")
 # A peer that did not click retry switches on the next sync too.
 fake_lobby.epoch = 0
 fake_lobby.setup_failed = false
 fake_lobby.retry_requested = false
 fake_lobby.panel.hide()
 scene.connection_route.select(0)
 fake_lobby.sync_room()
 fake_lobby.complete_request.emit()
 check(fake_lobby.epoch == 1 and scene.connection_route.selected == 0 and scene.selected_connection_route() == 3,"Partner did not follow coordinated TLS retry")
 check(fake_lobby.panel.visible,"Remote retry did not restore hidden setup panel")
 scene.connection_route.select(2)
 check(scene.selected_connection_route() == 3,"Menu edits bypassed TLS enforcement during retry")
 scene.connection_route.select(0)
 # Leaving while a retry response is pending must not resurrect setup.
 fake_lobby.epoch = 0
 scene.connection_route.select(0)
 fake_lobby.sync_room()
 fake_lobby.close()
 fake_lobby.complete_request.emit()
 check(scene.selected_connection_route() == 0,"Retry forced TLS for a later room")
 check(scene.connection_route.selected == 0,"Late retry response changed route after leaving")
 check(fake_lobby.epoch == 0 and not fake_lobby.retry_supported and not fake_lobby.retry_requested and not fake_lobby.retry_button.visible,"Leaving retained retry state")
 # If an older partner joins while a failed host is waiting to retry, the
 # next poll must close setup with actionable guidance instead of hanging.
 fake_lobby.active = true
 fake_lobby.room_id = "ABCDEF12"
 fake_lobby.setup_failed = true
 fake_lobby.retry_supported = true
 fake_lobby.response = {"version":1,"epoch":0,"retrySupported":false,"signal":""}
 fake_lobby.sync_room()
 fake_lobby.complete_request.emit()
 check(not fake_lobby.active and scene.setup_menu.visible and scene.status.text.contains("reload"),"Mixed-version failed setup stranded a room")
 fake_lobby.complete_request.emit() # Best-effort leave fixture.
 fake_lobby.room_id = "" # Fixture cleanup needs no HTTP leave.
 scene.solo()
 print("CONNECTION CODE/SETUP TEST ","FAIL" if failed else "PASS")
 scene.free()
 quit(1 if failed else 0)
