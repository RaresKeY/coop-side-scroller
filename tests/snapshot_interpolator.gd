extends SceneTree

const Buffer = preload("res://src/snapshot_interpolator.gd")
var checks := 0

func check(ok: bool, message: String):
 checks += 1
 if not ok:
  push_error(message)
  quit(1)
  assert(ok,message)

func actors(x: float, attack := 0) -> Dictionary:
 return {1:{"x":x,"y":448.0,"attack_id":attack,"animation":1,"face":1}}

func _initialize():
 var buffer = Buffer.new()
 check(buffer.sample(actors(7.0),0)[1].x == 7.0,"empty buffer preserves current state")
 var original = actors(0.0)
 buffer.push(0,original,0)
 original[1].x = 999.0
 buffer.push(3,actors(30.0),50)
 buffer.push(6,actors(60.0,2),100)
 var shown = buffer.sample(actors(60.0,2),125)
 check(is_equal_approx(shown[1].x,15.0),"render between snapshots at 60 FPS")
 check(shown[1].attack_id == 2,"discrete authoritative fields remain current")
 check(buffer.sample(actors(60.0),125,1)[1].x == 60.0,"local input gets no additional interpolation delay")
 shown[1].x = -999.0
 check(is_equal_approx(buffer.sample(actors(60.0),150)[1].x,30.0),"snapshots and outputs are independent copies")
 check(buffer.sample(actors(60.0),400)[1].x == 60.0,"packet gap holds last position without extrapolation")
 buffer.push(9,actors(90.0),410)
 check(buffer.sample(actors(90.0),410)[1].x >= 60.0,"jitter never rewinds presentation")
 buffer.push(9,actors(999.0),411)
 buffer.push(8,actors(999.0),412)
 check(buffer.sample(actors(90.0),600)[1].x == 90.0,"duplicate and old source ticks do not replace history")
 buffer.push(60,actors(600.0),1100)
 check(buffer.sample(actors(600.0),1100)[1].x == 600.0,"suspension resets old trajectory")
 buffer.push(63,{},1150)
 buffer.push(66,actors(5.0),1200)
 check(buffer.sample(actors(5.0),1200)[1].x == 5.0,"observed rejoin cannot interpolate an old lifetime")
 buffer.reset()
 buffer.push(0xfffffffd,actors(0.0),0)
 buffer.push(0,actors(30.0),50)
 buffer.push(3,actors(60.0),100)
 check(is_equal_approx(buffer.sample(actors(60.0),125)[1].x,15.0),"host tick wrap remains continuous")
 for i in range(100): buffer.push(6+i*3,actors(float(i)),150+i*50)
 check(buffer._frames.size() <= Buffer.MAX_FRAMES,"history stays bounded")
 buffer.reset()
 check(buffer.sample(actors(12.0),9000)[1].x == 12.0,"session reset removes old state")
 print("Snapshot interpolation PASS: ",checks," checks")
 quit(0)
