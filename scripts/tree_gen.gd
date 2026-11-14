extends RefCounted
# SHARED TREE GENERATOR + PLACER for the 100 big shade trees (tree_blob.gd) and the 100 new mixed trees (tree_mix.gd).
#   Every tree is its OWN geometry: own trunk (thick, flared foot), own branches, own leaf masses. Nothing is a copy.
#   Speed (weak phone): all trees of one map cell (CELL metres) are merged into ONE mesh = 1 draw call per cell, and a
#   cell that is outside the camera view is not drawn at all. No texture, no alpha, no shadow, light per vertex.
#   The meshes are built a little at a time (a few ms per frame) while the loading screen is on, so nothing freezes.
#   The finished set appears as ONE node in the world (S.name). warmup.gd waits for that node, so it is only there
#   when EVERY tree of the set is complete.

const Flora = preload("res://scripts/flora.gd")
const Conifer = preload("res://scripts/tree_conifer.gd")

const CELL := 170.0                 # metres: trees of one cell = one mesh (smaller cell = better culling, a few more draw calls)
const FRAME_BUDGET_US := 9000       # microseconds of mesh work per tick (keeps the loading bar moving)

static var taken: Array = []        # Vector2 (x, z) of every tree placed by this file (so the next set keeps away)


# ---------------------------------------------------------------------------- mesh buffer
class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	var tris := 0

	func add_vertex(p: Vector3, nrm: Vector3, col: Color) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col)
		return v.size() - 1

	func add_tri(a: int, b: int, d: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(d)
		tris += 1


# ---------------------------------------------------------------------------- shapes
# a tapered tube from a to b (radius ra -> rb). sides 4..8, segs rings-1. `bend` = sideways bulge in the middle.
static func tube(buf: Buf, a: Vector3, b: Vector3, ra: float, rb: float, sides: int, segs: int, bend: Vector3, col_a: Color, col_b: Color, rot: float, cap: bool) -> void:
	var dir := b - a
	var dist := dir.length()
	if dist < 0.001:
		return
	var up := dir / dist
	var side := up.cross(Vector3.UP)
	if side.length() < 0.05:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	var fwd := up.cross(side).normalized()
	var base := buf.v.size()
	for k in segs + 1:
		var t := float(k) / float(segs)
		var centre := a.lerp(b, t) + bend * (4.0 * t * (1.0 - t))
		var r := lerpf(ra, rb, t)
		var col := col_a.lerp(col_b, t)
		for s in sides:
			var ang := rot + TAU * float(s) / float(sides)
			var o := side * cos(ang) + fwd * sin(ang)
			buf.add_vertex(centre + o * r, (o + up * 0.15).normalized(), col)
	for k in segs:
		for s in sides:
			var s2 := (s + 1) % sides
			var a0 := base + k * sides + s
			var a1 := base + k * sides + s2
			var b0 := a0 + sides
			var b1 := a1 + sides
			buf.add_tri(a0, b0, a1)
			buf.add_tri(a1, b0, b1)
	if cap:
		var top := buf.add_vertex(b, up, col_b)
		var tb := base + segs * sides
		for s in sides:
			buf.add_tri(tb + s, top, tb + (s + 1) % sides)


# a lumpy ellipsoid (leaf mass). dark low in the crown, light on top (col_lo -> col_hi between ymin and ymax)
static func blob(buf: Buf, c: Vector3, r: Vector3, rng: RandomNumberGenerator, segs: int, rings: int, col_lo: Color, col_hi: Color, ymin: float, ymax: float, lump: float) -> void:
	var rows := rings - 1
	var pts: Array = [Vector3(0.0, r.y, 0.0)]
	for i in rows:
		var th := PI * float(i + 1) / float(rings)
		for s in segs:
			var a := TAU * float(s) / float(segs) + float(i) * 0.4
			var k := rng.randf_range(1.0 - lump, 1.0 + lump * 0.8)
			pts.append(Vector3(sin(th) * cos(a) * r.x * k, cos(th) * r.y, sin(th) * sin(a) * r.z * k))
	pts.append(Vector3(0.0, -r.y * 0.8, 0.0))
	var base := buf.v.size()
	var span := maxf(ymax - ymin, 0.01)
	for p in pts:
		var v: Vector3 = p
		var nrm := Vector3(v.x / (r.x * r.x), v.y / (r.y * r.y), v.z / (r.z * r.z)).normalized()
		var t := clampf((c.y + v.y - ymin) / span, 0.0, 1.0)
		var g := rng.randf_range(0.9, 1.07)
		var col := col_lo.lerp(col_hi, pow(t, 0.85))
		buf.add_vertex(c + v, (nrm + Vector3.UP * 0.35).normalized(), Color(col.r * g, col.g * g, col.b * g, 1.0))
	var last := pts.size() - 1
	for s in segs:
		var s2 := (s + 1) % segs
		buf.add_tri(base, base + 1 + s, base + 1 + s2)
		for i in rows - 1:
			var a0 := base + 1 + i * segs + s
			var a1 := base + 1 + i * segs + s2
			var b0 := a0 + segs
			var b1 := a1 + segs
			buf.add_tri(a0, b0, a1)
			buf.add_tri(a1, b0, b1)
		var l0 := base + 1 + (rows - 1) * segs + s
		var l1 := base + 1 + (rows - 1) * segs + s2
		buf.add_tri(l0, base + last, l1)


# a cone: round base ring at `base_c`, point at `tip`. Tip below the base = a hanging curtain (willow).
static func cone(buf: Buf, base_c: Vector3, tip: Vector3, wide: float, segs: int, rng: RandomNumberGenerator, col_lo: Color, col_hi: Color, ymin: float, ymax: float, lump: float) -> void:
	var base := buf.v.size()
	var span := maxf(ymax - ymin, 0.01)
	for s in segs:
		var a := TAU * float(s) / float(segs) + rng.randf() * 0.2
		var k := rng.randf_range(1.0 - lump, 1.0 + lump)
		var p := base_c + Vector3(cos(a), 0.0, sin(a)) * wide * k
		var out := Vector3(p.x - base_c.x, 0.35, p.z - base_c.z).normalized()
		var t := clampf((p.y - ymin) / span, 0.0, 1.0)
		var g := rng.randf_range(0.9, 1.06)
		var col := col_lo.lerp(col_hi, t)
		buf.add_vertex(p, out, Color(col.r * g, col.g * g, col.b * g, 1.0))
	var ti := buf.add_vertex(tip, Vector3.UP, col_lo.lerp(col_hi, clampf((tip.y - ymin) / span, 0.0, 1.0)))
	var bi := buf.add_vertex(base_c, Vector3.DOWN, col_lo)
	for s in segs:
		var s2 := (s + 1) % segs
		buf.add_tri(base + s, ti, base + s2)
		buf.add_tri(base + s2, bi, base + s)


# ---------------------------------------------------------------------------- one tree
# P keys (all set by the maker in tree_blob.gd / tree_mix.gd):
#   shape   "round" | "umbrella" | "vase" | "column" | "weeping" | "layered" | "cone" | "bottle" | "open"
#   height (m), trunk_r (m, radius above the root flare), trunk_h (0..1 clear trunk), taper (0..1 top radius / foot radius)
#   lean (Vector2 m), limbs (int), limb_len (m), limb_up (steepness), twigs (int per limb), blob_r (m), blob_flat (y / xz)
#   filler_r (m), lump (0..0.4), sides (trunk sides), bark_lo / bark_hi / leaf_lo / leaf_hi (Color)
static func tree(buf: Buf, ox: float, oy: float, oz: float, P: Dictionary, rng: RandomNumberGenerator) -> void:
	var H: float = P["height"]
	var R0: float = P["trunk_r"]
	var shape: String = P["shape"]
	var th: float = H * float(P["trunk_h"])
	var lean: Vector2 = P["lean"]
	var bark_lo: Color = P["bark_lo"]
	var bark_hi: Color = P["bark_hi"]
	var leaf_lo: Color = P["leaf_lo"]
	var leaf_hi: Color = P["leaf_hi"]
	var sides: int = int(P.get("sides", 7))
	var limbs: int = int(P["limbs"])
	var limb_len: float = P["limb_len"]
	var limb_up: float = P["limb_up"]
	var twigs: int = int(P["twigs"])
	var blob_r: float = P["blob_r"]
	var blob_flat: float = P["blob_flat"]
	var fill_r: float = P["filler_r"]
	var lump: float = float(P.get("lump", 0.18))
	var segs: int = int(P.get("blob_segs", 6))
	var tall := shape == "cone" or shape == "column"
	var tt: float = H * 0.93 if tall else th          # top of the trunk
	var top_r: float = maxf(R0 * float(P.get("taper", 0.45)), 0.06)
	if shape == "bottle":
		top_r = maxf(R0 * 0.55, 0.1)
	var foot := Vector3(ox, oy - 0.1, oz)
	var ymin: float = oy + th * 0.5
	var ymax: float = oy + H * 1.02

	# --- trunk: flared foot + 3 sections, leaning, a little wobble. (thick: R0 is big)
	var tsv := PackedFloat32Array([0.0, 0.12, 0.5, 1.0])
	var rsv := PackedFloat32Array([R0 * 1.45, R0, lerpf(R0, top_r, 0.55), top_r])
	if shape == "bottle":
		rsv = PackedFloat32Array([R0 * 1.15, R0 * 1.2, R0 * 1.0, top_r])
	var tp: Array = []
	for k in 4:
		var t: float = tsv[k]
		tp.append(foot + Vector3(lean.x * t * t, tt * t, lean.y * t * t))
	var wob := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * (0.12 + R0 * 0.25)
	for k in 3:
		var pa: Vector3 = tp[k]
		var pb: Vector3 = tp[k + 1]
		var bend := wob if k == 1 else Vector3.ZERO
		var ta: float = tsv[k]
		var tb: float = tsv[k + 1]
		tube(buf, pa, pb, rsv[k], rsv[k + 1], sides, 2 if k == 1 else 1, bend, bark_lo.lerp(bark_hi, ta), bark_lo.lerp(bark_hi, tb), rng.randf() * TAU, k == 2)

	# --- branches + leaf masses
	var ang0 := rng.randf() * TAU
	var tip_count := 0
	for l in limbs:
		var u := float(l) / float(maxi(limbs - 1, 1))
		var ang := ang0 + float(l) * 2.39996 + rng.randf_range(-0.3, 0.3)
		var sy: float
		if tall:
			sy = th * 0.55 + (tt - th * 0.55) * u * 0.92
		elif shape == "layered":
			sy = th * 0.8 + (H * 0.88 - th * 0.8) * (float(l % 4) / 3.0)
		else:
			sy = th * lerpf(0.78, 1.0, u)
		var tf := clampf(sy / maxf(tt, 0.1), 0.0, 1.0)
		var from := foot + Vector3(lean.x * tf * tf, sy, lean.y * tf * tf)
		var rl: float
		if tall:
			rl = limb_len * (1.0 - 0.55 * u) * rng.randf_range(0.8, 1.15)
		else:
			rl = limb_len * rng.randf_range(0.8, 1.15) * (1.1 - 0.3 * u)
		var el: float = limb_up * rng.randf_range(0.75, 1.25)
		if shape == "weeping":
			el = 0.9 * (1.0 - u) + 0.3
		var dirh := Vector3(cos(ang), 0.0, sin(ang))
		var to := from + (dirh + Vector3(0.0, el, 0.0)).normalized() * rl
		if shape == "weeping":
			to.y -= rl * 0.45
		var lr: float = lerpf(R0 * 0.5, R0 * 0.2, u)
		if shape == "bottle" or tall:
			lr = R0 * 0.22
		lr = maxf(lr, 0.07)
		var lbend := Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, 0.4), rng.randf_range(-0.3, 0.3)) * rl * 0.35
		tube(buf, from, to, lr, maxf(lr * 0.35, 0.03), 4, 2, lbend, bark_hi * 0.92, bark_hi, rng.randf() * TAU, true)

		var tips: Array = [to]
		for w in twigs:
			var tt2 := rng.randf_range(0.4, 0.8)
			var pt := from.lerp(to, tt2) + lbend * (4.0 * tt2 * (1.0 - tt2))
			var tdir := (dirh.rotated(Vector3.UP, rng.randf_range(-1.1, 1.1)) + Vector3(0.0, rng.randf_range(0.1, 0.7), 0.0)).normalized()
			if shape == "weeping":
				tdir = Vector3(tdir.x * 0.6, -0.8, tdir.z * 0.6).normalized()
			var tto := pt + tdir * rl * rng.randf_range(0.3, 0.5)
			tube(buf, pt, tto, maxf(lr * 0.4, 0.04), 0.025, 4, 1, Vector3.ZERO, bark_hi, bark_hi, 0.0, true)
			tips.append(tto)

		for tip in tips:
			var c: Vector3 = tip
			var br := blob_r * rng.randf_range(0.75, 1.2) * (1.15 - 0.3 * u)
			c += Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.1, 0.4), rng.randf_range(-0.5, 0.5)) * br * 0.5
			tip_count += 1
			if shape == "weeping":
				var hang := minf(H * rng.randf_range(0.28, 0.5), c.y - oy - 1.0)
				cone(buf, c, Vector3(c.x, c.y - maxf(hang, 1.0), c.z), br * 0.55, 5, rng, leaf_lo, leaf_hi, oy, ymax, 0.2)
				blob(buf, c, Vector3(br * 0.7, br * 0.5, br * 0.7), rng, segs, 3, leaf_lo, leaf_hi, ymin, ymax, lump)
			elif shape == "cone":
				cone(buf, c + Vector3(0.0, -br * 0.4, 0.0), c + Vector3(0.0, br * 0.9, 0.0), br * 1.25, 7, rng, leaf_lo, leaf_hi, ymin, ymax, lump)
			else:
				blob(buf, c, Vector3(br, br * blob_flat, br), rng, segs, 3, leaf_lo, leaf_hi, ymin, ymax, lump)

	# --- centre of the crown: one big mass so the outline is a real shape (not only dots at the branch ends)
	var fpos := Vector3(ox + lean.x, oy + th + (H - th) * rng.randf_range(0.4, 0.7), oz + lean.y)
	match shape:
		"weeping":
			blob(buf, fpos + Vector3(0.0, H * 0.06, 0.0), Vector3(fill_r * 0.75, fill_r * 0.45, fill_r * 0.75), rng, segs + 1, 3, leaf_lo, leaf_hi, ymin, ymax, lump)
		"umbrella":
			blob(buf, Vector3(fpos.x, oy + th + (H - th) * 0.55, fpos.z), Vector3(fill_r, fill_r * 0.3, fill_r), rng, segs + 1, 3, leaf_lo, leaf_hi, ymin, ymax, lump)
		"cone", "column":
			cone(buf, Vector3(fpos.x, oy + th * 0.95, fpos.z), Vector3(ox + lean.x, oy + H, oz + lean.y), fill_r * (0.5 if shape == "column" else 0.85), 7, rng, leaf_lo, leaf_hi, ymin, ymax, lump)
		"bottle":
			blob(buf, Vector3(fpos.x, oy + th + (H - th) * 0.5, fpos.z), Vector3(fill_r * 0.9, fill_r * 0.45, fill_r * 0.9), rng, segs, 3, leaf_lo, leaf_hi, ymin, ymax, lump)
		"open":
			pass
		_:
			blob(buf, fpos, Vector3(fill_r, fill_r * blob_flat * 1.1, fill_r), rng, segs + 1, 3, leaf_lo, leaf_hi, ymin, ymax, lump)
	if shape == "round" or shape == "vase":
		blob(buf, Vector3(ox + lean.x, oy + H - blob_r * 0.5, oz + lean.y), Vector3(blob_r * 1.1, blob_r * blob_flat, blob_r * 1.1), rng, segs, 3, leaf_lo, leaf_hi, ymin, ymax, lump)


# ---------------------------------------------------------------------------- parameters from a type table
# T (Dictionary) holds RANGES [lo, hi]: h (total height), r (trunk radius above the root flare), th (clear trunk 0..1), limbs, ll (limb length),
#   up (limb steepness), tw (twigs per limb), br (leaf mass radius), fl (leaf mass flatness), fr (centre mass radius), lean (metres per 12 m height),
#   shape, leaf = list of palette numbers, bark = list of palette numbers.
# Every call draws NEW random numbers, so no two trees get the same height / thickness / limb count / colour.
static func _rr(rng: RandomNumberGenerator, a: Array) -> float:
	return rng.randf_range(float(a[0]), float(a[1]))


static func _jit(c: Color, rng: RandomNumberGenerator, k: float) -> Color:
	return Color(clampf(c.r * rng.randf_range(1.0 - k, 1.0 + k), 0.0, 1.0), clampf(c.g * rng.randf_range(1.0 - k, 1.0 + k), 0.0, 1.0), clampf(c.b * rng.randf_range(1.0 - k, 1.0 + k), 0.0, 1.0), 1.0)


static func params(rng: RandomNumberGenerator, T: Dictionary, leaf_pals: Array, bark_pals: Array) -> Dictionary:
	var H: float = _rr(rng, T["h"])
	var R0: float = _rr(rng, T["r"])
	var li_list: Array = T["leaf"]
	var bi_list: Array = T["bark"]
	var lpal: Array = leaf_pals[int(li_list[rng.randi() % li_list.size()])]
	var bpal: Array = bark_pals[int(bi_list[rng.randi() % bi_list.size()])]
	var lean_k: float = float(T.get("lean", 0.5)) * H / 12.0
	var tw: Array = T["tw"]
	var lm: Array = T["limbs"]
	var b0: Color = bpal[0]
	var b1: Color = bpal[1]
	var l0: Color = lpal[0]
	var l1: Color = lpal[1]
	return {
		"shape": String(T["shape"]),
		"height": H,
		"trunk_r": R0,
		"trunk_h": _rr(rng, T["th"]),
		"taper": rng.randf_range(0.38, 0.6),
		"lean": Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * lean_k,
		"limbs": rng.randi_range(int(lm[0]), int(lm[1])),
		"limb_len": _rr(rng, T["ll"]),
		"limb_up": _rr(rng, T["up"]),
		"twigs": rng.randi_range(int(tw[0]), int(tw[1])),
		"blob_r": _rr(rng, T["br"]),
		"blob_flat": _rr(rng, T["fl"]),
		"filler_r": _rr(rng, T["fr"]),
		"lump": rng.randf_range(0.12, 0.26),
		"blob_segs": 6 + (rng.randi() % 2),
		"sides": 6 if R0 < 0.7 else 7,
		"bark_lo": _jit(b0, rng, 0.08),
		"bark_hi": _jit(b1, rng, 0.08),
		"leaf_lo": _jit(l0, rng, 0.07),
		"leaf_hi": _jit(l1, rng, 0.07),
	}


# ---------------------------------------------------------------------------- shared material
static var _mat: StandardMaterial3D = null


static func material() -> StandardMaterial3D:
	if _mat == null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX   # light per vertex: cheap on a phone
		m.roughness = 1.0
		m.metallic_specular = 0.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat = m
	return _mat


static func to_instance(buf: Buf, node_name: String) -> MeshInstance3D:
	if buf.v.size() == 0 or buf.idx.size() == 0:
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buf.v
	arrays[Mesh.ARRAY_NORMAL] = buf.n
	arrays[Mesh.ARRAY_COLOR] = buf.c
	arrays[Mesh.ARRAY_INDEX] = buf.idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 6.0
	return mi


# ---------------------------------------------------------------------------- placement + build pipeline
# S (Dictionary):  name (node name of the finished set), report_key, count, min_dist, margin, seed,
#   desert_max, swamp_max, wait_nodes (Array of node names that must exist first), maker (Callable(rng, i, count) -> Dictionary P),
#   trunk_hit (float: collision radius = trunk_r * this)
static func start(world: Node, report: Callable, S: Dictionary) -> void:
	var t := Timer.new()
	t.wait_time = 0.25
	world.add_child(t)
	t.timeout.connect(_poll.bind(t, world, report, S))
	t.start()


static func _poll(t: Timer, world: Node, report: Callable, S: Dictionary) -> void:
	for n in S["wait_nodes"]:
		if world.get_node_or_null(String(n)) == null:
			return
	t.queue_free()
	_plan(world, report, S)


# true when ANY point on a ring round (x, z) is a little bit desert (trees must stay well away from the sand)
static func _desert_near(x: float, z: float, radius: float, limit: float) -> bool:
	for k in 8:
		var a := TAU * float(k) / 8.0
		var w: Array = Flora.biome_w(x + cos(a) * radius, z + sin(a) * radius)
		if float(w[3]) > limit:
			return true
	return false


static func _plan(world: Node, report: Callable, S: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(S["seed"])
	var half: float = Flora.half
	var lim: float = half - 40.0
	var count: int = int(S["count"])
	var margin: float = float(S["margin"])
	var min_dist: float = float(S["min_dist"])
	var desert_max: float = float(S["desert_max"])
	var swamp_max: float = float(S["swamp_max"])

	# places to keep away from: banyans, conifers and every tree set placed before this one. Vector3(x, z, radius)
	var avoid: Array = []
	var bh := world.get_node_or_null("Banyans")
	if bh != null:
		for c in bh.get_children():
			avoid.append(Vector3((c as Node3D).position.x, (c as Node3D).position.z, 12.0))
	for p in Conifer.spots_taken:
		avoid.append(Vector3((p as Vector2).x, (p as Vector2).y, 5.0))
	for p in taken:
		avoid.append(Vector3((p as Vector2).x, (p as Vector2).y, 8.0))
	var own_r: float = float(S.get("own_r", 5.0))
	var ring_r: float = float(S.get("desert_ring", 20.0))
	var ring_max: float = float(S.get("desert_ring_max", 0.03))

	var spots: Array = []
	var mine: Array = []
	var tries := 0
	var dist_now := min_dist
	while spots.size() < count and tries < 40000:
		tries += 1
		if tries % 8000 == 0:
			dist_now = maxf(dist_now - 1.5, min_dist * 0.55)   # crowded map: allow trees a little closer, but never skip the count
		var x := rng.randf_range(-lim, lim)
		var z := rng.randf_range(-lim, lim)
		var w: Array = Flora.biome_w(x, z)
		if float(w[3]) > desert_max or float(w[4]) > swamp_max:
			continue
		if not Flora.spot_ok(x, z, margin):
			continue
		var p := Vector2(x, z)
		var bad := false
		for q in mine:
			if (q as Vector2).distance_to(p) < dist_now:
				bad = true
				break
		if not bad:
			for a in avoid:
				var av: Vector3 = a
				if Vector2(av.x, av.y).distance_to(p) < av.z + own_r:
					bad = true
					break
		if bad:
			continue
		if _desert_near(x, z, ring_r, ring_max):
			continue   # also not at the edge of the desert (checked last: it is the slowest test)
		mine.append(p)
		spots.append(p)

	# one definition per tree: place, own seed, own parameters
	var maker: Callable = S["maker"]
	var defs: Array = []
	for i in spots.size():
		var sp: Vector2 = spots[i]
		var gy := 0.0
		if world.has_method("height_at"):
			gy = float(world.call("height_at", sp.x, sp.y))
		var P: Dictionary = maker.call(rng, i, spots.size())
		defs.append({"x": sp.x, "y": gy, "z": sp.y, "seed": rng.randi(), "P": P})

	# sort the trees into map cells
	var ncell := int(ceil(half * 2.0 / CELL))
	var cells: Array = []
	for i in ncell * ncell:
		cells.append([])
	for d in defs:
		var cx := clampi(int(floor((float((d as Dictionary)["x"]) + half) / CELL)), 0, ncell - 1)
		var cz := clampi(int(floor((float((d as Dictionary)["z"]) + half) / CELL)), 0, ncell - 1)
		(cells[cz * ncell + cx] as Array).append(d)

	var ctx := {
		"S": S, "defs": defs, "cells": cells, "next": 0, "holder": Node3D.new(), "tris": 0, "meshes": 0,
		"t0": t0, "tries": tries, "plan_ms": Time.get_ticks_msec() - t0, "spots": mine,
	}
	(ctx["holder"] as Node3D).name = String(S["name"]) + "_build"   # renamed when finished
	var tk := Timer.new()
	tk.wait_time = 0.03
	world.add_child(tk)
	tk.timeout.connect(_tick.bind(tk, world, report, ctx))
	tk.start()
	report.call("%s: planned %d/%d trees, building ..." % [String(S["report_key"]), spots.size(), count])


static func _tick(tk: Timer, world: Node, report: Callable, ctx: Dictionary) -> void:
	var S: Dictionary = ctx["S"]
	var cells: Array = ctx["cells"]
	var holder: Node3D = ctx["holder"]
	var t_start := Time.get_ticks_usec()
	while int(ctx["next"]) < cells.size():
		var ci: int = int(ctx["next"])
		ctx["next"] = ci + 1
		var list: Array = cells[ci]
		if list.is_empty():
			continue
		var buf := Buf.new()
		var rng := RandomNumberGenerator.new()
		for d in list:
			var dd: Dictionary = d
			rng.seed = int(dd["seed"])
			tree(buf, float(dd["x"]), float(dd["y"]), float(dd["z"]), dd["P"], rng)
		var mi := to_instance(buf, "%s_cell%d" % [String(S["name"]), ci])
		if mi != null:
			holder.add_child(mi)
			ctx["meshes"] = int(ctx["meshes"]) + 1
			ctx["tris"] = int(ctx["tris"]) + buf.tris
		if Time.get_ticks_usec() - t_start > FRAME_BUDGET_US:
			break
	if int(ctx["next"]) < cells.size():
		return
	tk.queue_free()
	_finish(world, report, ctx)


static func _finish(world: Node, report: Callable, ctx: Dictionary) -> void:
	var S: Dictionary = ctx["S"]
	var holder: Node3D = ctx["holder"]
	var defs: Array = ctx["defs"]
	# trunks: one static body, one cylinder per tree (own radius, own height)
	var body := StaticBody3D.new()
	body.name = String(S["name"]) + "Trunks"
	body.collision_layer = 1
	body.collision_mask = 0
	var hit_k: float = float(S["trunk_hit"])
	for d in defs:
		var dd: Dictionary = d
		var P: Dictionary = dd["P"]
		var cyl := CylinderShape3D.new()
		cyl.radius = maxf(float(P["trunk_r"]) * hit_k, 0.25)
		cyl.height = clampf(float(P["height"]) * float(P["trunk_h"]) + 1.0, 3.0, 10.0)
		var cs := CollisionShape3D.new()
		cs.shape = cyl
		cs.position = Vector3(float(dd["x"]), float(dd["y"]) + cyl.height * 0.5, float(dd["z"]))
		body.add_child(cs)
	holder.add_child(body)
	holder.name = String(S["name"])
	for p in (ctx["spots"] as Array):
		taken.append(p)
	world.add_child(holder)   # the set exists only now = every tree is complete
	report.call("%s: %d/%d trees, %d meshes (= max %d draw calls), %d triangles, %d tries, %d ms" % [
		String(S["report_key"]), defs.size(), int(S["count"]), int(ctx["meshes"]), int(ctx["meshes"]), int(ctx["tris"]), int(ctx["tries"]), Time.get_ticks_msec() - int(ctx["t0"])])
