extends RefCounted
# FOREST PLAN F4: banyan (বট) generator, all made by CODE (no model files).
#   TreeBanyan.build(seed, scale) -> Node3D  (origin = ground point under the trunk)
#     child "Wood"   : trunk (bent, with root flare) + 3-5 thick limbs + hanging aerial roots (ঝুরি)
#     child "Leaves" : wide canopy of leaf cards (alpha scissor, F3 "broad" card)
#   Same seed = same tree (own RandomNumberGenerator, no global randf).
#   F5: place_all() puts 30 of them in the world (4 shapes x random turn / size, leaves in MultiMesh). F6 adds collision + cutting.
#   Needs the F3 textures: use make_test_tree(), it waits for them.

const FloraTex = preload("res://scripts/flora_tex.gd")
const Flora = preload("res://scripts/flora.gd")


# ---------------------------------------------------------------------------- tube (trunk, limb, root)
# sweeps a ring along a path. radii = one radius per point. lobe = rib strength around the trunk (0 = round).
# returns the new vertex base (so many tubes can go into one mesh).
static func _tube(st: SurfaceTool, base: int, pts: PackedVector3Array, radii: PackedFloat32Array,
		sides: int, lobe: float, phase: float) -> int:
	var n := pts.size()
	var ring := sides + 1
	var t0 := (pts[1] - pts[0]).normalized()
	var ref := Vector3.RIGHT if absf(t0.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var nrm := (ref - t0 * ref.dot(t0)).normalized()
	var v := 0.0
	for i in n:
		var p := pts[i]
		var tg := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		nrm = (nrm - tg * nrm.dot(tg)).normalized()   # parallel transport: no twisting
		var bn := tg.cross(nrm)
		var r := maxf(radii[i], 0.02)
		if i > 0:
			v += pts[i].distance_to(pts[i - 1]) / (2.8 * TAU * r)   # bark tile keeps its shape
		for s in ring:
			var a := TAU * float(s) / float(sides)
			var rr := r * (1.0 + lobe * sin(5.0 * a + phase))
			st.set_uv(Vector2(float(s) / float(sides), v))
			st.add_vertex(p + (nrm * cos(a) + bn * sin(a)) * rr)
	for i in n - 1:
		for s in sides:
			var a0 := base + i * ring + s
			var b0 := a0 + ring
			st.add_index(a0)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(b0 + 1)
	return base + n * ring


# one leaf card: bottom middle at pc, u = sideways, v = along the twig
static func _card(ls: SurfaceTool, base: int, pc: Vector3, u: Vector3, v: Vector3, sz: float, nrm: Vector3) -> int:
	var bl := pc - u * sz * 0.5
	var br := pc + u * sz * 0.5
	var corners := [bl, br, br + v * sz, bl + v * sz]
	var uvs := [Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)]
	for i in 4:
		ls.set_normal(nrm)
		ls.set_uv(uvs[i])
		ls.add_vertex(corners[i])
	for idx in [0, 1, 2, 0, 2, 3]:
		ls.add_index(base + idx)
	return base + 4


# ---------------------------------------------------------------------------- the tree
static func build(seed_: int, sc: float = 1.0) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var root := Node3D.new()
	root.name = "Banyan"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0

	# trunk: bent, thick root flare at the foot, ribs (buttresses)
	var th := 4.5 * sc
	var bx := rng.randf_range(-0.9, 0.9) * sc
	var bz := rng.randf_range(-0.9, 0.9) * sc
	var ph := rng.randf() * TAU
	var tp := PackedVector3Array()
	var tr := PackedFloat32Array()
	for i in 13:
		var t := float(i) / 12.0
		tp.append(Vector3(bx * t * t + 0.12 * sc * sin(t * 7.0 + ph), th * t - 0.3 * sc,
				bz * t * t + 0.12 * sc * cos(t * 6.0 + ph)))
		tr.append(sc * lerpf(0.62, 0.40, t) * (1.0 + 1.2 * exp(-t * 10.0)))
	base = _tube(st, base, tp, tr, 16, 0.12, ph)

	# 3 - 5 thick limbs going out and up, bending
	var limbs: Array = []
	var count := rng.randi_range(3, 5)
	var a0 := rng.randf() * TAU
	for L in count:
		var ang := a0 + TAU * float(L) / float(count) + rng.randf_range(-0.35, 0.35)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var start := tp[int(rng.randf_range(0.72, 0.98) * 12.0)]
		var ll := rng.randf_range(6.5, 9.5) * sc
		var rise := rng.randf_range(2.2, 3.8) * sc
		var wob := rng.randf() * TAU
		var lp := PackedVector3Array()
		var lr := PackedFloat32Array()
		for k in 9:
			var s := float(k) / 8.0
			var p := start + dir * (ll * s) + Vector3(0.0, rise * sin(s * PI * 0.65), 0.0)
			p += side * (0.9 * sc * sin(s * 4.0 + wob) * s)
			lp.append(p)
			lr.append(sc * lerpf(0.42, 0.12, s))
		base = _tube(st, base, lp, lr, 8, 0.0, 0.0)
		limbs.append(lp)

	# aerial roots (ঝুরি): thin ones hang to the ground, the last one of each limb is a thick pillar
	var nroots := 0
	for lm in limbs:
		var lpp: PackedVector3Array = lm
		var m := rng.randi_range(3, 4)
		for j in m + 1:
			var thick := (j == m)
			var s := rng.randf_range(0.6, 0.75) if thick else rng.randf_range(0.3, 0.95)
			var fi := s * 8.0
			var i0 := mini(int(fi), 7)
			var top := lpp[i0].lerp(lpp[i0 + 1], fi - float(i0))
			var dx := rng.randf_range(-0.7, 0.7) * sc
			var dz := rng.randf_range(-0.7, 0.7) * sc
			var r_top := (0.12 if thick else rng.randf_range(0.035, 0.055)) * sc
			var r_bot := (0.28 if thick else rng.randf_range(0.05, 0.08)) * sc
			var rp := PackedVector3Array()
			var rr := PackedFloat32Array()
			for k in 8:
				var q := float(k) / 7.0
				var sway := sin(q * PI * 1.5 + float(j)) * 0.22 * sc * (1.0 - q)
				rp.append(Vector3(top.x + dx * q + sway, lerpf(top.y, -0.15 * sc, q), top.z + dz * q + sway * 0.7))
				rr.append(lerpf(r_top, r_bot, q * q))
			base = _tube(st, base, rp, rr, 5, 0.0, 0.0)
			nroots += 1

	st.generate_normals()
	st.generate_tangents()
	var wood := MeshInstance3D.new()
	wood.name = "Wood"
	wood.mesh = st.commit()
	wood.material_override = FloraTex.bark_material()
	root.add_child(wood)

	# canopy: leaf cards that grow outward from the limb tips and along the limbs
	var ls := SurfaceTool.new()
	ls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lb := 0
	var cards := 0
	for lm in limbs:
		var lpp: PackedVector3Array = lm
		for c in 48:
			var pc := lpp[rng.randi_range(3, 8)] + Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(-0.8, 1.0),
					rng.randf_range(-1.6, 1.6)) * sc
			var out := Vector3(pc.x, 0.0, pc.z)
			out = out.normalized() if out.length() > 0.1 else Vector3.RIGHT
			var v := (out * rng.randf_range(0.2, 1.0) + Vector3(0.0, rng.randf_range(0.3, 1.0), 0.0)
					+ Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))).normalized()
			var u := v.cross(Vector3.UP)
			u = u.normalized() if u.length() > 0.1 else Vector3.RIGHT
			u = u.rotated(v, rng.randf_range(-0.8, 0.8))
			var nrm := (Vector3.UP * 0.7 + out * 0.5).normalized()   # soft light from above
			lb = _card(ls, lb, pc, u, v, rng.randf_range(2.0, 3.0) * sc, nrm)
			cards += 1
	var leaves := MeshInstance3D.new()
	leaves.name = "Leaves"
	leaves.mesh = ls.commit()
	leaves.material_override = FloraTex.leaf_material("broad")
	root.add_child(leaves)
	root.set_meta("banyan_info", "limbs %d, roots %d, cards %d" % [count, nroots, cards])
	return root


# ---------------------------------------------------------------------------- test tree at the spawn
# report = Callable(String) -> void   (we tell the overlay what happened)
static func make_test_tree(world: Node, pos: Vector3, report: Callable) -> void:
	FloraTex.start()
	report.call("banyan: waiting for textures ...")
	var t := Timer.new()
	t.wait_time = 0.25
	world.add_child(t)
	t.timeout.connect(_poll.bind(t, world, pos, report))
	t.start()


static func _poll(t: Timer, world: Node, pos: Vector3, report: Callable) -> void:
	if FloraTex._task != -1:
		if not WorkerThreadPool.is_task_completed(FloraTex._task):
			return
		WorkerThreadPool.wait_for_task_completion(FloraTex._task)
		FloraTex._finish()
	if not FloraTex.tex.has("bark"):
		return
	t.queue_free()
	var t0 := Time.get_ticks_msec()
	var tree := build(7, 1.0)
	var gy := 0.0
	if world.has_method("height_at"):
		gy = float(world.call("height_at", pos.x, pos.z))
	tree.position = Vector3(pos.x, gy, pos.z)
	world.add_child(tree)
	report.call("banyan: OK  %s, %d ms" % [str(tree.get_meta("banyan_info")), Time.get_ticks_msec() - t0])


# ---------------------------------------------------------------------------- F5: 30 banyans in the world
const COUNT := 30
const MIN_DIST := 25.0      # metres between two banyans
const VIS_END := 110.0      # step2: a banyan is drawn only closer than this (100 m + a little)
const VARIANTS := 4         # 4 different shapes, each tree gets its own turn + size
const SPOT_MARGIN := 8.0    # free space around the trunk (roots + limbs reach about 9 m)
const WORLD_SEED := 5005    # same seed = same forest
const DESERT_MAX := 0.25    # no banyan where the desert weight is higher than this


static func place_all(world: Node, report: Callable) -> void:
	FloraTex.start()
	report.call("banyan: waiting for textures ...")
	var t := Timer.new()
	t.wait_time = 0.25
	world.add_child(t)
	t.timeout.connect(_place_poll.bind(t, world, report))
	t.start()


static func _place_poll(t: Timer, world: Node, report: Callable) -> void:
	if FloraTex._task != -1:
		if not WorkerThreadPool.is_task_completed(FloraTex._task):
			return
		WorkerThreadPool.wait_for_task_completion(FloraTex._task)
		FloraTex._finish()
	if not FloraTex.tex.has("bark"):
		return
	t.queue_free()
	_place_now(world, report)


static func _place_now(world: Node, report: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = WORLD_SEED
	var lim: float = Flora.half - 40.0

	# 1. find the spots (x, z, size, variant)
	var spots: Array = []
	var tries := 0
	var biome_n := [0, 0, 0, 0, 0]
	while spots.size() < COUNT and tries < 4000:
		tries += 1
		var x := rng.randf_range(-lim, lim)
		var z := rng.randf_range(-lim, lim)
		var w: Array = Flora.biome_w(x, z)
		if float(w[3]) > DESERT_MAX:
			continue
		if not Flora.spot_ok(x, z, SPOT_MARGIN):
			continue
		var near := false
		for s in spots:
			var sv: Vector4 = s
			if Vector2(sv.x, sv.y).distance_to(Vector2(x, z)) < MIN_DIST:
				near = true
				break
		if near:
			continue
		spots.append(Vector4(x, z, rng.randf_range(0.8, 1.3), float(rng.randi_range(0, VARIANTS - 1))))
		var best := 0
		for k in 5:
			if float(w[k]) > float(w[best]):
				best = k
		biome_n[best] += 1

	# 2. the 4 shapes (wood mesh, leaf mesh, materials) + one MultiMesh of leaves per shape
	var wood_mesh: Array = []
	var wood_mat: Array = []
	var leaf_mesh: Array = []
	var leaf_mat: Array = []
	var counts := [0, 0, 0, 0]
	for s in spots:
		var s0: Vector4 = s
		counts[int(s0.w)] += 1
	var holder := Node3D.new()
	holder.name = "Banyans"
	for v in VARIANTS:
		var r := build(101 + v * 37, 1.0)
		var wd := r.get_node("Wood") as MeshInstance3D
		var lv := r.get_node("Leaves") as MeshInstance3D
		wood_mesh.append(wd.mesh)
		wood_mat.append(wd.material_override)
		leaf_mesh.append(lv.mesh)
		leaf_mat.append(lv.material_override)
		r.free()

	# 3. the trees
	var used := [0, 0, 0, 0]
	for s in spots:
		var sv: Vector4 = s
		var v := int(sv.w)
		var gy := 0.0
		if world.has_method("height_at"):
			gy = float(world.call("height_at", sv.x, sv.y))
		var ry := rng.randf() * TAU
		var tree := Node3D.new()
		tree.name = "Banyan"
		tree.position = Vector3(sv.x, gy, sv.y)
		tree.rotation.y = ry
		tree.scale = Vector3.ONE * sv.z
		var wood := MeshInstance3D.new()
		wood.name = "Wood"
		wood.mesh = wood_mesh[v]
		wood.material_override = wood_mat[v]
		wood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wood.visibility_range_end = VIS_END   # step2: far = not drawn
		tree.add_child(wood)
		var leaves := MeshInstance3D.new()
		leaves.name = "Leaves"
		leaves.mesh = leaf_mesh[v]
		leaves.material_override = leaf_mat[v]
		leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		leaves.visibility_range_end = VIS_END
		tree.add_child(leaves)
		tree.set_meta("size", sv.z)
		holder.add_child(tree)
	world.add_child(holder)
	report.call("banyan: %d/%d trees (farm %d, forest %d, rock %d, desert %d, swamp %d), %d tries, %d ms" % [
			spots.size(), COUNT, biome_n[0], biome_n[1], biome_n[2], biome_n[3], biome_n[4], tries, Time.get_ticks_msec() - t0])
