shader_type canvas_item;
render_mode unshaded;
// Emulate 8x nearest replication followed by linear sampling, without an 8x image.
// Atlas bounds prevent another animation cell leaking into an edge sample.
uniform vec4 frame_bounds = vec4(0.0, 0.0, 1.0, 1.0);
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
 vec2 p = UV / TEXTURE_PIXEL_SIZE - vec2(0.5);
 vec2 blend = clamp((fract(p) - vec2(0.5)) * 8.0 + vec2(0.5), vec2(0.0), vec2(1.0));
 vec2 uv = (floor(p) + vec2(0.5) + blend) * TEXTURE_PIXEL_SIZE;
 uv = clamp(uv, frame_bounds.xy + TEXTURE_PIXEL_SIZE * 0.5, frame_bounds.zw - TEXTURE_PIXEL_SIZE * 0.5);
 COLOR = texture(TEXTURE, uv) * tint;
}
