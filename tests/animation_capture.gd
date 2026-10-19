extends SceneTree
var game
var output := "res://build/animation-before"
func _initialize():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
 call_deferred("capture_frames")

func capture_frames():
 game = load("res://main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 game.setup_menu.hide()
 game.status.text = "Animation frame audit / actual scene"
 game.players[1].x = 650.0
 game.update_sprites()
 var sprite = game.sprites[1]
 if not sprite is AnimatedSprite2D:
  push_error("Licensed character missing for frame audit")
  quit(1)
  return
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
 var count = 0
 for clip in game.animations.get_animation_names():
  for facing in [1,-1]:
   for frame in game.animations.get_frame_count(clip):
    sprite.show_frame(clip,frame,Vector2(650,448),facing)
    game.queue_redraw()
    await process_frame
    await RenderingServer.frame_post_draw
    var filename = "%s/%s-%s-%02d.png" % [output,clip.replace(" ","_"),"R" if facing>0 else "L",frame]
    root.get_texture().get_image().save_png(filename)
    count += 1
 var trace = []
 for action in ["jump","attack"]:
  game.solo()
  game.setup_menu.hide()
  game.status.text = "Live " + action + " / core inputs / actual scene"
  for t in range(170): game.core.step(1,false,false)
  game.sync_core_view()
  for t in range(55 if action == "jump" else 24):
   game.core.step(0,action == "jump",action == "attack")
   game.sync_core_view()
   game.update_sprites()
   game.enemy_flash = maxf(0,game.enemy_flash-1.0/60)
   game.queue_redraw()
   var actor = game.sprites[1]
   var state = game.players[1]
   trace.append({"action":action,"tick":t,"clip":actor.animation,"frame":actor.frame,"x":state.x,"y":state.y,"vy":state.vy,"grounded":state.grounded,"hp":game.enemy_hp})
   await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("%s/live-%s-%02d.png" % [output,action,t])
 var file = FileAccess.open(output+"/playback.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(trace," "))
 print("ANIMATION FRAME CAPTURE PASS frames=",count," live_ticks=",trace.size()," output=",output)
 game.free()
 quit()
