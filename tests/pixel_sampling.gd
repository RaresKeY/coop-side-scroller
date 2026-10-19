extends SceneTree
func _initialize(): call_deferred("verify")
func verify():
 var game = load("res://main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 game.setup_menu.hide()
 game.update_sprites()
 var actor = game.sprites[1]
 var worst = 0
 var negative_control := false
 for clip in ["Idle","Attack 1","Run"]:
  for face in [1,-1]:
   actor.show_frame(clip,0,Vector2(650.37,448.21),face)
   actor.scale = Vector2(1.37,1.37)
   actor.show()
   await process_frame
   await RenderingServer.frame_post_draw
   var actual = root.get_texture().get_image()
   var frame = game.animations.get_frame_texture(clip,0)
   var image = frame.get_image()
   image.resize(image.get_width()*8,image.get_height()*8,Image.INTERPOLATE_NEAREST)
   var reference = Sprite2D.new()
   reference.texture = ImageTexture.create_from_image(image)
   reference.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
   reference.position = actor.position
   reference.offset = actor.offset*8
   reference.scale = actor.scale/8
   reference.flip_h = actor.flip_h
   game.add_child(reference)
   actor.hide()
   await process_frame
   await RenderingServer.frame_post_draw
   var expected = root.get_texture().get_image()
   var a = actual.get_data()
   var b = expected.get_data()
   var delta = 0
   for index in a.size(): delta = maxi(delta,absi(int(a[index])-int(b[index])))
   worst = maxi(worst,delta)
   if clip == "Idle" and face == 1:
    reference.position.x += 6
    await process_frame
    await RenderingServer.frame_post_draw
    negative_control = root.get_texture().get_image().get_data() != a
   reference.free()
 print("GPU SUPERSCALE REFERENCE ","PASS" if worst<=3 and negative_control else "FAIL"," maximum_channel_delta=",worst," tolerance=3 negative_control=",negative_control)
 game.free()
 quit(0 if worst<=3 and negative_control else 1)
