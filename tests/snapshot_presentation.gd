extends SceneTree

const Game = preload("res://src/main.gd")
var checks := 0

func check(ok: bool, message: String):
 checks += 1
 if not ok:
  push_error(message)
  quit(1)
  assert(ok,message)

func _initialize():
 run.call_deferred()

func run():
 var game = Game.new()
 root.add_child(game)
 game.set_process(false)
 game.set_physics_process(false)
 for sprite in game.sprites.values(): sprite.queue_free()
 game.sprites.clear()
 var frames = SpriteFrames.new()
 frames.remove_animation("default")
 var atlas = AtlasTexture.new()
 atlas.atlas = GradientTexture2D.new()
 atlas.region = Rect2(0,0,64,64)
 for clip in ["Idle","Run","Jump","Attack 1","Walk"]:
  frames.add_animation(clip)
  frames.set_animation_speed(clip,12.0)
  for i in range(17 if clip == "Jump" else 5): frames.add_frame(clip,atlas)
 game.animations = frames
 var state = {"x":60.0,"y":448.0,"vy":0.0,"face":1,"attack":0.0,"attack_id":0,"animation":1,"grounded":true}
 var local_state = state.duplicate()
 local_state.x = 260.0
 game.players = {1:state,2:local_state}
 game.update_sprites()
 var sprite = game.sprites[1]
 check(sprite.local_ticks == 1,"one fixed update advances one pose tick")
 game.mode = "client"
 var now = Time.get_ticks_msec()
 for i in range(3):
  var source = state.duplicate()
  source.x = float(i*30)
  game.snapshot_interpolator.push(i*3,{1:source,2:local_state},now-125+i*50)
 for i in range(120): game.update_sprite_positions()
 check(sprite.local_ticks == 1,"render frequency cannot advance animation clocks")
 check(sprite.position.x < state.x,"real main callback interpolates remote positions")
 check(game.sprites[2].position.x == local_state.x,"real main callback keeps local position current")
 check(state.x == 60.0 and game.players[1].x == 60.0,"rendering preserves authoritative players")
 game.update_sprites()
 check(sprite.local_ticks == 2 and sprite.age == 1,"fixed animation cadence survives high render frequency")
 game.reset_network()
 check(game.snapshot_interpolator._frames.is_empty(),"real session reset clears interpolation history")
 game.queue_free()
 await process_frame
 print("Snapshot presentation integration PASS: ",checks," checks")
 quit(0)
