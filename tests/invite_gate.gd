extends SceneTree
const Game = preload("res://src/main.gd")
class FakeInvite extends "res://src/invite_gate.gd":
 var calls := 0
 func send_validation(_attempt: int): calls += 1
var failed := false
func check(ok: bool, text: String):
 if not ok: failed = true; push_error(text)
func _initialize(): call_deferred("run")
func run():
 var game = Game.new()
 root.add_child(game)
 game.lobby.set_process(false)
 game.invite.free()
 game.invite = FakeInvite.new()
 game.add_child(game.invite)
 var canvas = game.settings_menu.get_parent()
 game.invite.setup(game,canvas)
 var gate = game.invite
 gate.open()
 check(gate.active() and game.ui_blocking() and not game.header.visible and not game.settings_button.visible,"Invite did not precede the menus")
 game.chat.update_positions()
 check(not game.chat.available() and not game.chat.observed_available,"Invite allowed chat or reported stale availability")
 check(game.settings_menu.is_ancestor_of(game.diagnostics.copy_button) and not game.setup_menu.is_ancestor_of(game.diagnostics.copy_button),"Diagnostics remained in the main menu")
 gate.begin("bad")
 check(gate.calls==0 and gate.key.is_empty(),"Malformed invite reached the service")
 gate.begin("a".repeat(64))
 var previous = gate.validation_id
 gate.begin("b".repeat(64))
 check(gate.calls==1 and gate.busy() and gate.confirm.disabled,"Duplicate invite submission overlapped")
 gate.complete(HTTPRequest.RESULT_SUCCESS,401,PackedStringArray(),PackedByteArray(),previous)
 check(gate.active() and gate.key.is_empty() and not gate.busy(),"Rejected invite unlocked the game")
 gate.begin("b".repeat(64))
 var origin_attempt = gate.validation_id
 gate.complete(HTTPRequest.RESULT_SUCCESS,403,PackedStringArray(),JSON.stringify({"error":"origin_denied"}).to_utf8_buffer(),origin_attempt)
 check(gate.active() and gate.hint.text.contains("page") and not gate.hint.text.contains("invalid"),"Origin rejection blamed the invite")
 gate.begin("b".repeat(64))
 gate.complete(HTTPRequest.RESULT_SUCCESS,403,PackedStringArray(),JSON.stringify({"error":"invitation_expired"}).to_utf8_buffer(),gate.validation_id)
 check(gate.active() and gate.hint.text.contains("expired"),"Invite expiry was not actionable")
 gate.begin("b".repeat(64))
 gate.complete(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify({"version":1,"rooms":[]}).to_utf8_buffer(),previous)
 check(gate.busy() and gate.active(),"An old invite response consumed a replacement attempt")
 gate.complete(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify({"version":1,"rooms":[]}).to_utf8_buffer(),gate.validation_id)
 check(not gate.active() and gate.key=="b".repeat(64) and gate.entry.text.is_empty(),"Validated invite was lost or retained in its field")
 check(game.setup_menu.visible and game.header.visible and game.settings_button.visible,"Validated invite did not open the main menu")
 game.toggle_settings()
 check(game.settings_menu.visible and not game.setup_menu.visible and game.ui_blocking(),"Settings did not isolate its input/menu")
 game.close_settings()
 check(game.setup_menu.visible and not game.settings_menu.visible,"Settings did not return to the main menu")
 game.setup_menu.hide()
 game.lobby.active = true
 game.lobby.room_id = "ABCDEF12"
 game.lobby.role = "client"
 game.lobby.panel.show()
 game.toggle_settings()
 game.lobby.restart_compatibility(game.lobby.generation)
 check(game.settings_menu.visible and not game.lobby.panel.visible,"TLS retry opened a second panel over Settings")
 game.close_settings()
 check(game.lobby.panel.visible and not game.settings_menu.visible,"Settings did not restore pending connection setup")
 game.lobby.room_id = ""
 game.lobby.active = false
 gate.open()
 gate.begin("c".repeat(64))
 previous = gate.validation_id
 gate.open()
 gate.begin("d".repeat(64))
 gate.complete(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify({"version":1,"rooms":[]}).to_utf8_buffer(),previous)
 check(gate.active() and gate.busy() and gate.key.is_empty(),"Canceled invite response reopened a prior session")
 for code in [200,429,503]:
  gate.complete(HTTPRequest.RESULT_SUCCESS,code,PackedStringArray(),JSON.stringify({"version":1,"rooms":"invalid","error":"DO-NOT-DISPLAY"}).to_utf8_buffer(),gate.validation_id)
  check(gate.active() and gate.key.is_empty() and not gate.hint.text.contains("DO-NOT-DISPLAY"),"Bad validation response escaped the gate")
  gate.begin("d".repeat(64))
 gate.complete(HTTPRequest.RESULT_CANT_CONNECT,0,PackedStringArray(),PackedByteArray(),gate.validation_id)
 check(gate.active() and not gate.busy() and not gate.confirm.disabled,"Network failure stranded invite entry")
 for malformed in [{"version":[1],"rooms":[]},{"version":"1","rooms":[]},{"error":["origin_denied"]},{"error":{"code":"origin_denied"}}]:
  gate.begin("d".repeat(64))
  gate.complete(HTTPRequest.RESULT_SUCCESS,403 if malformed.has("error") else 200,PackedStringArray(),JSON.stringify(malformed).to_utf8_buffer(),gate.validation_id)
  check(gate.active() and not gate.busy() and gate.key.is_empty() and not gate.hint.text.contains("Checking"),"Malformed response type stranded invite entry")

 await process_frame
 game.free()
 print("INVITE/SETTINGS CONTRACTS ","FAIL" if failed else "PASS")
 quit(1 if failed else 0)
