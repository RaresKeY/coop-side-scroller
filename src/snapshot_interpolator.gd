extends RefCounted

const DELAY_TICKS := 6.0
const MAX_FRAMES := 32
const RESET_GAP_MS := 500
var _frames: Array = []
var _source_tick := -1
var _timeline_tick := 0.0
var _render_tick := -INF
var _arrival_ms := 0
var interpolated_samples := 0

func reset():
 _frames.clear()
 _source_tick = -1
 _timeline_tick = 0.0
 _render_tick = -INF
 _arrival_ms = 0
 interpolated_samples = 0

func push(host_tick: int, actors: Dictionary, received_ms: int):
 var source = host_tick & 0xffffffff
 if not _frames.is_empty():
  var delta = (source - _source_tick) & 0xffffffff
  if delta == 0 or delta >= 0x80000000: return
  var previous: Dictionary = _frames.back().actors
  var same_members = previous.size() == actors.size()
  for id in actors:
   if not previous.has(id): same_members = false
  # Resume at current state after suspension or an observed lifetime change.
  if received_ms - _arrival_ms > RESET_GAP_MS or not same_members:
   reset()
  else:
   _timeline_tick += float(delta)
 _source_tick = source
 _arrival_ms = received_ms
 _frames.append({"tick":_timeline_tick,"actors":actors.duplicate(true)})
 while _frames.size() > MAX_FRAMES: _frames.pop_front()

func sample(current: Dictionary, now_ms: int, local_slot := 0) -> Dictionary:
 var result = current.duplicate(true)
 if _frames.is_empty(): return result
 var latest: Dictionary = _frames.back()
 # A monotonic render cursor absorbs arrival jitter; it never extrapolates.
 var wanted = minf(latest.tick, latest.tick - DELAY_TICKS + maxf(0.0,now_ms-_arrival_ms)*0.06)
 _render_tick = maxf(_render_tick, maxf(_frames[0].tick,wanted))
 while _frames.size() > 2 and _frames[1].tick <= _render_tick:
  _frames.pop_front()
 var before: Dictionary = _frames[0]
 var after: Dictionary = before
 for frame in _frames:
  after = frame
  if frame.tick >= _render_tick: break
  before = frame
 var span = after.tick - before.tick
 var weight = clampf((_render_tick-before.tick)/span,0.0,1.0) if span > 0 else 0.0
 for id in result:
  # Until local prediction exists, avoid adding render delay to local input.
  if id == local_slot: continue
  if not before.actors.has(id) or not after.actors.has(id): continue
  # Only positions are delayed. Authority, animation, HP and events stay current.
  result[id].x = lerpf(before.actors[id].x,after.actors[id].x,weight)
  result[id].y = lerpf(before.actors[id].y,after.actors[id].y,weight)
 if weight > 0.0 and weight < 1.0: interpolated_samples += 1
 return result
