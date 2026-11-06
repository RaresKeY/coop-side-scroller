extends PanelContainer
# Draw one continuous outline so the translucent tail has no doubled-alpha seam.
const TAIL_LENGTH := 24.0
const TAIL_HALF_WIDTH := 7.0
const TAIL_OFFSET := 18.0
var fill := Color(0.055,0.065,0.08,0.68)
var edge := Color(0.65,0.65,0.65,0.16)
var target := Vector2.ZERO
var has_target := false

func configure(style: StyleBoxFlat):
 fill = style.bg_color
 edge = style.border_color
 var padding = StyleBoxEmpty.new()
 for side in range(4): padding.set_content_margin(side,style.get_content_margin(side))
 add_theme_stylebox_override("panel",padding)
 resized.connect(queue_redraw)
 queue_redraw()

func point_to(local_target: Vector2):
 if not has_target or target != local_target:
  target = local_target
  has_target = true
  queue_redraw()

func footprint() -> Rect2:
 # Reserve the tail before placing nearby bubbles; tails must not cover text.
 return Rect2(position,size+Vector2(0,TAIL_LENGTH))

func tail_points() -> PackedVector2Array:
 if not has_target or size.x<32 or target.y<=size.y+2: return PackedVector2Array()
 var offset = TAIL_OFFSET if target.x<=size.x/2 else -TAIL_OFFSET
 var base = Vector2(clampf(target.x+offset,12,size.x-12),size.y)
 var delta = target-base
 var direction = delta.normalized()
 var length = minf(TAIL_LENGTH,delta.length())
 # Stop on the ray before a slanted tip leaves the panel's horizontal bounds.
 if direction.x<0: length=minf(length,(base.x-1)/-direction.x)
 elif direction.x>0: length=minf(length,(size.x-1-base.x)/direction.x)
 return PackedVector2Array([base-Vector2(TAIL_HALF_WIDTH,0),base+direction*length,base+Vector2(TAIL_HALF_WIDTH,0)])

func _draw():
 if size.x<=0 or size.y<=0: return
 var outline = PackedVector2Array([Vector2.ZERO,Vector2(size.x,0),size])
 var tail = tail_points()
 if not tail.is_empty():
  outline.append(tail[2]);outline.append(tail[1]);outline.append(tail[0])
 outline.append(Vector2(0,size.y))
 draw_colored_polygon(outline,fill)
 outline.append(outline[0])
 draw_polyline(outline,edge,1.0,true)
