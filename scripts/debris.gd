extends Node3D
# FALLING PIECES. When a tree / bush / rock is broken, a few small cubes (its colour) fly out, fall, bounce
# once or twice, lie on the ground and shrink away.
#
# Cheap on purpose (phone):
#   - ONE MultiMesh draws all cubes (one draw call), no physics bodies, no collision with anything but the ground.
#   - LIMIT: at most MAX_DEBRIS cubes exist at once. When it is full, the oldest cube is reused for the new one.
#   - No per-frame allocation except the transforms written into the MultiMesh.
#   - When no cube exists, _process is switched off.

const MAX_DEBRIS := 80        # cubes at the same time (the LIMIT)
const PER_PIECE := 3          # cubes made for one destroyed piece
const SIZE_MIN := 0.14        # cube size in meters (a piece is 0.61 m)
const SIZE_MAX := 0.26
const LIFE_MIN := 2.5         # seconds a cube lives before it starts to shrink
const LIFE_MAX := 4.0
const SHRINK := 0.8           # seconds the shrinking takes
const GRAVITY := 14.0
const BOUNCE := 0.3           # speed kept after hitting the ground

var _ground: Callable         # (x, z) -> ground height
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _p: Array = []            # {pos, vel, axis, ang, spin, size, col, age, life, rest}


func setup(ground_fn: Callable) -> void:
	_ground = ground_fn
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mesh.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = mesh
	_mm.instance_count = MAX_DEBRIS
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # F8
	_mmi.multimesh = _mm
	_mmi.top_level = true   # world space, whatever the parent does
	_mmi.custom_aabb = AABB(Vector3(-2000, -100, -2000), Vector3(4000, 600, 4000))   # cubes move: do not let culling hide them
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	set_process(false)


func count() -> int:
	return _p.size()


# pos = world centre of the broken thing, col = its colour, dir = bullet direction (the cubes get a push along it)
func spawn(pos: Vector3, col: Color, dir: Vector3 = Vector3.ZERO, n: int = PER_PIECE) -> void:
	if _mm == null:
		return
	for i in n:
		if _p.size() >= MAX_DEBRIS:
			_p.pop_front()   # full: the oldest cube is replaced
		var shade := randf_range(0.8, 1.1)
		var c := Color(clampf(col.r * shade, 0.0, 1.0), clampf(col.g * shade, 0.0, 1.0), clampf(col.b * shade, 0.0, 1.0))
		var v := Vector3(randf_range(-1.8, 1.8), randf_range(1.0, 3.2), randf_range(-1.8, 1.8)) + dir * randf_range(1.0, 3.0)
		_p.append({
			"pos": pos + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2)),
			"vel": v,
			"axis": Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized(),
			"ang": randf() * TAU,
			"spin": randf_range(-8.0, 8.0),
			"size": randf_range(SIZE_MIN, SIZE_MAX),
			"col": c,
			"age": 0.0,
			"life": randf_range(LIFE_MIN, LIFE_MAX),
			"rest": false,
		})
	set_process(true)


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var i := 0
	while i < _p.size():
		var d: Dictionary = _p[i]
		d["age"] = float(d["age"]) + dt
		if float(d["age"]) >= float(d["life"]) + SHRINK:
			_p[i] = _p[_p.size() - 1]   # remove: move the last one here
			_p.pop_back()
			continue
		if not bool(d["rest"]):
			var vel: Vector3 = d["vel"]
			vel.y -= GRAVITY * dt
			var pos: Vector3 = d["pos"] + vel * dt
			d["ang"] = float(d["ang"]) + float(d["spin"]) * dt
			var half := float(d["size"]) * 0.5
			var gy := 0.0
			if _ground.is_valid():
				gy = float(_ground.call(pos.x, pos.z))
			if pos.y < gy + half:
				pos.y = gy + half
				if absf(vel.y) < 1.2:
					d["rest"] = true
					vel = Vector3.ZERO
				else:
					vel.y = -vel.y * BOUNCE
					vel.x *= 0.6
					vel.z *= 0.6
					d["spin"] = float(d["spin"]) * 0.5
			d["vel"] = vel
			d["pos"] = pos
		i += 1
	var n := _p.size()
	for k in n:
		var q: Dictionary = _p[k]
		var s := float(q["size"])
		var over := float(q["age"]) - float(q["life"])
		if over > 0.0:
			s *= clampf(1.0 - over / SHRINK, 0.0, 1.0)
		var b := Basis(q["axis"], float(q["ang"])).scaled(Vector3(s, s, s))
		_mm.set_instance_transform(k, Transform3D(b, q["pos"]))
		_mm.set_instance_color(k, q["col"])
	_mm.visible_instance_count = n
	if n == 0:
		set_process(false)
