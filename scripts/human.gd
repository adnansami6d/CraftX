extends RefCounted
# V31: a realistic-looking person built from simple shapes (no outline, soft lighting).
# Real proportions (about 7.5 heads tall): tapered arms and legs, elbows, knees, hands with fingers,
# real face (eyes with iris + pupil + eyelids, brows, nose, lips, cheeks, ears), neck, collar, hair, work boots.
# Feet at y = 0, 1.52 m tall (player.gd scales it to the final height), the face looks to -Z.
#
# Returns the joints that move:
#   arm_l, arm_r, leg_l, leg_r      swing joints (shoulder / hip) - same names as before
#   elbow_l, elbow_r, knee_l, knee_r  bend joints (new)
#   spine (chest twists / breathes), head
#
# Options (all optional) in the dictionary o:
#   skin, top, pants, boots, hair, eyes (iris colour)  - colours
#   sleeveless (true = bare arms), belt, pack, ponytail, bake (true = merge shapes into few meshes, faster on phones)

const Util = preload("res://scripts/util.gd")
const SPINE_Y := 0.88   # height of the waist joint (chest and head hang from it)
const HEAD_Y := 1.37    # height of the neck joint (head hangs from it)
const SK := 0.72        # skin roughness (a little sheen)

static var _mats := {}
static var _meshes := {}


static func _m(color: Color, rough: float = 0.85, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [color.to_html(false), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED if rough > 0.85 else BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_mats[key] = m
	return m


static func _sph(r: float) -> Mesh:
	var key := "s%s" % r
	if not _meshes.has(key):
		if r < 0.02:
			_meshes[key] = Util.sphere(r, 10, 5)
		else:
			_meshes[key] = Util.sphere(r, 16, 8)
	return _meshes[key]


static func _cap(r: float, h: float) -> Mesh:
	var key := "c%s_%s" % [r, h]
	if not _meshes.has(key):
		var c := CapsuleMesh.new()
		c.radius = r
		c.height = maxf(h, r * 2.0 + 0.001)
		c.radial_segments = 12
		c.rings = 4
		_meshes[key] = c
	return _meshes[key]


static func _cyl(r: float, h: float) -> Mesh:
	var key := "y%s_%s" % [r, h]
	if not _meshes.has(key):
		_meshes[key] = Util.cyl(r, h, 18)
	return _meshes[key]


# cylinder that is wider at the top (rt) than at the bottom (rb): limbs, neck, boot shaft
static func _taper(rt: float, rb: float, h: float) -> Mesh:
	var key := "t%s_%s_%s" % [rt, rb, h]
	if not _meshes.has(key):
		var c := CylinderMesh.new()
		c.top_radius = rt
		c.bottom_radius = rb
		c.height = h
		c.radial_segments = 14
		c.rings = 1
		_meshes[key] = c
	return _meshes[key]


static func _box(x: float, y: float, z: float) -> Mesh:
	var key := "b%s_%s_%s" % [x, y, z]
	if not _meshes.has(key):
		_meshes[key] = Util.box(Vector3(x, y, z))
	return _meshes[key]


static func _torus(inner: float, outer: float) -> Mesh:
	var key := "o%s_%s" % [inner, outer]
	if not _meshes.has(key):
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 16
		t.ring_segments = 6
		_meshes[key] = t
	return _meshes[key]


static func _add(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, scl: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO, rough: float = 0.85, metal: float = 0.0) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = _m(color, rough, metal)
	n.position = pos
	n.scale = scl
	n.rotation_degrees = rot
	parent.add_child(n)
	return n


static func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j


# ------------------------------------------------------------------------------------------------
# arm: shoulder joint -> upper arm -> elbow joint -> forearm -> hand with 4 fingers + thumb
# side = -1 for the left arm (x < 0), +1 for the right arm. Returns [shoulder, elbow]
static func _make_arm(spine: Node3D, side: float, skin: Color, top: Color, sleeveless: bool) -> Array:
	var skin_d := skin.darkened(0.06)
	var skin_l := skin.lightened(0.05)
	var sh := _joint(spine, Vector3(side * 0.205, 1.2 - SPINE_Y, 0))
	var cloth := skin if sleeveless else top
	_add(sh, _sph(0.05), cloth, Vector3(0, -0.005, 0), Vector3(1.05, 1.1, 1.0), Vector3.ZERO, SK if sleeveless else 0.85)   # shoulder cap
	_add(sh, _taper(0.043, 0.034, 0.27), skin, Vector3(0, -0.145, 0), Vector3.ONE, Vector3.ZERO, SK)                     # upper arm
	_add(sh, _sph(0.034), skin_l, Vector3(0, -0.1, -0.008), Vector3(1.0, 1.6, 1.0), Vector3.ZERO, SK)                    # biceps
	if not sleeveless:
		_add(sh, _taper(0.049, 0.045, 0.15), top, Vector3(0, -0.085, 0), Vector3.ONE, Vector3.ZERO, 0.88)                # short sleeve
	var el := _joint(sh, Vector3(0, -0.28, 0))
	_add(el, _sph(0.034), skin, Vector3.ZERO, Vector3.ONE, Vector3.ZERO, SK)                                              # elbow
	_add(el, _taper(0.033, 0.021, 0.245), skin, Vector3(0, -0.125, 0), Vector3.ONE, Vector3.ZERO, SK)                    # forearm
	_add(el, _sph(0.03), skin_l, Vector3(0, -0.07, 0.002), Vector3(1.0, 1.7, 1.0), Vector3.ZERO, SK)                     # forearm muscle
	_add(el, _taper(0.022, 0.02, 0.03), skin_d, Vector3(0, -0.25, 0), Vector3.ONE, Vector3.ZERO, SK)                     # wrist
	# hand: the palm faces the leg, thumb to the front
	var inw: float = -side
	_add(el, _sph(0.04), skin, Vector3(0, -0.287, 0), Vector3(0.42, 1.1, 0.95), Vector3.ZERO, SK)                        # palm / back of hand
	var lens := [0.066, 0.074, 0.068, 0.055]
	var zs := [-0.027, -0.009, 0.009, 0.026]
	for i in 4:
		var L: float = lens[i]
		var l1 := L * 0.55
		var l2 := L * 0.45
		var a1 := 0.22 + 0.04 * i
		var a2 := a1 + 0.45
		var p0 := Vector3(0, -0.325, zs[i])
		var d1 := Vector3(inw * sin(a1), -cos(a1), 0)
		_add(el, _cap(0.0085, l1 + 0.017), skin, p0 + d1 * (l1 * 0.5), Vector3.ONE, Vector3(0, 0, rad_to_deg(inw * a1)), SK)
		var p1 := p0 + d1 * l1
		var d2 := Vector3(inw * sin(a2), -cos(a2), 0)
		_add(el, _cap(0.0075, l2 + 0.015), skin, p1 + d2 * (l2 * 0.5), Vector3.ONE, Vector3(0, 0, rad_to_deg(inw * a2)), SK)
	_add(el, _cap(0.0095, 0.058), skin, Vector3(inw * 0.006, -0.292, -0.043), Vector3.ONE, Vector3(28, 0, inw * 10.0), SK)   # thumb
	return [sh, el]


# leg: hip joint -> thigh -> knee joint -> shin -> work boot. Returns [hip, knee]
static func _make_leg(model: Node3D, side: float, pants: Color, boots: Color, sole: Color) -> Array:
	var hip := _joint(model, Vector3(side * 0.08, 0.78, 0))
	_add(hip, _taper(0.076, 0.056, 0.39), pants, Vector3(0, -0.19, 0), Vector3.ONE, Vector3.ZERO, 0.9)                    # thigh
	_add(hip, _sph(0.06), pants, Vector3(0, -0.13, -0.01), Vector3(1.0, 1.9, 0.95), Vector3.ZERO, 0.9)                    # thigh muscle
	var kn := _joint(hip, Vector3(0, -0.38, 0))
	_add(kn, _sph(0.054), pants, Vector3.ZERO, Vector3.ONE, Vector3.ZERO, 0.9)                                             # knee
	_add(kn, _taper(0.053, 0.04, 0.33), pants, Vector3(0, -0.165, 0), Vector3.ONE, Vector3.ZERO, 0.9)                     # shin
	_add(kn, _sph(0.045), pants, Vector3(0, -0.08, 0.018), Vector3(1.0, 1.7, 1.0), Vector3.ZERO, 0.9)                     # calf
	_add(kn, _taper(0.044, 0.05, 0.07), pants, Vector3(0, -0.255, 0), Vector3.ONE, Vector3.ZERO, 0.9)                     # trouser hem
	# boot: shaft, foot, toe cap, sole, heel
	_add(kn, _taper(0.047, 0.05, 0.12), boots, Vector3(0, -0.31, 0.002), Vector3.ONE, Vector3.ZERO, 0.6)
	_add(kn, _sph(0.05), boots, Vector3(0, -0.36, -0.055), Vector3(0.95, 0.8, 2.3), Vector3.ZERO, 0.6)
	_add(kn, _sph(0.04), boots.darkened(0.15), Vector3(0, -0.372, -0.125), Vector3(1.0, 0.75, 1.2), Vector3.ZERO, 0.55)
	_add(kn, _box(0.098, 0.028, 0.25), sole, Vector3(0, -0.386, -0.055), Vector3.ONE, Vector3.ZERO, 0.95)
	_add(kn, _box(0.08, 0.03, 0.07), sole, Vector3(0, -0.385, 0.032), Vector3.ONE, Vector3.ZERO, 0.95)
	return [hip, kn]


# ------------------------------------------------------------------------------------------------
static func build(model: Node3D, o: Dictionary) -> Dictionary:
	var skin: Color = o.get("skin", Color(0.88, 0.68, 0.55))
	var top: Color = o.get("top", Color(0.09, 0.09, 0.11))
	var pants: Color = o.get("pants", Color(0.14, 0.14, 0.16))
	var boots: Color = o.get("boots", Color(0.25, 0.17, 0.11))
	var hair: Color = o.get("hair", Color(0.3, 0.19, 0.1))
	var iris: Color = o.get("eyes", Color(0.28, 0.17, 0.09))
	var sleeveless: bool = o.get("sleeveless", true)
	var ponytail: bool = o.get("ponytail", true)
	var skin_d := skin.darkened(0.08)
	var skin_l := skin.lightened(0.04)
	var blush := skin.lerp(Color(0.85, 0.35, 0.33), 0.14)
	var lip := skin.lerp(Color(0.62, 0.2, 0.22), 0.5)
	var shirt_d := top.darkened(0.2)
	var sole := Color(0.07, 0.065, 0.06)
	var y0 := SPINE_Y

	# ---- pelvis, hips, belt (they stay still; the legs swing from their own joints)
	_add(model, _sph(0.1), pants, Vector3(0, 0.82, 0), Vector3(1.6, 0.9, 1.0), Vector3.ZERO, 0.9)
	for sx in [-1.0, 1.0]:
		var gx: float = sx * 0.045
		_add(model, _sph(0.058), pants, Vector3(gx, 0.79, 0.05), Vector3(1.0, 1.15, 0.95), Vector3.ZERO, 0.9)
	if o.get("belt", true):
		_add(model, _cyl(0.11, 0.03), Color(0.12, 0.09, 0.07), Vector3(0, 0.862, 0), Vector3(1.4, 1.0, 0.88), Vector3.ZERO, 0.6)
		_add(model, _box(0.04, 0.026, 0.008), Color(0.85, 0.7, 0.3), Vector3(0, 0.862, -0.098), Vector3.ONE, Vector3.ZERO, 0.35, 0.8)

	# ---- chest (hangs from the spine joint: it can twist and breathe)
	var spine := _joint(model, Vector3(0, y0, 0))
	_add(spine, _cap(0.092, 0.3), top, Vector3(0, 0.98 - y0, 0), Vector3(1.5, 1.0, 0.88), Vector3.ZERO, 0.88)              # waist / belly
	_add(spine, _sph(0.115), top, Vector3(0, 1.12 - y0, 0), Vector3(1.55, 1.1, 0.88), Vector3.ZERO, 0.88)                   # rib cage
	_add(spine, _sph(0.1), top, Vector3(0, 1.215 - y0, 0), Vector3(1.7 if sleeveless else 2.0, 0.55, 0.85), Vector3.ZERO, 0.88)   # shoulder line
	_add(spine, _sph(0.1), top, Vector3(0, 0.885 - y0, 0), Vector3(1.5, 0.45, 0.9), Vector3.ZERO, 0.88)                    # shirt hem
	_add(spine, _torus(0.034, 0.05), shirt_d, Vector3(0, 1.268 - y0, 0.004), Vector3(1.0, 0.9, 1.1), Vector3.ZERO, 0.88)   # collar
	_add(spine, _taper(0.037, 0.043, 0.1), skin_d, Vector3(0, 1.31 - y0, 0), Vector3.ONE, Vector3.ZERO, SK)                 # neck
	if o.get("pack", false):
		var pk := Color(0.22, 0.25, 0.17)
		_add(spine, _box(0.26, 0.32, 0.11), pk, Vector3(0, 1.08 - y0, 0.14), Vector3.ONE, Vector3.ZERO, 0.9)
		_add(spine, _box(0.24, 0.09, 0.12), pk.darkened(0.12), Vector3(0, 1.21 - y0, 0.14), Vector3.ONE, Vector3.ZERO, 0.9)
		for sx in [-1.0, 1.0]:
			var px: float = sx * 0.07
			_add(spine, _box(0.035, 0.012, 0.17), pk.darkened(0.2), Vector3(px, 1.268 - y0, 0.0), Vector3.ONE, Vector3.ZERO, 0.9)
			_add(spine, _box(0.035, 0.22, 0.012), pk.darkened(0.2), Vector3(px, 1.12 - y0, -0.094), Vector3.ONE, Vector3.ZERO, 0.9)

	# ---- arms and legs
	var al: Array = _make_arm(spine, -1.0, skin, top, sleeveless)
	var ar: Array = _make_arm(spine, 1.0, skin, top, sleeveless)
	var ll: Array = _make_leg(model, -1.0, pants, boots, sole)
	var lr: Array = _make_leg(model, 1.0, pants, boots, sole)

	# ---- head (positions below are relative to the neck joint)
	var head := _joint(spine, Vector3(0, HEAD_Y - y0, 0))
	_add(head, _sph(0.1), skin, Vector3(0, 0.05, 0.005), Vector3(0.9, 1.1, 1.0), Vector3.ZERO, SK)                          # skull
	_add(head, _sph(0.085), skin, Vector3(0, -0.008, -0.012), Vector3(0.9, 1.0, 0.95), Vector3.ZERO, SK)                    # lower face
	_add(head, _sph(0.04), skin, Vector3(0, -0.05, -0.055), Vector3(1.5, 0.75, 1.0), Vector3.ZERO, SK)                      # jaw + chin
	_add(head, _sph(0.03), skin, Vector3(0, 0.075, -0.083), Vector3(2.2, 0.35, 0.7), Vector3.ZERO, SK)                      # brow bone
	for sx in [-1.0, 1.0]:
		var s: float = sx
		var ex: float = s * 0.037
		_add(head, _sph(0.026), blush, Vector3(s * 0.05, 0.0, -0.068), Vector3(1.0, 0.8, 0.55), Vector3.ZERO, SK)           # cheek
		_add(head, _sph(0.02), skin, Vector3(s * 0.0915, 0.04, 0.004), Vector3(0.45, 1.2, 0.8), Vector3.ZERO, SK)           # ear
		_add(head, _sph(0.012), skin.darkened(0.12), Vector3(s * 0.0935, 0.04, 0.0), Vector3(0.4, 1.0, 0.7), Vector3.ZERO, SK)   # inner ear
		# eye: white, iris, pupil, shine, upper lid, lash line
		_add(head, _sph(0.0125), Color(0.96, 0.94, 0.92), Vector3(ex, 0.055, -0.082), Vector3(1.2, 0.8, 0.7), Vector3.ZERO, 0.25)
		_add(head, _sph(0.0075), iris, Vector3(ex, 0.055, -0.0885), Vector3(1.0, 1.0, 0.4), Vector3.ZERO, 0.3)
		_add(head, _sph(0.0038), Color(0.02, 0.02, 0.02), Vector3(ex, 0.055, -0.0905), Vector3(1.0, 1.0, 0.4), Vector3.ZERO, 0.3)
		_add(head, _sph(0.0018), Color(1, 1, 1), Vector3(ex + 0.0025, 0.0595, -0.0925), Vector3(1.0, 1.0, 0.6), Vector3.ZERO, 0.1)
		_add(head, _sph(0.0135), skin_d, Vector3(ex, 0.0645, -0.0835), Vector3(1.25, 0.5, 0.8), Vector3.ZERO, SK)
		_add(head, _box(0.027, 0.0025, 0.004), Color(0.05, 0.04, 0.04), Vector3(ex, 0.0583, -0.091), Vector3.ONE, Vector3.ZERO, 0.6)
		# eyebrow: two pieces, arched
		var bc := hair.darkened(0.25)
		_add(head, _box(0.024, 0.008, 0.008), bc, Vector3(s * 0.028, 0.083, -0.0865), Vector3.ONE, Vector3(0, 0, s * 8.0), 0.7)
		_add(head, _box(0.024, 0.008, 0.008), bc, Vector3(s * 0.05, 0.085, -0.0835), Vector3.ONE, Vector3(0, 0, -s * 14.0), 0.7)
		_add(head, _sph(0.0085), skin.darkened(0.03), Vector3(s * 0.0125, 0.012, -0.0955), Vector3(1.0, 0.9, 0.9), Vector3.ZERO, SK)   # nostril wing
		_add(head, _sph(0.0035), Color(0.12, 0.06, 0.05), Vector3(s * 0.0065, 0.004, -0.1), Vector3(1.0, 1.4, 0.6), Vector3.ZERO, 0.9)   # nostril
	# nose
	_add(head, _sph(0.011), skin, Vector3(0, 0.032, -0.0945), Vector3(0.75, 2.0, 1.0), Vector3(12, 0, 0), SK)               # bridge
	_add(head, _sph(0.0135), skin, Vector3(0, 0.011, -0.1035), Vector3(1.0, 0.85, 1.0), Vector3.ZERO, SK)                  # tip
	# mouth
	_add(head, _sph(0.011), lip, Vector3(0, -0.0235, -0.0885), Vector3(2.1, 0.42, 0.7), Vector3.ZERO, 0.5)                 # upper lip
	_add(head, _sph(0.012), lip, Vector3(0, -0.0345, -0.0875), Vector3(1.9, 0.5, 0.8), Vector3.ZERO, 0.45)                 # lower lip
	_add(head, _box(0.034, 0.0025, 0.006), lip.darkened(0.45), Vector3(0, -0.0285, -0.0905), Vector3.ONE, Vector3.ZERO, 0.8)   # mouth line

	# ---- hair: top + back, fringe, sideburns, ponytail
	_add(head, _sph(0.108), hair, Vector3(0, 0.085, 0.03), Vector3(0.98, 1.0, 1.04), Vector3.ZERO, 0.55)
	_add(head, _sph(0.1), hair, Vector3(0, 0.045, 0.03), Vector3(0.96, 1.05, 1.0), Vector3.ZERO, 0.55)
	_add(head, _sph(0.05), hair, Vector3(0, 0.118, -0.045), Vector3(1.8, 0.42, 0.85), Vector3(-12, 0, 0), 0.55)
	for sx in [-1.0, 1.0]:
		var hx: float = sx * 0.079
		_add(head, _box(0.012, 0.045, 0.014), hair, Vector3(hx, 0.08, -0.05), Vector3.ONE, Vector3.ZERO, 0.55)
	if ponytail:
		_add(head, _sph(0.02), hair.darkened(0.45), Vector3(0, 0.03, 0.125), Vector3.ONE, Vector3.ZERO, 0.6)
		_add(head, _cap(0.026, 0.19), hair, Vector3(0, -0.058, 0.144), Vector3(1.0, 1.0, 1.0), Vector3(-12, 0, 0), 0.55)

	if o.get("bake", true):
		Util.bake(model)

	return {
		"arm_l": al[0], "elbow_l": al[1], "arm_r": ar[0], "elbow_r": ar[1],
		"leg_l": ll[0], "knee_l": ll[1], "leg_r": lr[0], "knee_r": lr[1],
		"spine": spine, "head": head,
	}
