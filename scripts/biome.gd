extends RefCounted
# Biomes of the 1000 m map (V25). ONE formula, used by the ground shader (GPU: soil colour) and the streaming of trees / rocks (CPU).
# weights(x, z) = [farm, forest, rock, desert, swamp] (sum = 1).  North = -z.
#   farm   = the old 400 m map in the middle (loam)
#   forest = north-west, rock = north-east, desert = south-east, swamp = south-west  (borders are wavy and blend softly)

# F17: the ground of F11c (real grass + dirt pictures with normal maps), 2 scales each so the tiling does not show;
# biome = tint on top. Changes against F11c: no vertex colour (nothing is dug any more), safe random cell, fine bumps fade out far away.
const GROUND_FILES := {
	"t_grass": "res://assets/tex/grass_albedo.png", "t_dirt": "res://assets/tex/dirt_albedo.png",
	"n_grass": "res://assets/tex/grass_normal.png", "n_dirt": "res://assets/tex/dirt_normal.png",
}

const GROUND_SHADER := """
shader_type spatial;
varying vec3 wpos;
uniform sampler2D t_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D t_dirt : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D n_grass : filter_linear_mipmap, repeat_enable;
uniform sampler2D n_dirt : filter_linear_mipmap, repeat_enable;
uniform float bright = 1.0;
vec2 warp(vec2 p) {
	return vec2(p.x + sin(p.x * 0.011 + p.y * 0.007) * 60.0 + sin(p.y * 0.017 - p.x * 0.005) * 40.0,
		p.y + sin(p.y * 0.012 - p.x * 0.008) * 60.0 + sin(p.x * 0.019 + p.y * 0.006) * 40.0);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// v1.0 cheap ground: 2 picture reads only, no normal map, no hash noise (= no shimmer); far = blurrier pictures
	vec2 p = wpos.xz;
	vec2 w = warp(p);
	vec2 q = (w - p) * 0.25 + p;
	float d = max(abs(q.x), abs(q.y));
	float farm = 1.0 - smoothstep(225.0, 285.0, d);
	float east = smoothstep(-70.0, 70.0, w.x);
	float south = smoothstep(-70.0, 70.0, w.y);
	float o = 1.0 - farm;
	float fo = o * (1.0 - east) * (1.0 - south);
	float ro = o * east * (1.0 - south);
	float de = o * east * south;
	float sw = o * (1.0 - east) * south;
	float big = 0.5 + 0.5 * sin(p.x * 0.045) * sin(p.y * 0.04);
	float dist = length(VERTEX);
	float far_t = smoothstep(30.0, 110.0, dist);
	float bias = far_t * 4.0;   // far = smaller / blurrier picture = no flicker and nothing to draw
	vec3 gt = texture(t_grass, p / 3.5, bias).rgb * (0.82 + 0.36 * big);
	vec3 dt = texture(t_dirt, p / 3.0, bias).rgb * (0.85 + 0.3 * big);
	float gl = dot(gt, vec3(0.333));
	gt = mix(vec3(gl), gt, 0.7) * vec3(1.0, 0.97, 0.85);   // less green
	float dl = dot(dt, vec3(0.333));
	float pat = smoothstep(0.80, 0.93, 0.5 + 0.5 * sin(p.x * 0.09 + sin(p.y * 0.05) * 2.0) * sin(p.y * 0.083 + sin(p.x * 0.04)));
	vec3 c_farm = mix(gt, dt, 0.15);
	vec3 c_for = gt * vec3(0.55, 0.66, 0.5);
	vec3 c_rock = mix(dt, vec3(dl), 0.7) * 1.5;
	vec3 c_des = vec3(0.82, 0.69, 0.43) * (0.55 + dl * 1.5);
	vec3 c_sw = mix(gt, dt, 0.3) * vec3(0.6, 0.62, 0.48);
	vec3 col = c_farm * farm + c_for * fo + c_rock * ro + c_des * de + c_sw * sw;
	float grassy = farm + fo + sw;
	col = mix(col, dt * 0.9, pat * 0.5 * grassy);
	ALBEDO = col * bright;
	ROUGHNESS = 1.0;
}
"""


# FALLBACK ground (used only when the F11c ground pictures cannot be loaded): no image files, grass + soil made by noise in the shader.
# Open field = bright green grass, forest = dark lush grass + humus + a dirt trail, rock = stony, desert = sand, swamp = wet dark green.
const GRASS_SHADER := """
shader_type spatial;
varying vec3 wpos;
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
vec2 warp(vec2 p) {
	return vec2(p.x + sin(p.x * 0.011 + p.y * 0.007) * 60.0 + sin(p.y * 0.017 - p.x * 0.005) * 40.0,
		p.y + sin(p.y * 0.012 - p.x * 0.008) * 60.0 + sin(p.x * 0.019 + p.y * 0.006) * 40.0);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz;
	vec2 w = warp(p);
	vec2 q = (w - p) * 0.25 + p;
	float d = max(abs(q.x), abs(q.y));
	float farm = 1.0 - smoothstep(225.0, 285.0, d);
	float east = smoothstep(-70.0, 70.0, w.x);
	float south = smoothstep(-70.0, 70.0, w.y);
	float o = 1.0 - farm;
	float fo = o * (1.0 - east) * (1.0 - south);
	float ro = o * east * (1.0 - south);
	float de = o * east * south;
	float sw = o * (1.0 - east) * south;

	// fine detail fades with distance (no shimmering far away)
	float dist = length(VERTEX);
	float fd = 1.0 - smoothstep(18.0, 75.0, dist);

	float n_big = vn(p * 0.02) * 0.65 + vn(p * 0.055 + 3.1) * 0.35;
	float n_mid = vn(p * 0.45 + 9.7);
	float blade = vn(p * 5.0 + 2.0) * 0.5 + vn(p * 13.0 + 7.0) * 0.5;
	float fine = mix(0.5, blade, fd);

	// ---- grass colours of each biome (dark = in the shade of the clumps, light = tips in the sun)
	vec3 g_dark = lin(vec3(0.17, 0.30, 0.07)) * farm + lin(vec3(0.07, 0.22, 0.05)) * fo + lin(vec3(0.24, 0.32, 0.12)) * ro
		+ lin(vec3(0.48, 0.42, 0.20)) * de + lin(vec3(0.10, 0.24, 0.07)) * sw;
	vec3 g_light = lin(vec3(0.36, 0.48, 0.14)) * farm + lin(vec3(0.20, 0.36, 0.09)) * fo + lin(vec3(0.40, 0.48, 0.20)) * ro
		+ lin(vec3(0.68, 0.60, 0.32)) * de + lin(vec3(0.24, 0.40, 0.13)) * sw;
	float t = clamp(n_mid * 0.45 + fine * 0.65 + (n_big - 0.5) * 0.5, 0.0, 1.0);
	vec3 grass = mix(g_dark, g_light, t);
	// slightly dry / yellow patches (not in the forest and swamp)
	float dry = smoothstep(0.62, 0.88, vn(p * 0.035 + 21.0)) * (1.0 - fo) * (1.0 - sw) * 0.45;
	grass = mix(grass, lin(vec3(0.55, 0.52, 0.22)), dry);

	// ---- soil colours: loam, dark humus, grey stony, sand, wet mud
	vec3 s_col = lin(vec3(0.33, 0.23, 0.14)) * farm + lin(vec3(0.20, 0.14, 0.08)) * fo + lin(vec3(0.45, 0.42, 0.38)) * ro
		+ lin(vec3(0.84, 0.74, 0.52)) * de + lin(vec3(0.22, 0.17, 0.10)) * sw;
	s_col *= 0.80 + 0.40 * mix(0.5, vn(p * 3.0 + 40.0) * 0.6 + vn(p * 9.0) * 0.4, fd);

	// ---- where the soil shows through the grass
	float thr = 0.74 * farm + 0.68 * fo + 0.52 * ro + 0.16 * de + 0.72 * sw;
	float dn = vn(p * 0.07 + 5.0) * 0.55 + vn(p * 0.23 + 11.0) * 0.45 + (fine - 0.5) * 0.30 * fd;
	float dirt = smoothstep(thr, thr + 0.09, dn);

	// ---- a dirt trail winding through the forest (north-west)
	float tx = -240.0 + sin(p.y * 0.018) * 32.0 + sin(p.y * 0.051 + 1.3) * 7.0;
	float tw = 1.5 + 0.9 * vn(vec2(p.y * 0.08, 3.0));
	float edge = (fine - 0.5) * 1.1;
	float trail = (1.0 - smoothstep(tw * 0.55, tw + 0.9, abs(p.x - tx) + edge)) * smoothstep(0.5, 0.9, fo);
	trail *= smoothstep(-470.0, -420.0, p.y) * (1.0 - smoothstep(-60.0, -20.0, p.y));
	dirt = max(dirt, trail);
	vec3 col = mix(grass, s_col, dirt);

	// wet swamp is darker, soft light / shade patches over everything
	col *= 1.0 - 0.22 * sw * smoothstep(0.45, 0.8, vn(p * 0.09 + 60.0));
	col *= 0.84 + 0.32 * mix(0.5, vn(p * 1.3 + 80.0), fd * 0.8 + 0.2);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}
"""


static var _tex_cache := {}
static var via_import := 0
static var via_file := 0
static var report := "ground: -"


# image -> texture WITH mipmaps (no shimmering far away); cached. Used for the ground AND the mountain.
# 1) the imported resource  2) if the editor has not imported the file yet: read the plain image file.
static func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var img: Image = null
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			img = (t as Texture2D).get_image()
			if img != null and not img.is_empty():
				via_import += 1
	if img == null or img.is_empty():
		img = Image.load_from_file(path)
		if img != null and not img.is_empty():
			via_file += 1
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	var it := ImageTexture.create_from_image(img)
	_tex_cache[path] = it
	return it


# loads the 4 ground pictures; returns {} when any is missing (then the picture-free fallback shader is used, never a white ground)
static func load_ground_textures() -> Dictionary:
	var out := {}
	via_import = 0
	via_file = 0
	for k in GROUND_FILES:
		var t := tex(GROUND_FILES[k])
		if t != null:
			out[k] = t
	report = "ground: %d/%d pictures (import %d, file %d)%s" % [out.size(), GROUND_FILES.size(), via_import, via_file,
		"" if out.size() == GROUND_FILES.size() else "  -> FALLBACK shader"]
	if out.size() != GROUND_FILES.size():
		return {}
	return out


static func warp(x: float, z: float) -> Vector2:
	return Vector2(x + sin(x * 0.011 + z * 0.007) * 60.0 + sin(z * 0.017 - x * 0.005) * 40.0,
		z + sin(z * 0.012 - x * 0.008) * 60.0 + sin(x * 0.019 + z * 0.006) * 40.0)


static func weights(x: float, z: float) -> Array:
	var w := warp(x, z)
	var qx := (w.x - x) * 0.25 + x
	var qz := (w.y - z) * 0.25 + z
	var d := maxf(absf(qx), absf(qz))
	var farm := 1.0 - smoothstep(225.0, 285.0, d)
	var east := smoothstep(-70.0, 70.0, w.x)
	var south := smoothstep(-70.0, 70.0, w.y)
	var o := 1.0 - farm
	return [farm, o * (1.0 - east) * (1.0 - south), o * east * (1.0 - south), o * east * south, o * (1.0 - east) * south]
