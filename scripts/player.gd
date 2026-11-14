extends CharacterBody3D
# The character. Height = 5 ft = 1.524 m.
# Built-in body is a placeholder. use_model(node) swaps in your own character.
# main.gd sets move_dir (joystick) and cam_yaw (camera) every frame.

const Util = preload("res://scripts/util.gd")
const Human = preload("res://scripts/human.gd")
const RigAnim = preload("res://scripts/rig_anim.gd")
const Sfx = preload("res://scripts/sfx.gd")
const AudioLib = preload("res://scripts/audio_lib.gd")
const HEIGHT := 1.524
const WALK_SPEED := 3.0 * Util.CHAR_SCALE
const RUN_SPEED := 6.5 * Util.CHAR_SCALE
const JUMP_SPEED := 7.0   # 1.2 m high: enough to climb a 1 m block
const GRAVITY := 20.0
const CUSTOM_MODEL_TURN_DEG := 180.0   # glb models usually face +Z; change to 0 if yours walks backwards

var move_dir := Vector2.ZERO
var cam_yaw := 0.0
var running := false

var model: Node3D
var pivot: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var elbow_l: Node3D   # V31: bend joints + chest + head of the realistic body
var elbow_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var spine: Node3D
var head: Node3D
var idle_t := 0.0
var gun_kind := -1     # set by shooter.gd: -1 = no weapon, 0 = pistol, 1 = rifle
var gun: Node3D        # the weapon shown in the hands (built from boxes)
var gun_pistol: Node3D
var gun_rifle: Node3D
var gun_amt := 0.0     # 0 = carried low, 1 = raised to aim
var rig                # code-driven skeleton animation for a glb character without animation clips
var model_scale := 1.0
var anim: AnimationPlayer
var anim_t := 0.0
var was_on_floor := true
var squash := 0.0
var seated := false
var aiming := false   # shooter.gd: facing the camera direction with the gun up

# --- sounds (your files in res://audio/walk, run, jump, land; empty folder = default sound from sfx.gd)
const STEP_EVERY_WALK := 0.52   # seconds between two steps
const STEP_EVERY_RUN := 0.34
var _snd_step: AudioStreamPlayer
var _snd_jump: AudioStreamPlayer
var _snd_land: AudioStreamPlayer
var _walk_sounds: Array = []
var _run_sounds: Array = []
var _step_t := 0.0
var _air_t := 0.0
var _step_last := -1


func _ready() -> void:
	add_to_group("player")
	_setup_sound()
	collision_mask = 3   # 1 = things (trees, walls, tractor), 2 = the ground
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25 * Util.CHAR_SCALE
	cap.height = HEIGHT * Util.CHAR_SCALE
	cs.shape = cap
	add_child(cs)

	pivot = Node3D.new()
	pivot.scale = Vector3.ONE * Util.CHAR_SCALE
	add_child(pivot)
	model = Node3D.new()
	model.position = Vector3(0, -HEIGHT / 2.0, 0)   # feet at the bottom of the capsule
	pivot.add_child(model)
	_build_placeholder()
	_build_gun()


func _build_placeholder() -> void:
	var parts: Dictionary = Human.build(model, {"top": Color(0.09, 0.09, 0.11), "pants": Color(0.14, 0.14, 0.16), "boots": Color(0.25, 0.17, 0.11), "hair": Color(0.3, 0.19, 0.1), "sleeveless": true, "pack": true})
	arm_l = parts["arm_l"]
	arm_r = parts["arm_r"]
	leg_l = parts["leg_l"]
	leg_r = parts["leg_r"]
	elbow_l = parts.get("elbow_l")
	elbow_r = parts.get("elbow_r")
	knee_l = parts.get("knee_l")
	knee_r = parts.get("knee_r")
	spine = parts.get("spine")
	head = parts.get("head")


# The weapon in the hands: simple boxes, grip at the node origin, the muzzle looks to -Z (character model space).
func _build_gun() -> void:
	# NOT inside 'model': use_model() deletes everything inside model when a glb character is loaded
	var holder := Node3D.new()
	holder.position = Vector3(0, -HEIGHT / 2.0, 0)   # same place as 'model': feet at the bottom of the capsule
	pivot.add_child(holder)
	gun = Node3D.new()
	gun.visible = false
	holder.add_child(gun)
	var dark := Util.mat(Color(0.12, 0.12, 0.14), 0.6, 0.3)
	var wood := Util.mat(Color(0.28, 0.2, 0.12), 0.8)
	gun_pistol = Node3D.new()
	gun.add_child(gun_pistol)
	Util.part(gun_pistol, Vector3(0.045, 0.05, 0.22), Vector3(0, 0.03, -0.08), dark)
	Util.part(gun_pistol, Vector3(0.04, 0.11, 0.05), Vector3(0, -0.04, 0.02), dark, Vector3(15, 0, 0))
	gun_rifle = Node3D.new()
	gun.add_child(gun_rifle)
	Util.part(gun_rifle, Vector3(0.05, 0.08, 0.5), Vector3(0, 0.03, -0.2), dark)
	Util.part(gun_rifle, Vector3(0.025, 0.025, 0.35), Vector3(0, 0.04, -0.62), dark)
	Util.part(gun_rifle, Vector3(0.05, 0.12, 0.22), Vector3(0, -0.01, 0.22), wood, Vector3(-8, 0, 0))
	Util.part(gun_rifle, Vector3(0.04, 0.11, 0.05), Vector3(0, -0.07, 0.03), dark, Vector3(15, 0, 0))
	Util.part(gun_rifle, Vector3(0.03, 0.12, 0.05), Vector3(0, -0.07, -0.25), dark)


# v_012: weapon poses (model space: feet y = 0, the body looks to -Z, +X = right). Each pose = [grip position, pitch in degrees (+ = muzzle up)].
# Checked against the real arm length of the character (reach 0.51 m from the shoulder): every hand point stays within about 0.5 m.
#   carry = while running (low, close to the body)   ready = standing / walking (in front of the chest)   aim = firing (raised, arms forward)
const GUN_POSES := {
	0: {"carry": [Vector3(0.05, 1.16, -0.24), -20.0], "ready": [Vector3(0.03, 1.24, -0.30), 0.0], "aim": [Vector3(0.03, 1.40, -0.36), 0.0],
		"hand_r": Vector3(0.01, -0.09, 0.10), "hand_l": Vector3(-0.045, -0.10, 0.10)},       # pistol: both hands on the grip
	1: {"carry": [Vector3(0.10, 1.18, -0.04), 40.0], "ready": [Vector3(0.10, 1.26, -0.08), 22.0], "aim": [Vector3(0.09, 1.36, -0.06), 0.0],
		"hand_r": Vector3(0.02, -0.10, 0.10), "hand_l": Vector3(0.0, -0.10, -0.19)},         # rifle: right on the grip, left on the fore grip
}
var _gun_low := 0.0     # 0..1 carry pose (running)


func _update_gun(delta: float) -> void:
	if gun == null:
		return
	var visible_now := gun_kind >= 0 and not seated
	gun.visible = visible_now
	if not visible_now:
		return
	gun_pistol.visible = gun_kind == 0
	gun_rifle.visible = gun_kind != 0
	var moving_fast := running and Vector2(velocity.x, velocity.z).length() > 1.0
	gun_amt = lerpf(gun_amt, 1.0 if aiming else 0.0, minf(14.0 * delta, 1.0))
	_gun_low = lerpf(_gun_low, 1.0 if (moving_fast and not aiming) else 0.0, minf(8.0 * delta, 1.0))
	var pz: Dictionary = GUN_POSES[1 if gun_kind != 0 else 0]
	var rdy: Array = pz["ready"]
	var carry: Array = pz["carry"]
	var aim: Array = pz["aim"]
	var pos: Vector3 = (rdy[0] as Vector3).lerp(carry[0], _gun_low).lerp(aim[0], gun_amt)
	var pitch: float = lerpf(lerpf(float(rdy[1]), float(carry[1]), _gun_low), float(aim[1]), gun_amt)
	var t := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(pitch)), pos)
	if rig != null:
		t = rig.chest_xform(t)   # the weapon follows the chest (lean, twist, bob)
	gun.transform = t
	if rig != null:
		# both hands on the weapon (rig_anim.gd two-bone arm IK)
		var gr: Vector3 = gun.transform * (pz["hand_r"] as Vector3)
		var gl: Vector3 = gun.transform * (pz["hand_l"] as Vector3)
		rig.set_hands(gl, gr, 1.0)


# a limb = a joint node at the top; the box hangs below it, so rotating the joint swings the limb
func _limb(pos: Vector3, size: Vector3, color: Color) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	var part := Util.mi(Util.box(size), color)
	part.position = Vector3(0, -size.y / 2.0, 0)
	j.add_child(part)
	model.add_child(j)
	return j


# Swap the placeholder for your own character (call after the player is in the scene).
func use_model(node: Node3D) -> void:
	for c in model.get_children():
		c.queue_free()
	arm_l = null
	arm_r = null
	leg_l = null
	leg_r = null
	elbow_l = null
	elbow_r = null
	knee_l = null
	knee_r = null
	spine = null
	head = null
	model.add_child(node)
	rig = null

	var box := _model_aabb(node)
	if box.size.y > 0.001:
		var s := HEIGHT / box.size.y
		node.scale = Vector3.ONE * s
		model_scale = s
		node.position.y = -box.position.y * s
	node.rotation_degrees.y = CUSTOM_MODEL_TURN_DEG

	var aps := node.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		anim = aps[0]
	# V31: no usable animation clips in the file -> move the skeleton from code (rig_anim.gd)
	if anim == null or not anim.has_animation("walk"):
		var r := RigAnim.new()
		if r.setup(node):
			rig = r
		else:
			push_warning("Character has no usable skeleton, it will not animate.")


func _model_aabb(root: Node3D) -> AABB:
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	var box := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for m in meshes:
		var xf: Transform3D = inv * m.global_transform
		var b: AABB = xf * m.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


# Sit on a seat marker (tractor). Character stays visible; physics off while seated.
func sit(seat: Node3D) -> void:
	seated = true
	running = false
	if gun != null:
		gun.visible = false
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	reparent(seat, false)
	position = Vector3.ZERO
	reset_physics_interpolation()
	rotation = Vector3.ZERO
	pivot.rotation = Vector3.ZERO
	pivot.scale = Vector3.ONE
	model.rotation = Vector3.ZERO
	model.scale = Vector3.ONE
	model.position.y = -HEIGHT / 2.0
	if arm_l != null:
		# V31: sit like a person: thighs forward, shins down, hands forward on the wheel
		arm_l.rotation = Vector3(1.0, 0.0, -0.12)
		arm_r.rotation = Vector3(1.0, 0.0, 0.12)
		leg_l.rotation = Vector3(1.45, 0.0, 0.0)
		leg_r.rotation = Vector3(1.45, 0.0, 0.0)
		if elbow_l != null:
			elbow_l.rotation.x = 0.9
			elbow_r.rotation.x = 0.9
			knee_l.rotation.x = -1.45
			knee_r.rotation.x = -1.45
			spine.rotation = Vector3.ZERO
			spine.scale = Vector3.ONE
			head.rotation = Vector3.ZERO
	elif rig != null:
		rig.clear_hands()   # no weapon hold while seated
		# seated: hips down to the seat, thighs forward, hands forward
		var drop := maxf(0.0, rig.hips_height() * model_scale - 0.77) / maxf(model_scale, 0.001)
		rig.apply([1.0, 1.0, 1.45, 1.45, 0.9, 0.9, -1.45, -1.45, 0.12, 0.0, 0.0, 0.0, 0.0, 0.0, drop], 1.0)
	elif anim != null and anim.has_animation("sit"):
		anim.play("sit")


func stand(world: Node, pos: Vector3) -> void:
	reparent(world, false)
	global_position = pos
	reset_physics_interpolation()
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	collision_layer = 1
	collision_mask = 3
	pivot.scale = Vector3.ONE * Util.CHAR_SCALE
	seated = false
	set_physics_process(true)


func jump() -> void:
	if is_on_floor():
		velocity.y = JUMP_SPEED
		_snd_jump.play()


func _player(db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = db
	add_child(p)
	return p


func _setup_sound() -> void:
	_walk_sounds = AudioLib.custom_streams("walk")
	_run_sounds = AudioLib.custom_streams("run")
	if _walk_sounds.is_empty():
		for i in 4:
			_walk_sounds.append(Sfx.footstep(i + 1))
	if _run_sounds.is_empty():
		_run_sounds = _walk_sounds   # no run sounds: the walk sounds are played faster
	_snd_step = _player(-6.0)
	_snd_jump = _player(-8.0)
	var jc := AudioLib.custom_streams("jump")
	_snd_jump.stream = jc[0] if not jc.is_empty() else Sfx.jump()
	_snd_land = _player(-4.0)
	var lc := AudioLib.custom_streams("land")
	_snd_land.stream = lc[0] if not lc.is_empty() else Sfx.land()


# one step every STEP_EVERY_x seconds while walking / running on the ground
func _footsteps(delta: float, moving: bool) -> void:
	if not is_on_floor():
		_air_t += delta
		_step_t = 0.0
		return
	var flat := Vector2(velocity.x, velocity.z).length()
	if not moving or flat < 0.5:
		_step_t = 0.0
		return
	_step_t += delta
	if _step_t < (STEP_EVERY_RUN if running else STEP_EVERY_WALK):
		return
	_step_t = 0.0
	var list: Array = _run_sounds if running else _walk_sounds
	var i := randi() % list.size()
	if list.size() > 1 and i == _step_last:   # never the same sound twice in a row
		i = (i + 1) % list.size()
	_step_last = i
	_snd_step.stream = list[i]
	_snd_step.pitch_scale = randf_range(0.93, 1.07) * (1.12 if running and _run_sounds == _walk_sounds else 1.0)
	_snd_step.volume_db = -3.0 if running else -6.0
	_snd_step.play()


# Run: tap once = keeps running in the camera direction. Tap again = stop.
func toggle_run() -> void:
	running = not running


func _physics_process(delta: float) -> void:
	var dir := move_dir
	var kb := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if kb != Vector2.ZERO:
		dir = kb
	if Input.is_action_just_pressed("ui_accept"):
		jump()

	# V29: touching the joystick while auto-running stops the run (walk with the stick)
	if running and move_dir.length() > 0.1:
		running = false
	# auto-run: no joystick -> go straight ahead (the way the camera looks)
	if running and dir.length() < 0.1:
		dir = Vector2(0, -1)

	var moving := dir.length() > 0.1
	var speed := RUN_SPEED if running else WALK_SPEED
	var wd := Vector3(dir.x, 0, dir.y).rotated(Vector3.UP, cam_yaw)
	var v := velocity
	v.x = wd.x * speed
	v.z = wd.z * speed
	if is_on_floor() and v.y <= 0.0:
		v.y = 0.0
	else:
		v.y -= GRAVITY * delta
	velocity = v
	move_and_slide()
	_footsteps(delta, moving)

	if aiming:
		pivot.rotation.y = lerp_angle(pivot.rotation.y, cam_yaw, 18.0 * delta)
	elif moving:
		var target := atan2(-wd.x, -wd.z)
		pivot.rotation.y = lerp_angle(pivot.rotation.y, target, 12.0 * delta)

	_animate(delta, dir)


func _animate(delta: float, dir: Vector2) -> void:
	var on_floor := is_on_floor()

	if arm_l == null and rig == null:
		# custom model: play its animations if it has them
		if anim != null:
			var want := "idle"
			if not on_floor:
				want = "jump"
			elif dir.length() > 0.1:
				want = "run" if running else "walk"
			if anim.has_animation(want) and anim.current_animation != want:
				anim.play(want)
	else:
		var al := 0.0
		var ar := 0.0
		var ll := 0.0
		var lr := 0.0
		var el := 0.15      # elbow bend (positive = forearm goes forward)
		var er := 0.15
		var kl := -0.04     # knee bend (negative = shin goes back)
		var kr := -0.04
		var out := 0.06     # arms a little away from the body
		var lean := 0.0
		var bob := 0.0
		var twist := 0.0
		var breath := 0.0
		var ground := 1.0
		if not on_floor:
			# jump pose: arms up and forward, one knee up, the other leg trailing
			al = 2.0
			ar = 1.7
			ll = 0.8
			lr = -0.35
			el = 0.5
			er = 0.4
			kl = -1.3
			kr = -0.7
			out = 0.3
			ground = 0.0
		else:
			var sp := minf(dir.length(), 1.0)
			anim_t += delta * (14.0 if running else 9.0) * sp
			idle_t += delta
			var amp := (1.1 if running else 0.7) * sp
			var swing := sin(anim_t) * amp
			var c := cos(anim_t)
			al = swing
			ar = -swing
			ll = -swing
			lr = swing
			# knees bend while the leg swings forward, elbows bend more when running
			var kmax := (1.7 if running else 0.95) * sp
			kl = -0.04 - maxf(0.0, -c) * kmax
			kr = -0.04 - maxf(0.0, c) * kmax
			var ebase := lerpf(0.15, 1.3 if running else 0.35, sp)
			el = ebase + maxf(0.0, c) * 0.3 * sp
			er = ebase + maxf(0.0, -c) * 0.3 * sp
			out = 0.06 + 0.04 * sp
			bob = absf(sin(anim_t)) * (0.028 if running else 0.016) * sp
			twist = swing * 0.18
			breath = sin(idle_t * 2.2) * 0.012 * (1.0 - sp)
			if running and sp > 0.1:
				lean = -0.18   # lean forward
		if aiming and arm_l != null:
			ar = 1.45
			al = 1.1
			er = 0.3
			el = 0.5
		var k := minf(20.0 * delta, 1.0)
		if arm_l == null:
			if gun == null or not gun.visible:
				rig.set_hands(Vector3.ZERO, Vector3.ZERO, 0.0)
			rig.apply([al, ar, ll, lr, el, er, kl, kr, out, lean, twist, bob, breath, ground, 0.0], k)
		else:
			arm_l.rotation.x = lerpf(arm_l.rotation.x, al, k)
			arm_r.rotation.x = lerpf(arm_r.rotation.x, ar, k)
			arm_l.rotation.z = lerpf(arm_l.rotation.z, -out, k)
			arm_r.rotation.z = lerpf(arm_r.rotation.z, out, k)
			leg_l.rotation.x = lerpf(leg_l.rotation.x, ll, k)
			leg_r.rotation.x = lerpf(leg_r.rotation.x, lr, k)
			model.rotation.x = lerpf(model.rotation.x, lean, k)
			if elbow_l != null:
				elbow_l.rotation.x = lerpf(elbow_l.rotation.x, el, k)
				elbow_r.rotation.x = lerpf(elbow_r.rotation.x, er, k)
				knee_l.rotation.x = lerpf(knee_l.rotation.x, kl, k)
				knee_r.rotation.x = lerpf(knee_r.rotation.x, kr, k)
				spine.rotation.y = lerpf(spine.rotation.y, twist, k)
				spine.rotation.x = lerpf(spine.rotation.x, -lean * 0.5, k)   # chest straightens up a little when running
				spine.scale = Vector3(1.0 + breath * 0.5, 1.0 + breath, 1.0 + breath * 0.6)   # breathing
				head.rotation.y = lerpf(head.rotation.y, -twist * 0.7, k)   # head stays looking ahead
				head.rotation.x = lerpf(head.rotation.x, -lean * 0.5, k)   # eyes stay level
			model.position.y = -HEIGHT / 2.0 + bob

	_update_gun(delta)

	# landing squash
	if on_floor and not was_on_floor:
		squash = 0.15
		if _air_t > 0.25:   # a real jump / fall, not a small step down
			_snd_land.volume_db = lerpf(-10.0, 0.0, clampf(_air_t / 0.8, 0.0, 1.0))
			_snd_land.play()
	if on_floor:
		_air_t = 0.0
	was_on_floor = on_floor
	squash = lerpf(squash, 0.0, 12.0 * delta)
	model.scale.y = 1.0 - squash
