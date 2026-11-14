extends Node3D
# F17: F11c grass + dirt pictures on the mountain, NO shimmer (see SHADER). F6: ONE big real-looking mountain in a free place of the map, all made by CODE.
#   Foot radius about 110 m (wavy outline, not a round cone), peak 58 m. Grass with soft hills and bumps on the lower slopes,
#   bare dirt on the steeper parts, grey layered rock on crags and near the top. Climbable (most slopes under 40 degrees).
#   height_at(x, z) is used by fx_map.height_at (tractor, camera). Collision = trimesh on layer 2 (like the ground), group "mountain".
#   Same seed = same mountain.

const Biome = preload("res://scripts/biome.gd")
const Cfg = preload("res://scripts/config.gd")
const R := 110.0
const R_MAX := R * 1.25   # the wavy outline never goes further than this
const PEAK := 58.0
const CELL := 2.5
const SEED := 4242

var cx := 0.0
var cz := 0.0
var _n_out := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _n_hill := FastNoiseLite.new()
var _n_bump := FastNoiseLite.new()
var info := ""

const SHADER := """
shader_type spatial;
render_mode cull_back;
// F17: the F11c grass + dirt pictures. Why the old mountain shimmered (flickered):
//  1) its pictures had NO mipmaps (plain load()) - now Biome.tex() makes mipmaps;
//  2) texture() calls were inside an if() - there the GPU has no valid derivative = noisy pixels at the borders. Now every picture is
//     read OUTSIDE any if(), and the result is chosen with mix();
//  3) a fast sin() of the picture value made very fine stripes - now only slow layers;
//  4) far away only the average colour of each picture is used (fine detail fades out), so nothing can shimmer.
uniform sampler2D t_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float peak = 58.0;
uniform float bright = 1.15;
varying vec3 wpos;
varying vec3 wnrm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	vec3 n = normalize(wnrm);
	float slope = 1.0 - n.y;
	vec2 p = wpos.xz;
	float dist = length(VERTEX);
	float fd = 1.0 - smoothstep(70.0, 280.0, dist);    // fine detail: only near
	float md = 1.0 - smoothstep(250.0, 700.0, dist);   // medium detail: fades far away
	vec3 avg_g = textureLod(t_grass, vec2(0.5), 20.0).rgb;   // average colour of each picture (the smallest mipmap)
	vec3 avg_d = textureLod(t_dirt, vec2(0.5), 20.0).rgb;
	// ---- grass: the same 2 scales as the ground, so the foot of the mountain joins the field
	float low = texture(t_grass, p * 0.006).g;
	vec3 g1 = mix(avg_g, texture(t_grass, p / 3.5).rgb, fd);
	vec3 g2 = mix(avg_g, texture(t_grass, p / 19.0 + vec2(0.37, 0.61)).rgb, md);
	vec3 grass = mix(g1, g2, 0.35) * mix(0.78, 1.18, low) * vec3(0.95, 1.04, 0.82);
	float n1 = texture(t_dirt, p * 0.012).g;
	float rock_w = smoothstep(0.16, 0.30, slope + (n1 - 0.5) * 0.16);
	rock_w = max(rock_w, smoothstep(peak * 0.62, peak * 0.9, wpos.y + (n1 - 0.5) * 8.0) * 0.9);
	float dirt_w = smoothstep(0.07, 0.16, slope + (low - 0.5) * 0.10) * 0.6 * (1.0 - rock_w);
	// ---- dirt / rock: 3-sided projection (no stretching on steep slopes), always read (never inside an if)
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 dirt = texture(t_dirt, wpos.zy * 0.17).rgb * bw.x + texture(t_dirt, wpos.xz * 0.17).rgb * bw.y + texture(t_dirt, wpos.xy * 0.17).rgb * bw.z;
	dirt = mix(avg_d, dirt, fd);
	float gray = dot(dirt, vec3(0.333));
	vec3 rock = mix(dirt, vec3(gray), 0.65) * vec3(0.78, 0.76, 0.74);
	rock *= 1.0 + 0.10 * sin(wpos.y * 0.9 + low * 5.0) * md;   // soft layers of the rock (slow, so no shimmer)
	vec3 col = mix(grass, dirt * vec3(1.0, 0.92, 0.8), dirt_w);
	col = mix(col, rock, rock_w);
	ALBEDO = col * bright;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""


func _init() -> void:
	_n_out.seed = SEED
	_n_out.frequency = 1.0
	_n_out.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_ridge.seed = SEED + 1
	_n_ridge.frequency = 0.012
	_n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_ridge.fractal_octaves = 3
	_n_hill.seed = SEED + 2
	_n_hill.frequency = 0.03
	_n_hill.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_bump.seed = SEED + 3
	_n_bump.frequency = 0.12
	_n_bump.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH


func footprint() -> Rect2:
	return Rect2(cx - R_MAX, cz - R_MAX, R_MAX * 2.0, R_MAX * 2.0)


func inside(x: float, z: float) -> bool:
	return absf(x - cx) < R_MAX and absf(z - cz) < R_MAX


func height_at(x: float, z: float) -> float:
	var dx := x - cx
	var dz := z - cz
	var d := sqrt(dx * dx + dz * dz)
	if d >= R_MAX:
		return 0.0
	var a := atan2(dz, dx)
	var rr := R * (1.0 + 0.2 * _n_out.get_noise_2d(cos(a) * 2.0, sin(a) * 2.0))
	var t := 1.0 - d / rr
	if t <= 0.0:
		return 0.0
	var ridge := 1.0 - absf(_n_ridge.get_noise_2d(x, z))
	var h := PEAK * pow(t, 1.45)
	h += 10.0 * (ridge * ridge - 0.45) * pow(t, 1.2)               # crags and ridges
	h += 3.5 * (_n_hill.get_noise_2d(x, z) * 0.5 + 0.5) * smoothstep(0.0, 0.3, t)   # soft hills
	h += 0.8 * (_n_bump.get_noise_2d(x, z) * 0.5 + 0.5) * smoothstep(0.0, 0.12, t)  # small bumps in the grass
	return maxf(h, 0.0)


func build() -> void:
	var t0 := Time.get_ticks_msec()
	var n := int(ceil(R_MAX * 2.0 / CELL))
	var nv := n + 1
	var x0 := cx - R_MAX
	var z0 := cz - R_MAX
	var hs := PackedFloat32Array()
	hs.resize(nv * nv)
	for j in nv:
		for i in nv:
			hs[j * nv + i] = height_at(x0 + float(i) * CELL, z0 + float(j) * CELL)
	var vmap := PackedInt32Array()
	vmap.resize(nv * nv)
	vmap.fill(-1)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in n:
		for i in n:
			var ia := j * nv + i
			var ib := ia + 1
			var ic := ia + nv
			var id := ic + 1
			if hs[ia] < 0.005 and hs[ib] < 0.005 and hs[ic] < 0.005 and hs[id] < 0.005:
				continue
			for q in [ia, ib, ic, id]:
				if vmap[q] < 0:
					var qi: int = q % nv
					var qj: int = q / nv
					var hl: float = hs[qj * nv + maxi(qi - 1, 0)]
					var hr: float = hs[qj * nv + mini(qi + 1, nv - 1)]
					var hu: float = hs[maxi(qj - 1, 0) * nv + qi]
					var hd: float = hs[mini(qj + 1, nv - 1) * nv + qi]
					vmap[q] = verts.size()
					verts.append(Vector3(x0 + float(qi) * CELL, hs[q] + 0.03, z0 + float(qj) * CELL))
					norms.append(Vector3(hl - hr, 2.0 * CELL, hu - hd).normalized())
			var a := vmap[ia]
			var b := vmap[ib]
			var c := vmap[ic]
			var d := vmap[id]
			# clockwise seen from above = front face up
			idx.append(a)
			idx.append(b)
			idx.append(c)
			idx.append(b)
			idx.append(d)
			idx.append(c)
	if verts.is_empty():
		info = "mountain: EMPTY"
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var tg := Biome.tex("res://assets/tex/grass_albedo.png")   # with mipmaps (made in code)
	var td := Biome.tex("res://assets/tex/dirt_albedo.png")
	if tg != null:
		mat.set_shader_parameter("t_grass", tg)
	if td != null:
		mat.set_shader_parameter("t_dirt", td)
	mat.set_shader_parameter("bright", Cfg.MOUNTAIN_BRIGHT)
	mat.set_shader_parameter("peak", PEAK)
	var mi := MeshInstance3D.new()
	mi.name = "MountainMesh"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# collision: the same triangles
	var faces := PackedVector3Array()
	faces.resize(idx.size())
	for k in idx.size():
		faces[k] = verts[idx[k]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var body := StaticBody3D.new()
	body.name = "MountainBody"
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_to_group("mountain")
	body.add_child(cs)
	add_child(body)
	info = "mountain: OK at x %d z %d, peak %d m, %d tris, %d ms" % [int(cx), int(cz), int(PEAK), idx.size() / 3, Time.get_ticks_msec() - t0]

