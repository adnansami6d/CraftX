extends Node3D
# V25: rocks, reeds ... of the big map are made in 200 m squares around the camera.
# Only the nearby squares exist; far squares are deleted. A square is built over a few frames (no big hitch).
# Same square = same things every time (the random seed comes from the square number).

const Util = preload("res://scripts/util.gd")
const Biome = preload("res://scripts/biome.gd")
const SaveGame = preload("res://scripts/savegame.gd")
const CHUNK := 100.0    # step2: 100 m squares (was 200): smaller pieces = smaller work per frame
const LOAD_R := 120.0   # step2: build a square when its centre is closer than this (draw area about 120 m)
const KEEP_R := 170.0   # step2: delete a square when its centre is farther than this
const GRID := 12        # 12 x 12 sample cells per square (about 8 m each, same density as before)
const VIS_END := 140.0  # step2: rocks / reeds farther than this from the camera are not drawn

var half := 500.0
var rail: Node   # V26: has near_track(x, z)
var blocks: Array = []   # Rect2 list: nothing is placed inside (old map, future buildings)
var _chunks := {}
var _t := 1.0
var _building := false
var _m := {}
var _warm: Node3D = null


func start() -> void:
	_m["rock"] = Util.sphere(1.0, 6, 3)
	_m["reed"] = Util.cone(0.15, 1.2, 4)
	_m["puddle"] = Util.cyl(1.0, 0.04, 10)
	_m["puddle_m"] = Util.mat(Color(0.16, 0.27, 0.26), 0.1, 0.2)
	# v_001: one hidden copy of rock / reed / puddle, so the warm-up draws them once (no first-time freeze later)
	_warm = Node3D.new()
	_warm.add_to_group("stream_warm")
	add_child(_warm)
	var one := [Transform3D(Basis.IDENTITY, Vector3(0, -30, 0))]
	var onec := [Color(0.5, 0.5, 0.5)]
	Util.multi(_warm, _m["rock"], Util.vcol_mat(), one, onec)
	Util.multi(_warm, _m["reed"], Util.vcol_mat(), one, onec)
	Util.multi(_warm, _m["puddle"], _m["puddle_m"], one, [])


func free_warm() -> void:
	if _warm != null and is_instance_valid(_warm):
		_warm.queue_free()
	_warm = null


func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.3 and not _building:
		_t = 0.0
		_update()


func _centre(k: Vector2i) -> Vector2:
	return Vector2((float(k.x) + 0.5) * CHUNK, (float(k.y) + 0.5) * CHUNK)


func _update() -> void:
	var cam := get_viewport().get_camera_3d()
	var cp := Vector2.ZERO
	if cam != null:
		cp = Vector2(cam.global_position.x, cam.global_position.z)
	for k in _chunks.keys():
		if _centre(k).distance_to(cp) > KEEP_R:
			(_chunks[k] as Node).queue_free()
			_chunks.erase(k)
	var ck := Vector2i(floori(cp.x / CHUNK), floori(cp.y / CHUNK))
	var best := Vector2i.ZERO
	var bd := LOAD_R
	var found := false
	var mapr := Rect2(-half, -half, half * 2.0, half * 2.0)
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var k := Vector2i(ck.x + dx, ck.y + dz)
			if _chunks.has(k) or not mapr.intersects(Rect2(float(k.x) * CHUNK, float(k.y) * CHUNK, CHUNK, CHUNK)):
				continue
			var d := _centre(k).distance_to(cp)
			if d < bd:
				bd = d
				best = k
				found = true
	if found:
		_build(best)


func _build(k: Vector2i) -> void:
	_building = true
	Util.dbg["what"] = "stream chunk %d,%d" % [k.x, k.y]
	var node := Node3D.new()
	var cx := (float(k.x) + 0.5) * CHUNK
	var cz := (float(k.y) + 0.5) * CHUNK
	node.position = Vector3(cx, 0.0, cz)
	add_child(node)
	_chunks[k] = node
	var x0 := float(k.x) * CHUNK
	var z0 := float(k.y) * CHUNK
	var all_farm := true
	for c in [Vector2(x0, z0), Vector2(x0 + CHUNK, z0), Vector2(x0, z0 + CHUNK), Vector2(x0 + CHUNK, z0 + CHUNK), Vector2(cx, cz)]:
		if float(Biome.weights(c.x, c.y)[0]) < 0.999:
			all_farm = false
			break
	if all_farm:
		_building = false
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (k.x * 73856093) ^ (k.y * 19349663) ^ 7919
	var cell := CHUNK / float(GRID)
	var ak := cell * cell / 1000.0
	var lim := half - 28.0
	var rk: Array = []
	var rkcol: Array = []
	var rd: Array = []
	var rdcol: Array = []
	var pd: Array = []
	var shapes: Array = []   # [shape, local position, kind, size]   (DIG5: kind + size so the gun can cut it)
	var rshapes: Array = []  # FIX: [shape, local position, size] of the rocks you can walk through (small ones): bullets only (layer 3)
	for gx in GRID:
		if gx % 3 == 2:   # step2: a pause every 3 columns
			await get_tree().process_frame
			if not _chunks.has(k):
				_building = false
				return
		for gz in GRID:
			var x := x0 + (float(gx) + rng.randf()) * cell
			var z := z0 + (float(gz) + rng.randf()) * cell
			if absf(x) > lim or absf(z) > lim:
				continue
			var p2d := Vector2(x, z)
			var blocked := false
			for b in blocks:
				if (b as Rect2).has_point(p2d):
					blocked = true
					break
			if rail != null and rail.near_track(x, z):
				continue
			if blocked:
				continue
			var w: Array = Biome.weights(x, z)
			var lx := x - cx
			var lz := z - cz
			var yaw := Basis(Vector3.UP, rng.randf() * TAU)
			var r: float = w[2]
			var d: float = w[3]
			var s: float = w[4]
			if r > 0.03:
				if rng.randf() < 3.5 * ak * r:
					var sc := 0.8 + rng.randf() * rng.randf() * 2.6
					rk.append(Transform3D(yaw * Basis.from_scale(Vector3(sc * 1.1, sc * 0.8, sc)), Vector3(lx, 0.45 * sc, lz)))
					var g := rng.randf_range(0.4, 0.58)
					rkcol.append(Color(g, g * 0.97, g * 0.92))
					if sc > 1.5:
						var cs := CylinderShape3D.new()
						cs.radius = 0.95 * sc
						cs.height = 1.6 * sc
						shapes.append([cs, Vector3(lx, 0.8 * sc, lz), "rock", sc])
					else:
						_add_rock_hit(rshapes, lx, lz, sc, 0.45 * sc, 0.9)   # FIX: every rock can be broken
				if rng.randf() < 6.0 * ak * r:
					var sc2 := rng.randf_range(0.25, 0.6)
					rk.append(Transform3D(yaw * Basis.from_scale(Vector3(sc2 * 1.2, sc2 * 0.8, sc2)), Vector3(lx, 0.2 * sc2, lz)))
					var g2 := rng.randf_range(0.4, 0.6)
					rkcol.append(Color(g2, g2, g2 * 0.95))
					_add_rock_hit(rshapes, lx, lz, sc2, 0.2 * sc2, 1.2)   # FIX: small rocks too
			if d > 0.03:
				if rng.randf() < 0.5 * ak * d:
					var sc5 := rng.randf_range(0.5, 1.4)
					rk.append(Transform3D(yaw * Basis.from_scale(Vector3(sc5 * 1.1, sc5 * 0.8, sc5)), Vector3(lx, 0.4 * sc5, lz)))
					rkcol.append(Color(0.7, 0.62, 0.48))
					_add_rock_hit(rshapes, lx, lz, sc5, 0.4 * sc5, 0.9)   # FIX: desert rocks too
			if s > 0.03:
				if rng.randf() < 5.0 * ak * s:
					for i in 4:
						var sc6 := rng.randf_range(0.8, 1.6)
						rd.append(Transform3D(Basis.from_scale(Vector3.ONE * sc6), Vector3(lx + rng.randf_range(-0.8, 0.8), 0.6 * sc6, lz + rng.randf_range(-0.8, 0.8))))
						rdcol.append(Color(rng.randf_range(0.25, 0.35), rng.randf_range(0.4, 0.5), rng.randf_range(0.15, 0.2)))
				if rng.randf() < 0.9 * ak * s:
					var pr := rng.randf_range(1.5, 4.5)
					pd.append(Transform3D(Basis.from_scale(Vector3(pr, 1.0, pr)), Vector3(lx, 0.03, lz)))
	await get_tree().process_frame
	if not _chunks.has(k):
		_building = false
		return
	var leaf_m := Util.vcol_mat()
	_multi(node, "rock", leaf_m, rk, rkcol)
	_multi(node, "reed", leaf_m, rd, rdcol)
	_multi(node, "puddle", _m["puddle_m"], pd, [])
	await get_tree().process_frame
	if not _chunks.has(k):
		_building = false
		return
	if not shapes.is_empty():
		var body := StaticBody3D.new()
		body.set_meta("cuttable", true)
		node.add_child(body)
		var n := 0
		for sh in shapes:   # v_001: a few shapes per frame (no physics hitch)
			var cs := CollisionShape3D.new()
			cs.shape = sh[0]
			cs.position = sh[1]
			if sh.size() > 3:
				cs.set_meta("kind", sh[2])
				cs.set_meta("size", sh[3])
			body.add_child(cs)
			n += 1
			if n % 4 == 0:
				await get_tree().process_frame
				if not _chunks.has(k) or not is_instance_valid(body):
					_building = false
					return
	if not rshapes.is_empty():
		var bb := StaticBody3D.new()
		bb.collision_layer = 4   # layer 3: bullets hit it, the player / camera / tractor do not see it
		bb.collision_mask = 0
		bb.set_meta("cuttable", true)
		node.add_child(bb)
		var n2 := 0
		for rs in rshapes:   # FIX: rocks that are not solid for the player, but the gun can break them
			var rcs := CollisionShape3D.new()
			rcs.shape = rs[0]
			rcs.position = rs[1]
			rcs.set_meta("kind", "rock")
			rcs.set_meta("size", rs[2])
			bb.add_child(rcs)
			n2 += 1
			if n2 % 6 == 0:
				await get_tree().process_frame
				if not _chunks.has(k) or not is_instance_valid(bb):
					_building = false
					return
	SaveGame.apply_cuts(node)   # v_012d: things you broke before stay broken
	_building = false
	Util.dbg["what"] = ""


# FIX: a bullet-only hit shape for a rock (a sphere a bit bigger than the picture, at least 0.4 m so small stones are easy to hit)
func _add_rock_hit(rshapes: Array, lx: float, lz: float, sc: float, y: float, k: float) -> void:
	var sp := SphereShape3D.new()
	sp.radius = maxf(k * sc, 0.4)
	rshapes.append([sp, Vector3(lx, y, lz), sc])


func _multi(parent: Node, mesh_key: String, mat: Material, xf: Array, col: Array) -> void:
	if xf.is_empty():
		return
	var before := parent.get_child_count()
	Util.multi(parent, _m[mesh_key], mat, xf, col)
	for i in range(before, parent.get_child_count()):
		var c := parent.get_child(i)
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).visibility_range_end = VIS_END

