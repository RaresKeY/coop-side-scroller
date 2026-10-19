extends SceneTree
var failed := false
func check(value: bool, message: String):
 if not value:
  failed = true
  push_error(message)
func _initialize():
 call_deferred("verify")
func verify():
 var game = load("res://main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 game.update_sprites()
 var actor = game.sprites[1]
 if not actor.has_method("present"):
  push_error("Licensed character required for visual playback tests")
  game.free()
  quit(1)
  return
 check(actor.scale == Vector2.ONE,"Character is not half the previous 2x size")
 var attack_texture = game.animations.get_frame_texture("Attack 1",0)
 check(attack_texture.region.size.x == 148,"Saber spill was cropped")
 var state = {"animation":3,"attack_id":1,"attack":0.4,"x":650.0,"y":448.0,"face":1,"grounded":true,"vy":0.0}
 var frames = []
 for t in range(24):
  state.attack = (24-t)/60.0
  actor.present(state)
  frames.append(actor.frame)
 check(frames == [0,0,0,1,1,1,1,1,2,2,2,3,3,3,3,4,4,4,4,4,4,4,4,4],"Attack anticipation/strike/recovery timing changed")
 # Actual core input drives the presentation through ascent, apex, fall and landing.
 game.core.configure(1)
 var jump_frames = {}
 for t in range(55):
  game.core.step(0,true,false)
  game.sync_core_view()
  game.update_sprites()
  if actor.animation == "Jump": jump_frames[actor.frame] = true
 for index in range(17): check(jump_frames.has(index),"Held jump never displayed frame " + str(index))
 check(actor.animation == "Idle","Landing did not return to idle")
 # Every jump pose must keep its lowest authored pixel above its foot anchor.
 for index in range(17):
  var image = game.animations.get_frame_texture("Jump",index).get_image()
  check(image.get_used_rect().end.y <= actor.JUMP_FEET[index],"Jump feet penetrate anchor at frame " + str(index))
 # Compare mirrored attack anchors in global coordinates around the same root.
 for face in [1,-1]:
  for index in range(5):
   actor.show_frame("Attack 1",index,Vector2(650,448),face)
   var region = game.animations.get_frame_texture("Attack 1",index).region
   var source_anchor = Vector2(index*128+76-region.position.x,111)
   if face < 0: source_anchor.x = region.size.x-source_anchor.x
   check((actor.offset+source_anchor-region.size*0.5).length()<0.001,"Mirrored attack anchor drift")
 print("CHARACTER VIEW TEST ","FAIL" if failed else "PASS", " jump_frames=",jump_frames.size())
 game.free()
 quit(1 if failed else 0)
