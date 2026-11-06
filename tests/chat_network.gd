extends SceneTree
class Session extends "res://src/main.gd":
 var role := "host"
 var sent := false
 var success_at := -1.0
 func _ready():
  super._ready()
  if role=="host": host()
  else: join_game()
 func _physics_process(dt):
  super._physics_process(dt)
  if not sent and chat.names==["Terra","Rae"]:
   sent=chat.submit("Hello from "+player_name+"\nReady to go.")
  if chat.history.size()==2:
   var texts=chat.history.map(func(message): return message.text)
   if "Hello from Terra\nReady to go." in texts and "Hello from Rae\nReady to go." in texts and chat.bubbles.size()==2:
    if success_at<0:
     print("CHAT REAL ENET PASS ",role," names=",chat.names," echoes=",chat.history.size())
     success_at=elapsed
  if success_at>=0 and (role=="client" or elapsed-success_at>1.0): get_tree().quit()
  if elapsed>10:
   push_error("CHAT REAL ENET FAILED "+role+" "+str(chat.names)+" "+str(chat.history))
   get_tree().quit(1)
func _initialize(): call_deferred("run")
func run():
 var scene=Session.new()
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--chat-role="):scene.role=arg.get_slice("=",1)
 root.add_child(scene)
