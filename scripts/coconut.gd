extends RefCounted
# F7: COCONUT PALMS (নারিকেল গাছ) along all four beaches, all made by CODE.
#   6 different palm shapes (height 7.5-13.5 m, lean, S-bend, base bulge, 15-21 arched fronds, hanging nuts).
#   Every placed palm gets its own turn (leaning towards the sea), size, height and tint, so no two look the same.
#   Fronds = curved V-shaped ribbons with a feathery leaflet texture (alpha scissor). Trunk = ringed bark texture.
#   Textures are made in a background thread. Palms are drawn with MultiMesh in chunks of 250 m (far chunks are hidden).
#   Trunks have a thin collision (layer 1), so you cannot walk through them.

const FloraTex = preload("res://scripts/flora_tex.gd")
const TreeBanyan = preload("res://scripts/tree_banyan.gd")
const Flora = preload("res://scripts/flora.gd")

const VARIANTS := 6
const WORLD_SEED := 8008
const CHUNK := 250.0       # metres along the beach per MultiMesh chunk
const DEPTH_MIN := 3.0     # metres in from the map edge (the sand strip is 18 m wide)
const DEPTH_MAX := 14.0
const END_MARGIN := 22.0   # keep the 4 corners free
const VIS_END := 450.0     # chunks further away than this are not drawn

static var _task := -1
static var _img_f: Image
static var _img_t: Image


# ---------------------------------------------------------------------------- textures (background thread)
static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _seg(img: Image, a: Vector2, b: Vector2, c: Color, wide: bool) -> void:
	var steps := int(a.distance_to(b) / 1.2) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		var px := int(p.x)
		var py := int(p.y)
		_px(img, px, py, c)
		_px(img, px + 1, py, c)
		_px(img, px, py + 1, c)
		if wide:
			_px(img, px - 1, py, c)
			_px(img, px, py - 1, c)


# frond card 512 x 256: midrib along the middle, long leaflets hanging to both sides (forward leaning)
static func _frond_image() -> Image:
	var w := 512
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var base := Color(0.17, 0.40, 0.08)
	img.fill(Color(base.r, base.g, base.b, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2468
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 0.04
	nz.seed = 31
	var mid := 128.0
	_seg(img, Vector2(0.0, mid), Vector2(float(w) - 6.0, mid), Color(0.50, 0.44, 0.20, 1.0), true)
	var x := 20.0
	while x < float(w) - 12.0:
		var f := x / float(w)
		var prof := sin(PI * pow(f, 0.6))
		var ll := 22.0 + 100.0 * pow(maxf(prof, 0.0), 0.7)
		for sd: float in [-1.0, 1.0]:
			var shade := 0.8 + rng.randf() * 0.4 + nz.get_noise_2d(x, sd * 50.0) * 0.18
			var c0 := Color(base.r * shade, base.g * shade, base.b * shade, 1.0)
			var c1 := Color(minf(c0.r * 1.18, 1.0), minf(c0.g * 1.15, 1.0), c0.b * 1.05, 1.0)
			var j := rng.randf_range(-6.0, 6.0)
			var p0 := Vector2(x, mid + sd * 2.0)
			var p1 := Vector2(x + ll * (0.34 + j * 0.004), mid + sd * ll * 0.55)
			var p2 := Vector2(x + ll * (0.50 + j * 0.004), mid + sd * ll * 0.98)
			_seg(img, p0, p1, c0, true)
			_seg(img, p1, p2, c1, false)
		x += 7.0
	img.generate_mipmaps()
	return img


# trunk bark 128 x 256 (tiles in both directions): rings round the trunk + vertical fibres
static func _trunk_image() -> Image:
	var w := 128
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 1.0
	nz.seed = 55
	var base := Color(0.52, 0.44, 0.34)
	for y in h:
		var v := float(y) / float(h)
		var zz := v * 5.0
		for x in w:
			var a := TAU * float(x) / float(w)
			var cx := cos(a)
			var sx := sin(a)
			var n1 := lerpf(nz.get_noise_3d(cx * 2.2, sx * 2.2, zz), nz.get_noise_3d(cx * 2.2, sx * 2.2, zz - 5.0), v)
			var n2 := lerpf(nz.get_noise_3d(cx * 7.0, sx * 7.0, zz * 0.5), nz.get_noise_3d(cx * 7.0, sx * 7.0, zz * 0.5 - 2.5), v)
			var ring := absf(sin(v * PI * 16.0 + n1 * 0.9))
			var g := smoothstep(0.0, 0.3, ring)
			var k := (0.55 + 0.45 * g) * (0.9 + 0.2 * n2) * (0.85 + 0.3 * (n1 * 0.5 + 0.5))
			img.set_pixel(x, y, Color(base.r * k, base.g * k, base.b * k, 1.0))
	img.generate_mipmaps()
	return img


static func _work() -> void:
	_img_f = _frond_image()
	_img_t = _trunk_image()


# ---------------------------------------------------------------------------- one palm shape
static func _ball(st: SurfaceTool, base: int, c: Vector3, r: float, col: Color) -> int:
	var stacks := 4
	var sect := 6
	var ring := sect + 1
	st.set_color(col)
	for i in stacks + 1:
		var th := PI * float(i) / float(stacks)
		for s in ring:
			var a := TAU * float(s) / float(sect)
			st.set_uv(Vector2(float(s) / float(sect), 0.3 + 0.2 * float(i) / float(stacks)))
			st.add_vertex(c + Vector3(sin(th) * cos(a), cos(th), sin(th) * sin(a)) * r)
	for i in stacks:
		for s in sect:
			var a0 := base + i * ring + s
			var b0 := a0 + ring
			st.add_index(a0)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(b0 + 1)
	return base + (stacks + 1) * ring


# the tree leans towards local +X (placement turns it towards the sea). origin = ground point under the trunk.
static func _make_variant(seed_: int, trunk_mat: Material, frond_mat: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var height := rng.randf_range(7.5, 13.5)
	var lean := rng.randf_range(0.6, 3.4)
	var bend_z := rng.randf_range(-1.0, 1.0)
	var ph := rng.randf() * TAU
	var thick := rng.randf_range(0.85, 1.2)
	var n := 14
	var pts := PackedVector3Array()
	var rad := PackedFloat32Array()
	for i in n + 1:
		var t := float(i) / float(n)
		pts.append(Vector3(lean * t * t + 0.22 * sin(t * 5.0 + ph), height * t - 0.15,
				bend_z * t * t + 0.2 * sin(t * 4.0 + ph * 1.7)))
		rad.append(thick * lerpf(0.25, 0.14, t) * (1.0 + 0.9 * exp(-t * 14.0)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	var base := TreeBanyan._tube(st, 0, pts, rad, 10, 0.0, 0.0)
	var top := pts[n]
	for k in rng.randi_range(3, 7):   # hanging nuts under the crown
		var a := rng.randf() * TAU
		var c := top + Vector3(cos(a) * 0.3, -0.25 - rng.randf() * 0.2, sin(a) * 0.3)
		var col := Color(0.42, 0.62, 0.22) if rng.randf() < 0.7 else Color(0.5, 0.36, 0.2)
		base = _ball(st, base, c, rng.randf_range(0.13, 0.19), col)
	st.generate_normals()

	# fronds: young ones stand up in the middle, old ones arch out and droop
	var fs := SurfaceTool.new()
	fs.begin(Mesh.PRIMITIVE_TRIANGLES)
	fs.set_color(Color.WHITE)
	var fb := 0
	var nf := rng.randi_range(15, 21)
	var size_k := rng.randf_range(0.85, 1.2)
	var droop_k := rng.randf_range(0.8, 1.3)
	var yaw0 := rng.randf() * TAU
	var seg := 8
	for k in nf:
		var f := float(k) / float(nf - 1)
		var yaw := yaw0 + float(k) * 2.39996 + rng.randf_range(-0.15, 0.15)
		var dirh := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-dirh.z, 0.0, dirh.x)
		var phi := lerpf(1.3, 0.2, pow(f, 0.8)) + rng.randf_range(-0.12, 0.12)
		var bend := lerpf(0.5, 2.4, f) * droop_k + rng.randf_range(-0.2, 0.2)
		var flen := lerpf(2.4, 4.3, sqrt(f)) * size_k * rng.randf_range(0.9, 1.1)
		var half_w := 0.6 * lerpf(0.8, 1.0, f)
		var alpha := rng.randf_range(0.45, 0.7)   # V shape of the frond
		var nrm := (Vector3.UP * 0.8 + dirh * 0.25).normalized()
		var p := top + Vector3(0.0, 0.05, 0.0)
		var ds := flen / float(seg)
		for i in seg + 1:
			var u := float(i) / float(seg)
			var left := p + side * (half_w * cos(alpha)) - Vector3.UP * (half_w * sin(alpha))
			var right := p - side * (half_w * cos(alpha)) - Vector3.UP * (half_w * sin(alpha))
			fs.set_normal(nrm)
			fs.set_uv(Vector2(u, 0.0))
			fs.add_vertex(left)
			fs.set_normal(nrm)
			fs.set_uv(Vector2(u, 0.5))
			fs.add_vertex(p)
			fs.set_normal(nrm)
			fs.set_uv(Vector2(u, 1.0))
			fs.add_vertex(right)
			phi -= bend / float(seg)
			p += (dirh * cos(phi) + Vector3.UP * sin(phi)) * ds
		for i in seg:
			var a0 := fb + i * 3
			var b0 := a0 + 3
			for idx in [a0, a0 + 1, b0, a0 + 1, b0 + 1, b0, a0 + 1, a0 + 2, b0 + 1, a0 + 2, b0 + 2, b0 + 1]:
				fs.add_index(idx)
		fb += (seg + 1) * 3

	var mesh := ArrayMesh.new()
	st.commit(mesh)   # surface 0: trunk + nuts
	fs.commit(mesh)   # surface 1: fronds
	mesh.surface_set_material(0, trunk_mat)
	mesh.surface_set_material(1, frond_mat)
	return mesh


# ---------------------------------------------------------------------------- placing
# report = Callable(String) -> void   (we tell the overlay what happened)
static func place_all(world: Node, report: Callable) -> void:
	if _task == -1:
		_task = WorkerThreadPool.add_task(_work, false, "CoconutTex")
	report.call("coconut: making textures ...")
	var t := Timer.new()
	t.wait_time = 0.25
	world.add_child(t)
	t.timeout.connect(_poll.bind(t, world, report))
	t.start()


static func _poll(t: Timer, world: Node, report: Callable) -> void:
	if not WorkerThreadPool.is_task_completed(_task):
		return
	t.stop()
	t.queue_free()
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_place_now(world, report)


static func _place_now(world: Node, report: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	var ft := ImageTexture.create_from_image(_img_f)
	var tt := ImageTexture.create_from_image(_img_t)
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_texture = tt
	trunk_mat.vertex_color_use_as_albedo = true
	trunk_mat.roughness = 0.95
	trunk_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var frond_mat := StandardMaterial3D.new()
	frond_mat.albedo_texture = ft
	frond_mat.vertex_color_use_as_albedo = true
	frond_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	frond_mat.alpha_scissor_threshold = 0.25
	frond_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	frond_mat.roughness = 0.75
	frond_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var meshes: Array = []
	for v in VARIANTS:
		meshes.append(_make_variant(300 + v * 41, trunk_mat, frond_mat))

	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED
	var half: float = Flora.half
	var outs := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]   # east, west, south, north (sea side)
	var groups := {}   # chunk key -> Array of VARIANTS arrays of [Transform3D, Color, Vector3 (trunk collider), float (radius)]
	var total := 0
	for side in 4:
		var o: Vector2 = outs[side]
		var s := -half + END_MARGIN + rng.randf_range(0.0, 10.0)
		while s < half - END_MARGIN:
			var d := rng.randf_range(DEPTH_MIN, DEPTH_MAX)
			var x := o.x * (half - d) if side < 2 else s
			var z := o.y * (half - d) if side >= 2 else s
			s += rng.randf_range(2.5, 5.0) if rng.randf() < 0.25 else rng.randf_range(12.0, 32.0)
			if Flora.rail != null and Flora.rail.near_track(x, z):
				continue
			var gy := 0.0
			if world.has_method("height_at"):
				gy = float(world.call("height_at", x, z))
			var yaw := atan2(-o.y, o.x) + rng.randf_range(-0.7, 0.7)   # lean towards the sea
			var sc := rng.randf_range(0.8, 1.25)
			var sxz := sc * rng.randf_range(0.92, 1.08)
			var sy := sc * rng.randf_range(0.85, 1.2)
			var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sxz, sy, sxz)), Vector3(x, gy, z))
			var tint := Color(rng.randf_range(0.85, 1.05), rng.randf_range(0.9, 1.1), rng.randf_range(0.75, 1.0))
			var key := side * 100 + int((s + half) / CHUNK)
			if not groups.has(key):
				var lists: Array = []
				for v in VARIANTS:
					lists.append([])
				groups[key] = lists
			var var_i := rng.randi_range(0, VARIANTS - 1)
			(groups[key][var_i] as Array).append([xf, tint, Vector3(x, gy + 1.5, z), 0.3 * sxz])
			total += 1

	var holder := Node3D.new()
	holder.name = "CoconutPalms"
	for key in groups:
		var body := StaticBody3D.new()
		body.collision_layer = 1   # things: the player cannot walk through the trunks
		body.collision_mask = 0
		for v in VARIANTS:
			var items: Array = groups[key][v]
			if items.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = meshes[v]
			mm.instance_count = items.size()
			for i in items.size():
				var it: Array = items[i]
				mm.set_instance_transform(i, it[0])
				mm.set_instance_color(i, it[1])
				var cyl := CylinderShape3D.new()
				cyl.radius = float(it[3])
				cyl.height = 3.0
				var cs := CollisionShape3D.new()
				cs.shape = cyl
				cs.position = it[2]
				body.add_child(cs)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = VIS_END
			holder.add_child(mmi)
		holder.add_child(body)
	world.add_child(holder)
	report.call("coconut: %d palms on the beaches (%d chunks, %d shapes), %d ms" % [total, groups.size(), VARIANTS, Time.get_ticks_msec() - t0])
