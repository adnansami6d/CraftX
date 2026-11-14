extends RefCounted
# V31: moves a Mixamo-style skeleton (Hips, Spine, LeftArm, LeftUpLeg ...) from code. No AnimationPlayer or animation files needed.
# Works with models in T-pose: every limb is given a direction in MODEL space, so the bone axes of the file do not matter.
# player.gd calls apply() every physics frame with the same numbers it uses for the built-in body:
#   p = [arm_l, arm_r, leg_l, leg_r, elbow_l, elbow_r, knee_l, knee_r, out, lean, twist, bob, breath, ground, extra_drop]
#   swing angles in radians: positive = forward. knee: negative = shin goes back. elbow: positive = forearm goes forward.
#   out = arms away from the body, lean = body lean (negative = forward), twist = chest twist,
#   ground = 1 on the floor / 0 in the air or seated, extra_drop = lower the hips (meters of the model, used when seated)

const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Pinky"]
const CURL := {"Thumb": 0.2, "Index": 0.45, "Middle": 0.55, "Ring": 0.65, "Pinky": 0.75}
const SEG := [0.4, 0.8, 0.5]   # how much each finger segment bends

# V34 hands on a held item (rifle): two-bone arm IK. Tune these three if the hands look turned the wrong way.
const HAND_ROLL_R := 1.5708    # turn of the right hand around the forearm (rad): palm toward the rifle (left)
const HAND_ROLL_L := -2.2      # left hand: palm up / toward the rifle (right), under the forend
const GRIP_CURL := 2.0         # how strongly the fingers close around the grip

var skel: Skeleton3D
var _idx := {}                      # bone name without the _NN number -> bone index
var _pm := {}                       # bone index -> rest position in model space
var _parent := PackedInt32Array()
var _order: Array = []              # bones, parents first
var _grest: Array = []              # global rest rotation of every bone (skeleton space)
var _gcur: Array = []
var _dtot: Array = []
var _rq := Quaternion.IDENTITY      # skeleton space -> model space
var _fwd := Vector3(0, 0, 1)        # the way the model faces
var _up := Vector3.UP
var _side := Vector3(-1, 0, 0)      # rotating about this axis by a positive angle swings a hanging limb forward
var _v0 := {}                       # rest direction of the arm bones (model space)
var _out := {}                      # "Left" / "Right" -> horizontal direction away from the body
var _leg_len := 0.8
var _hips_rest := Vector3.ZERO
var _hips_pinv := Basis.IDENTITY
var _unit := 1.0                    # model units per skeleton unit
var _spine2_scale := Vector3.ONE
var _root: Node3D                   # the loaded character (its transform inside the player's model)
var _hand_w := 0.0                  # 0 = normal arm animation ... 1 = hands on the rifle
var _hand_goal := 0.0
var _hand_l := Vector3.ZERO         # wanted wrist positions, in the rig's model space
var _hand_r := Vector3.ZERO
var _chain: Array = []              # v_012: bone indexes Spine, Spine1, Spine2 (the chest chain)
var _chain_q: Array = []            # their current rotations (model space), set every apply()
var _off_cur := Vector3.ZERO        # current hips offset (bob / drop), model space
var _p: Array = [0.0, 0.0, 0.0, 0.0, 0.15, 0.15, -0.04, -0.04, 0.06, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0]


static func _base(n: String) -> String:
	var s := n
	var c := s.find(":")
	if c >= 0:
		s = s.substr(c + 1)
	var u := s.rfind("_")
	if u > 0 and s.substr(u + 1).is_valid_int():
		s = s.substr(0, u)
	return s


func _dir(a: String, b: String) -> Vector3:
	var v: Vector3 = _pm[_idx[b]] - _pm[_idx[a]]
	return v.normalized()


func hips_height() -> float:
	return (_pm[_idx["Hips"]] as Vector3).y


# root = the loaded character scene (already inside the scene tree). Returns false if it has no usable skeleton.
func setup(root: Node3D) -> bool:
	var list := root.find_children("*", "Skeleton3D", true, false)
	if list.is_empty():
		return false
	skel = list[0]
	_root = root
	var n := skel.get_bone_count()
	if n < 20:
		return false
	for i in n:
		_idx[_base(skel.get_bone_name(i))] = i
	for need in ["Hips", "Spine", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftArm", "LeftForeArm", "LeftHand", "RightUpLeg", "RightLeg", "RightFoot", "RightArm", "RightForeArm", "RightHand"]:
		if not _idx.has(need):
			push_warning("RigAnim: bone missing: " + need)
			return false

	var t: Transform3D = root.global_transform.affine_inverse() * skel.global_transform
	_rq = t.basis.orthonormalized().get_rotation_quaternion()
	_unit = t.basis.get_scale().y
	if _unit < 0.000001:
		_unit = 1.0

	_parent.resize(n)
	_grest.resize(n)
	_gcur.resize(n)
	_dtot.resize(n)
	for i in n:
		_parent[i] = skel.get_bone_parent(i)
		var g: Transform3D = skel.get_bone_global_rest(i)
		_grest[i] = g.basis.orthonormalized().get_rotation_quaternion()
		_gcur[i] = _grest[i]
		_dtot[i] = Quaternion.IDENTITY
		_pm[i] = t * g.origin

	var done := {}
	var guard := 0
	while _order.size() < n and guard < n + 5:
		guard += 1
		for i in n:
			if done.has(i):
				continue
			var p: int = _parent[i]
			if p < 0 or done.has(p):
				_order.append(i)
				done[i] = true

	# which way is forward? from the heel to the toes (flat on the ground)
	_up = Vector3.UP
	_fwd = Vector3(0, 0, 1)
	if _idx.has("LeftToeBase"):
		var d: Vector3 = _pm[_idx["LeftToeBase"]] - _pm[_idx["LeftFoot"]]
		d.y = 0.0
		if d.length() > 0.01:
			_fwd = d.normalized()
	_side = _fwd.cross(_up).normalized()

	for s in ["Left", "Right"]:
		var v: Vector3 = _dir(s + "Arm", s + "ForeArm")
		_v0[s + "Arm"] = v
		var o := v
		o.y = 0.0
		_out[s] = o.normalized()
	_leg_len = maxf(0.3, (_pm[_idx["Hips"]] as Vector3).y - (_pm[_idx["LeftFoot"]] as Vector3).y)

	for cn in ["Spine", "Spine1", "Spine2"]:
		if _idx.has(cn):
			_chain.append(_idx[cn])
			_chain_q.append(Quaternion.IDENTITY)
	var hi: int = _idx["Hips"]
	_hips_rest = skel.get_bone_rest(hi).origin
	var hp: int = _parent[hi]
	if hp >= 0:
		_hips_pinv = skel.get_bone_global_rest(hp).basis.inverse()
	if _idx.has("Spine2"):
		_spine2_scale = skel.get_bone_rest(_idx["Spine2"]).basis.get_scale()
	return true


func _put(D: Dictionary, name: String, q: Quaternion) -> void:
	if _idx.has(name):
		D[_idx[name]] = q


func _leg(D: Dictionary, s: String, th: float, kn: float, ground: float) -> void:
	_put(D, s + "UpLeg", Quaternion(_side, th))
	_put(D, s + "Leg", Quaternion(_side, th + kn))
	var pitch := 0.0
	if ground > 0.5:
		pitch = -maxf(0.0, -th) * 0.6 + maxf(0.0, th) * 0.25   # toes push off behind, heel lands in front
	_put(D, s + "Foot", Quaternion(_side, pitch))


func _arm(D: Dictionary, s: String, sw: float, bend: float, out: float) -> void:
	var v0: Vector3 = _v0[s + "Arm"]
	var o: Vector3 = _out[s]
	var target := (-_up + o * sin(out)).normalized()
	var q_arm := Quaternion(_side, sw) * Quaternion(v0, target)    # T-pose -> arm hanging down, then swing
	var q_fore := Quaternion(_side, bend) * q_arm
	_put(D, s + "Arm", q_arm)
	_put(D, s + "ForeArm", q_fore)
	_put(D, s + "Hand", q_fore)
	# relaxed fingers (only while the arm hangs down)
	var f := clampf(cos(sw + bend), 0.0, 1.0)
	if f < 0.05:
		return
	var rt := _fwd.cross(-_up)
	var sgn := -1.0 if rt.dot(o) > 0.0 else 1.0
	for fn in FINGERS:
		var cur := q_fore
		for k in 3:
			cur = Quaternion(_fwd, sgn * float(CURL[fn]) * float(SEG[k]) * f) * cur
			_put(D, "%sHand%s%d" % [s, fn, k + 1], cur)


# l / r = wanted wrist positions in the player's model space (meters). goal 1 = hands on the item, 0 = normal arms.
func set_hands(l: Vector3, r: Vector3, goal: float) -> void:
	_hand_goal = goal
	if goal > 0.0 and _root != null:
		var inv: Transform3D = _root.transform.affine_inverse()
		_hand_l = inv * l
		_hand_r = inv * r


func clear_hands() -> void:
	_hand_goal = 0.0
	_hand_w = 0.0


# v_012: where a point of the upper body (rest position, rig space) is now, after the chest chain (Spine, Spine1, Spine2)
# has turned / leaned and the hips have moved. Used for the shoulders (IK) and to carry the weapon with the chest.
func _chest_point(p: Vector3, off: Vector3) -> Vector3:
	if _chain.is_empty():
		return p + off
	var joint: Vector3 = (_pm[_chain[0]] as Vector3) + off
	for k in range(1, _chain.size()):
		var a: int = _chain[k - 1]
		var b: int = _chain[k]
		joint = joint + (_chain_q[k - 1] as Quaternion) * ((_pm[b] as Vector3) - (_pm[a] as Vector3))
	var last: int = _chain[_chain.size() - 1]
	return joint + (_chain_q[_chain.size() - 1] as Quaternion) * (p - (_pm[last] as Vector3))


# v_012: moves a transform (player model space) together with the chest, so the weapon follows lean / twist / bob
func chest_xform(t: Transform3D) -> Transform3D:
	if _root == null or _chain.is_empty():
		return t
	var rt: Transform3D = _root.transform.affine_inverse() * t
	var origin := _chest_point(rt.origin, _off_cur)
	var q: Quaternion = _chain_q[_chain_q.size() - 1]
	return _root.transform * Transform3D(Basis(q) * rt.basis, origin)


# two-bone IK: shoulder -> elbow -> wrist reaches 'target' (rig space); elbow points down and a bit outward
func _hand_ik(D: Dictionary, s: String, target: Vector3, off: Vector3, w: float, roll: float) -> void:
	var ia: int = _idx[s + "Arm"]
	var S: Vector3 = _chest_point(_pm[ia], off)   # v_012: the shoulder where it really is now (not the T-pose spot)
	var E0: Vector3 = _pm[_idx[s + "ForeArm"]]
	var H0: Vector3 = _pm[_idx[s + "Hand"]]
	var la := ((E0 - (_pm[ia] as Vector3)) as Vector3).length()
	var lb := (H0 - E0).length()
	var to := target - S
	var d := clampf(to.length(), absf(la - lb) + 0.01, la + lb - 0.005)
	var u := to.normalized()
	var x := (la * la - lb * lb + d * d) / (2.0 * d)
	var h := sqrt(maxf(la * la - x * x, 0.0))
	var pole: Vector3 = -_up + (_out[s] as Vector3) * 0.5
	var nrm := pole - u * pole.dot(u)
	if nrm.length() < 0.001:
		nrm = -_up
	nrm = nrm.normalized()
	var E := S + u * x + nrm * h
	var W := S + u * d
	var dir_up := (E - S).normalized()
	var dir_fo := (W - E).normalized()
	var q_arm := Quaternion(_v0[s + "Arm"], dir_up)
	var q_fore := Quaternion((H0 - E0).normalized(), dir_fo)
	var q_roll := Quaternion(dir_fo, roll)
	var q_hand := q_roll * q_fore
	_blend(D, s + "Arm", q_arm, w)
	_blend(D, s + "ForeArm", q_fore, w)
	_blend(D, s + "Hand", q_hand, w)
	# fingers close around the grip: bend toward the palm side
	var palm: Vector3 = q_hand * (-_up)
	var axis := dir_fo.cross(palm)
	if axis.length() < 0.001:
		axis = _side
	axis = axis.normalized()
	for fn in FINGERS:
		var cur := q_hand
		for k in 3:
			cur = Quaternion(axis, float(CURL[fn]) * float(SEG[k]) * GRIP_CURL) * cur
			_blend(D, "%sHand%s%d" % [s, fn, k + 1], cur, w)


func _blend(D: Dictionary, name: String, q: Quaternion, w: float) -> void:
	if not _idx.has(name):
		return
	var i: int = _idx[name]
	var base: Quaternion = D[i] if D.has(i) else Quaternion.IDENTITY
	D[i] = base.slerp(q, w)


func apply(target: Array, k: float) -> void:
	if skel == null:
		return
	var kk := clampf(k, 0.0, 1.0)
	for i in _p.size():
		_p[i] = lerpf(float(_p[i]), float(target[i]), kk)
	var al: float = _p[0]
	var ar: float = _p[1]
	var ll: float = _p[2]
	var lr: float = _p[3]
	var el: float = _p[4]
	var er: float = _p[5]
	var kl: float = _p[6]
	var kr: float = _p[7]
	var out: float = _p[8]
	var lean: float = _p[9]
	var twist: float = _p[10]
	var bob: float = _p[11]
	var breath: float = _p[12]
	var ground: float = _p[13]
	var extra: float = _p[14]

	var D := {}
	# chest: a little twist and lean spread over the three spine bones; head stays level
	_put(D, "Spine", Quaternion(_up, twist * 0.35) * Quaternion(_side, lean * 0.45))
	_put(D, "Spine1", Quaternion(_up, twist * 0.7) * Quaternion(_side, lean * 0.9))
	_put(D, "Spine2", Quaternion(_up, twist) * Quaternion(_side, lean * 1.3))
	_put(D, "Head", Quaternion(_up, -twist * 0.8) * Quaternion(_side, -lean * 1.1))
	for ci in _chain.size():
		_chain_q[ci] = D.get(_chain[ci], Quaternion.IDENTITY)
	_leg(D, "Left", ll, kl, ground)
	_leg(D, "Right", lr, kr, ground)
	_arm(D, "Left", al, el, out)
	_arm(D, "Right", ar, er, out)

	var wide := maxf(absf(ll), absf(lr))
	var drop := minf(_leg_len * (1.0 - cos(wide)) * 0.5, 0.12) * ground
	var off_m := _up * (bob - drop - extra)
	_off_cur = off_m
	_hand_w = lerpf(_hand_w, _hand_goal, kk)
	if _hand_w > 0.002:
		var hw := smoothstep(0.0, 1.0, _hand_w)
		_hand_ik(D, "Left", _hand_l, off_m, hw, HAND_ROLL_L)
		_hand_ik(D, "Right", _hand_r, off_m, hw, HAND_ROLL_R)

	var rq_inv := _rq.inverse()
	for i in _order:
		var p: int = _parent[i]
		var d: Quaternion = Quaternion.IDENTITY
		if D.has(i):
			d = D[i]
		elif p >= 0:
			d = _dtot[p]
		_dtot[i] = d
		var g: Quaternion = (rq_inv * d * _rq) * (_grest[i] as Quaternion)
		_gcur[i] = g
		var loc: Quaternion = g
		if p >= 0:
			loc = (_gcur[p] as Quaternion).inverse() * g
		skel.set_bone_pose_rotation(i, loc.normalized())

	# hips: up and down while walking (the body sinks when the legs are wide apart), lower when seated
	var off_s: Vector3 = _hips_pinv * (rq_inv * off_m / _unit)
	skel.set_bone_pose_position(_idx["Hips"], _hips_rest + off_s)

	if _idx.has("Spine2"):
		skel.set_bone_pose_scale(_idx["Spine2"], _spine2_scale * Vector3(1.0 + breath * 0.5, 1.0 + breath, 1.0 + breath * 0.6))
