extends RefCounted
# CONIFER (spruce / fir / pine) - made by CODE, very cheap for a weak phone (Infinix Hot 30i).
#   3 shapes, ~300 triangles each. 40 trees = about 12 000 triangles and only 6 DRAW CALLS in total
#   (one MultiMesh for the trunks + one for the needles, per shape). No shadows, no per-tree node.
#   Same seed = same forest. Switch + numbers: config.gd (CONIFERS) and the constants below.
#   Needs FloraTex (needle + bark textures), Flora.spot_ok (free places), TreeBanyan._tube (trunk tube).

const FloraTex = preload("res://scripts/flora_tex.gd")
const Flora = preload("res://scripts/flora.gd")
const TreeBanyan = preload("res://scripts/tree_banyan.gd")

const COUNT := 40
const MIN_DIST := 18.0        # metres between two conifers
const SPOT_MARGIN := 3.0      # free space round the trunk
const WORLD_SEED := 7707      # same seed = same places
const DESERT_MAX := 0.25      # no conifer where desert weight is higher
const SWAMP_MAX := 0.5
const LEAF_TINT := Color(1.55, 1.6, 1.25)   # needle colour (the needle picture is dark: raise = lighter / yellower)
const TRUNK_HIT := 0.4        # collision radius of a trunk (m)

# kind: 0 spruce (dense, drooping), 1 fir (tall, narrow), 2 pine (open crown, long bare trunk)
#       height, trunk radius, tiers, crown start (0..1 of height), card size low, card size top, droop
const KINDS := [
	[15.0, 0.34, 15, 0.16, 3.3, 0.9, 0.45],
	[17.0, 0.30, 18, 0.20, 2.5, 0.7, 0.30],
	[13.0, 0.30, 10, 0.42, 3.0, 1.2, 0.25],
]


# one card (bottom middle at pc, u = width direction, v = length direction). two triangles, vertex colour = light/dark.
static func _card(ls: SurfaceTool, base: int, pc: Vector3, u: Vector3, v: Vector3, sz: float, nrm: Vector3, col: Color) -> int:
	var bl := pc - u * sz * 0.5
	var br := pc + u * sz * 0.5
	var corners := [bl, br, br + v * sz, bl + v * sz]
	var uvs := [Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)]
	for i in 4:
		ls.set_color(col)
		ls.set_normal(nrm)
		ls.set_uv(uvs[i])
		ls.add_vertex(corners[i])
	for idx in [0, 1, 2, 0, 2, 3]:
		ls.add_index(base + idx)
	return base + 4


# returns [wood_mesh, leaf_mesh, height]
static func build_meshes(seed_: int, kind: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var P: Array = KINDS[kind]
	var H: float = P[0]
	var R0: float = P[1]
	var tiers: int = P[2]
	var y0: float = H * float(P[3])
	var szA: float = P[4]
	var szB: float = P[5]
	var droop0: float = P[6]
	var bx := rng.randf_range(-0.35, 0.35)
	var bz := rng.randf_range(-0.35, 0.35)

	# trunk: 6 sides, 7 rings, slightly bent, thin at the top
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tp := PackedVector3Array()
	var tr := PackedFloat32Array()
	for i in 8:
		var t := float(i) / 7.0
		tp.append(Vector3(bx * t * t, H * t - 0.2, bz * t * t))
		tr.append(maxf(R0 * (1.0 - 0.93 * pow(t, 0.8)) * (1.0 + 0.7 * exp(-t * 14.0)), 0.03))
	TreeBanyan._tube(st, 0, tp, tr, 6, 0.06, rng.randf() * TAU)
	st.generate_normals()
	st.generate_tangents()
	var wood_mesh := st.commit()

	# needles: whorls of branches, every branch = 2 crossed cards (no thin "edge-on" look from the side)
	var ls := SurfaceTool.new()
	ls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lb := 0
	var ang_off := rng.randf() * TAU
	for i in tiers:
		var t := float(i) / float(tiers - 1)
		var y := lerpf(y0, H * 0.96, t)
		var yt := y / H
		var cx := bx * yt * yt
		var cz := bz * yt * yt
		var nbr := int(round(lerpf(6.0, 3.0, t)))
		var droop := lerpf(droop0, -0.6, pow(t, 1.6))
		var tone := lerpf(0.72, 1.0, t)
		for k in nbr:
			var ang := ang_off + float(i) * 2.4 + TAU * float(k) / float(nbr) + rng.randf_range(-0.3, 0.3)
			var out := Vector3(cos(ang), 0.0, sin(ang))
			var pc := Vector3(cx, y, cz) + out * 0.12 + Vector3(0.0, rng.randf_range(-0.25, 0.25), 0.0)
			var v := (out - Vector3(0.0, droop + rng.randf_range(-0.12, 0.12), 0.0)).normalized()
			var u0 := v.cross(Vector3.UP).normalized()
			var sz := lerpf(szA, szB, pow(t, 0.8)) * rng.randf_range(0.85, 1.15)
			var nrm := (Vector3.UP * 0.75 + out * 0.45).normalized()
			var g := tone * rng.randf_range(0.88, 1.06)
			var col := Color(g, g, g * 0.97, 1.0)
			var roll := rng.randf_range(-0.4, 0.4)
			lb = _card(ls, lb, pc, u0.rotated(v, roll), v, sz, nrm, col)
			lb = _card(ls, lb, pc, u0.rotated(v, roll + 1.3), v, sz * 0.9, nrm, col)
	# top leader: two crossed upright cards
	var topc := Vector3(bx, H * 0.94, bz)
	for r in 2:
		lb = _card(ls, lb, topc, Vector3.RIGHT.rotated(Vector3.UP, float(r) * 1.57), Vector3.UP, 1.4, Vector3.UP, Color(1, 1, 1, 1))
	return [wood_mesh, ls.commit(), H]


static func _leaf_mat() -> StandardMaterial3D:
	var m := FloraTex.leaf_material("needle")
	m.vertex_color_use_as_albedo = true
	m.albedo_color = LEAF_TINT
	m.backlight_enabled = false      # cheaper
	return m


# ---------------------------------------------------------------------------- placement
static var spots_taken: Array = []   # Vector2 list (x, z): the big shade trees keep away from these
static var wait_banyans := false   # main.gd sets this to Cfg.NEW_BANYANS (we wait for them, then keep away)


static func place_all(world: Node, report: Callable) -> void:
	FloraTex.start()
	report.call("conifer: waiting for textures ...")
	var t := Timer.new()
	t.wait_time = 0.25
	world.add_child(t)
	t.timeout.connect(_poll.bind(t, world, report))
	t.start()


static func _poll(t: Timer, world: Node, report: Callable) -> void:
	if FloraTex._task != -1:
		if not WorkerThreadPool.is_task_completed(FloraTex._task):
			return
		WorkerThreadPool.wait_for_task_completion(FloraTex._task)
		FloraTex._finish()
	if not FloraTex.tex.has("bark"):
		return
	if wait_banyans and world.get_node_or_null("Banyans") == null:
		return   # wait for the banyans so we do not grow into them
	t.queue_free()
	_place_now(world, report)


static func _place_now(world: Node, report: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED
	var lim: float = Flora.half - 40.0

	# existing banyans (keep 12 m away)
	var avoid: Array = []
	var bh := world.get_node_or_null("Banyans")
	if bh != null:
		for c in bh.get_children():
			avoid.append(Vector2((c as Node3D).position.x, (c as Node3D).position.z))

	# 1. free places
	var spots: Array = []
	var tries := 0
	while spots.size() < COUNT and tries < 6000:
		tries += 1
		var x := rng.randf_range(-lim, lim)
		var z := rng.randf_range(-lim, lim)
		var w: Array = Flora.biome_w(x, z)
		if float(w[3]) > DESERT_MAX or float(w[4]) > SWAMP_MAX:
			continue
		if not Flora.spot_ok(x, z, SPOT_MARGIN):
			continue
		var p := Vector2(x, z)
		var bad := false
		for s in spots:
			if Vector2((s as Vector4).x, (s as Vector4).y).distance_to(p) < MIN_DIST:
				bad = true
				break
		if not bad:
			for a in avoid:
				if (a as Vector2).distance_to(p) < 12.0:
					bad = true
					break
		if bad:
			continue
		spots.append(Vector4(x, z, rng.randf_range(0.85, 1.2), float(rng.randi_range(0, 2))))

	spots_taken = []
	for s in spots:
		spots_taken.append(Vector2((s as Vector4).x, (s as Vector4).y))

	# 2. 3 shapes -> one MultiMesh for trunks + one for needles per shape (6 draw calls)
	var holder := Node3D.new()
	holder.name = "Conifers"
	var bark := FloraTex.bark_material()
	var leaf := _leaf_mat()
	var body := StaticBody3D.new()     # trunks: one body, one small cylinder per tree
	body.name = "ConiferTrunks"
	body.collision_layer = 1
	body.collision_mask = 0
	holder.add_child(body)
	var cyl := CylinderShape3D.new()
	cyl.radius = TRUNK_HIT
	cyl.height = 5.0
	for kind in 3:
		var list: Array = []
		for s in spots:
			if int((s as Vector4).w) == kind:
				list.append(s)
		if list.is_empty():
			continue
		var m := build_meshes(300 + kind * 41, kind)
		for pair in [[m[0], bark, "Wood"], [m[1], leaf, "Needles"]]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = pair[0]
			mm.instance_count = list.size()
			for i in list.size():
				var sv: Vector4 = list[i]
				var gy := 0.0
				if world.has_method("height_at"):
					gy = float(world.call("height_at", sv.x, sv.y))
				var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sv.z)
				mm.set_instance_transform(i, Transform3D(b, Vector3(sv.x, gy - 0.05, sv.y)))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s%d" % [pair[2], kind]
			mmi.multimesh = mm
			mmi.material_override = pair[1]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.extra_cull_margin = 8.0
			holder.add_child(mmi)
		for i in list.size():
			var sv: Vector4 = list[i]
			var gy := 0.0
			if world.has_method("height_at"):
				gy = float(world.call("height_at", sv.x, sv.y))
			var cs := CollisionShape3D.new()
			cs.shape = cyl
			cs.position = Vector3(sv.x, gy + 2.5, sv.y)
			body.add_child(cs)
	world.add_child(holder)
	report.call("conifer: %d/%d trees, 6 draw calls, %d tries, %d ms" % [spots.size(), COUNT, tries, Time.get_ticks_msec() - t0])
