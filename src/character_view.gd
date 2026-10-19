extends AnimatedSprite2D
# Presentation only: physics, logical states and damage stay in C++.
const PIXEL_SHADER = preload("res://shaders/pixel_superscale.gdshader")
const WORLD_SCALE := 1.0
const ATTACK_ENDS := [3,8,11,15,24] # anticipation, lift, apex, downstroke, contact/recovery
const ATTACK_REGIONS := [Rect2(0,0,148,128),Rect2(148,0,108,128),Rect2(256,0,128,128),Rect2(384,0,148,128),Rect2(536,0,128,128)]
const JUMP_FEET := [128,128,128,128,128,119,108,106,109,118,117,128,128,128,128,128,128]
const LANDING := [13,14,15,16,16,14,13,12,0]
var last_animation := -1
var last_attack := -1
var last_grounded := true
var local_ticks := 0
var landing_tick := -1
var age := 0
var sampled_clip := ""
var sampled_frame := -1

func _init():
 scale = Vector2.ONE * WORLD_SCALE
 texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
 var sampling = ShaderMaterial.new()
 sampling.shader = PIXEL_SHADER
 material = sampling

static func make_frames() -> SpriteFrames:
 var frames = SpriteFrames.new()
 frames.remove_animation("default")
 var metadata = JSON.parse_string(FileAccess.get_file_as_string("res://assets/craftpix-clips.json"))
 var speeds = {"Idle":6,"Walk":12,"Run":24,"Jump":24,"Attack 1":12.5,"Hurt":14,"Dead":10}
 for clip in speeds:
  var path = "res://assets/private/character/" + clip + ".png"
  if not ResourceLoader.exists(path): continue
  var texture = load(path) as Texture2D
  frames.add_animation(clip)
  frames.set_animation_speed(clip,speeds[clip])
  frames.set_animation_loop(clip,clip in ["Idle","Walk","Run"])
  var cells = metadata.get(clip,range(texture.get_width()/128)) if metadata is Dictionary else range(texture.get_width()/128)
  for cell in cells:
   var region = AtlasTexture.new()
   region.atlas = texture
   region.region = ATTACK_REGIONS[int(cell)] if clip == "Attack 1" else Rect2(int(cell)*128,0,128,128)
   frames.add_frame(clip,region)
 return frames

# Also used by the finite full-scene frame audit, with no product frame controls.
func show_frame(clip: String, index: int, feet: Vector2, facing: int):
 if is_playing(): stop()
 if animation != clip: animation = clip
 var selected = clampi(index,0,sprite_frames.get_frame_count(clip)-1)
 if frame != selected: frame = selected
 flip_h = facing < 0
 var texture = sprite_frames.get_frame_texture(clip,frame) as AtlasTexture
 var anchor = Vector2(64,128)
 if clip == "Attack 1": anchor = Vector2(frame*128+76-texture.region.position.x,111)
 if clip == "Jump": anchor.y = JUMP_FEET[frame]
 var half = texture.get_size()*0.5
 offset = Vector2((half.x-anchor.x)*(-1 if flip_h else 1),half.y-anchor.y)
 position = feet
 if texture and (sampled_clip != clip or sampled_frame != frame):
  sampled_clip = clip
  sampled_frame = frame
  var size = texture.atlas.get_size()
  var region = texture.region
  material.set_shader_parameter("frame_bounds",Vector4(region.position.x/size.x,region.position.y/size.y,region.end.x/size.x,region.end.y/size.y))

func present(state: Dictionary):
 local_ticks += 1
 if state.animation != last_animation or state.attack_id != last_attack: age = 0
 else: age += 1
 if state.grounded and not last_grounded: landing_tick = local_ticks
 var clip = ["Idle","Run","Jump","Attack 1","Walk"][state.animation]
 if not sprite_frames.has_animation(clip): clip = "Idle"
 var index = 0
 match state.animation:
  3:
   var attack_age = clampi(24-roundi(state.attack*60),0,23)
   while index < ATTACK_ENDS.size()-1 and attack_age >= ATTACK_ENDS[index]: index += 1
  2:
   if age < 3 and state.vy < -4.5: index = age
   elif state.vy < -0.3: index = clampi(3+int((state.vy+4.8)/4.8*5),3,7)
   elif state.vy <= 1.0: index = 8
   else: index = clampi(9+int((state.vy-1.0)/6.5*4),9,12)
  _:
   var landed = local_ticks-landing_tick
   if state.animation == 0 and landing_tick >= 0 and landed < LANDING.size():
    clip = "Jump"
    index = LANDING[landed]
   else:
    index = int(age*sprite_frames.get_animation_speed(clip)/60.0)%sprite_frames.get_frame_count(clip)
 if not sprite_frames.has_animation(clip): clip = "Idle"
 show_frame(clip,index,Vector2(state.x,state.y),state.face)
 last_animation = state.animation
 last_attack = state.attack_id
 last_grounded = state.grounded
