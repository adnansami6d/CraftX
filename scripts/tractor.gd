extends CharacterBody3D
# Arcade tractor. main.gd sets gas / brake / steer from the touch buttons.
# Brake: slows down; once stopped, holding brake = reverse.
#
# SPEED: the tractor itself is limited to MAX_KMH (60). When a machine is hooked on, the machine's own
# numbers decide (see scripts/implement.gd): transport_kmh while only hooked, work_kmh while WORK is ON.
# The lowest limit wins. If you are faster than the limit the tractor slows down by itself.
#
# ATTACHMENTS (plow etc.): any node in group "attachment" that has
#   - a child Marker3D named "Hitch"
#   - meta "side" = "rear" or "front"
# (scripts that extend implement.gd get all of this automatically.)
# Connected / disconnected MANUALLY with the ATTACH button (nothing connects by itself).

const Util = preload("res://scripts/util.gd")
const FuelD = preload("res://scripts/vehicle_data.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Lights = preload("res://scripts/vehicle_lights.gd")
const Cfg = preload("res://scripts/config.gd")
const AudioLib = preload("res://scripts/audio_lib.gd")
const MAX_KMH := 60.0
const MAX_FWD := MAX_KMH / 3.6      # m/s
const MAX_REV := 4.0
const ACCEL := 4.2
const BRAKE_FORCE := 16.0
const OVER_LIMIT_DECEL := 6.0       # how fast it slows down when above a machine's limit
const REV_ACCEL := 3.0
const DRAG := 3.0
const TURN := 1.8
const GRAVITY := 20.0
const ATTACH_RANGE := 2.5
# --- slopes (V2): the ground is a height grid, so the tractor reads the height under its 4 wheels
const SLOPE_G := 9.0            # how hard a slope pulls the tractor (m/s2 at 90 degrees). 0 = slopes do not change the speed
const DOWNHILL_BONUS := 0.4     # rolling downhill it may be this much faster than the speed limit
const MAX_CLIMB := 0.62         # radians (about 35 degrees): steeper than this it cannot drive up, it slides back
const WHEEL_FRONT_X := 0.92     # wheel positions (same numbers as _wheel() in _build_body)
const WHEEL_FRONT_Z := -1.3
const WHEEL_REAR_X := 1.05
const WHEEL_REAR_Z := 0.9

var fuel := FuelD.FUEL_TANK_TRACTOR   # liters
var fuel_cap := FuelD.FUEL_TANK_TRACTOR
var gas := false
var brake := false
var steer := 0.0
var speed := 0.0
var ground := Callable()   # (x, z) -> height of the ground. main.gd sets it with setup_ground()
var vy := 0.0              # up / down speed (m/s) - matters when the tractor flies over a hill top
var airborne := false

var seat: Marker3D
var _lights: Array = []
var _tail_mat: StandardMaterial3D
var _lens: StandardMaterial3D
var lights_on := false
var hitch_rear: Marker3D
var hitch_front: Marker3D
var slots := {}
var spinners: Array = []   # [node, radius]
var steerers: Array = []

# sounds (made from math in sfx.gd)
var snd_engine: AudioStreamPlayer
var snd_crash: AudioStreamPlayer
var engine_db := -14.0   # engine loudness when idling (-8 when you use your own engine file)
var was_hit := false
var crash_cd := 0.0


func _ready() -> void:
	add_to_group("tractor")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING   # no floor / wall logic: the ground is handled by _follow_ground()
	snd_engine = AudioStreamPlayer.new()
	var ec := AudioLib.custom_streams("engine")   # your file in audio/engine, or the default
	if not ec.is_empty():
		snd_engine.stream = AudioLib.looped(ec[0])
		engine_db = -8.0
	else:
		snd_engine.stream = Sfx.engine()
	snd_engine.volume_db = engine_db
	add_child(snd_engine)
	snd_crash = AudioStreamPlayer.new()
	var cc := AudioLib.custom_streams("crash")
	snd_crash.stream = cc[0] if not cc.is_empty() else Sfx.crash()
	add_child(snd_crash)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.0, 1.7, 3.8)
	cs.shape = sh
	cs.position = Vector3(0, 0.95, 0)
	add_child(cs)
	_build_body()


func _build_body() -> void:
	var green := Util.mat(Color(0.12, 0.52, 0.17), 0.4, 0.35)
	var green_dk := Util.mat(Color(0.08, 0.38, 0.12), 0.45, 0.3)
	var yellow := Util.mat(Color(0.95, 0.76, 0.1), 0.45, 0.2)
	var dark := Util.mat(Color(0.1, 0.1, 0.11), 0.6, 0.3)
	var steel := Util.mat(Color(0.4, 0.42, 0.46), 0.4, 0.7)
	var white := Util.mat(Color(0.93, 0.94, 0.92), 0.5)
	var glass := Util.mat(Color(0.55, 0.75, 0.9, 0.3), 0.1)
	var seat_m := Util.mat(Color(0.18, 0.2, 0.28), 0.9)
	_lens = Lights.lens_mat(Color(1.0, 0.95, 0.7))
	var lamp := _lens   # v_003: lens glows strongly when the lights are on
	var tail := Util.glow(Color(0.9, 0.05, 0.05), 1.2)
	_tail_mat = tail
	if Cfg.LIGHTS:   # v_002: two headlights on the front lamps, tilted a little down onto the road
		for sx in [-1.0, 1.0]:
			var sp := Lights.spot(self, Vector3(0.36 * sx, 1.66, -2.0), -5.0, 75.0, 34.0, 8.0, Color(1.0, 0.93, 0.78))
			_lights.append(sp)
			Lights.beam(sp, 32.0, 4.5, 0.22)
		# one wide work light on the roof for the ground right in front of the tractor
		var wl := Lights.spot(self, Vector3(0.0, 2.78, -0.6), -28.0, 22.0, 52.0, 3.5, Color(1.0, 0.95, 0.85))
		_lights.append(wl)
	var amber := Util.glow(Color(1.0, 0.6, 0.05), 1.6)

	# --- frame, engine, hood ---
	Util.part(self, Vector3(0.9, 0.45, 3.0), Vector3(0, 0.85, 0), steel)
	Util.part(self, Vector3(1.05, 0.7, 1.7), Vector3(0, 1.4, -1.05), green)
	Util.part(self, Vector3(0.92, 0.12, 1.6), Vector3(0, 1.81, -1.05), green_dk)
	Util.part(self, Vector3(0.14, 0.02, 1.5), Vector3(0, 1.88, -1.05), yellow)
	Util.part(self, Vector3(1.07, 0.06, 1.72), Vector3(0, 1.08, -1.05), yellow)    # yellow skirt line under the hood
	# front: grille, lights, bumper weight
	Util.part(self, Vector3(0.95, 0.62, 0.06), Vector3(0, 1.38, -1.91), dark)
	for i in 5:
		Util.part(self, Vector3(0.8, 0.03, 0.03), Vector3(0, 1.17 + i * 0.1, -1.95), steel)
	for sx in [-1.0, 1.0]:
		Util.part(self, Vector3(0.24, 0.17, 0.05), Vector3(0.36 * sx, 1.66, -1.93), steel)
		Util.part(self, Vector3(0.19, 0.12, 0.07), Vector3(0.36 * sx, 1.66, -1.95), lamp)
	Util.part(self, Vector3(1.4, 0.3, 0.28), Vector3(0, 0.62, -2.0), dark)
	Util.part(self, Vector3(1.3, 0.04, 0.3), Vector3(0, 0.78, -2.0), yellow)
	# exhaust stack with rain cap
	var pipe := Util.mim(Util.cyl(0.05, 0.85, 8), dark)
	pipe.position = Vector3(0.38, 2.25, -1.5)
	add_child(pipe)
	Util.part(self, Vector3(0.14, 0.03, 0.14), Vector3(0.38, 2.7, -1.5), steel, Vector3(18, 0, 0))
	# axles
	Util.part(self, Vector3(1.9, 0.14, 0.14), Vector3(0, 0.5, -1.3), dark)
	Util.part(self, Vector3(2.1, 0.2, 0.2), Vector3(0, 0.75, 0.9), dark)

	# --- cab ---
	Util.part(self, Vector3(1.55, 0.08, 1.65), Vector3(0, 1.12, 0.45), dark)
	for px in [-0.78, 0.78]:
		for pz in [-0.35, 1.15]:
			Util.part(self, Vector3(0.07, 1.7, 0.07), Vector3(px, 1.95, pz), white)
	Util.part(self, Vector3(1.78, 0.1, 1.8), Vector3(0, 2.82, 0.4), white)
	Util.part(self, Vector3(1.6, 0.04, 1.6), Vector3(0, 2.76, 0.4), green_dk)
	Util.part(self, Vector3(1.5, 1.45, 0.03), Vector3(0, 1.95, -0.35), glass)     # windshield
	Util.part(self, Vector3(1.5, 1.3, 0.03), Vector3(0, 1.98, 1.15), glass)       # rear window
	for sx in [-0.78, 0.78]:
		Util.part(self, Vector3(0.03, 1.2, 1.4), Vector3(sx, 2.0, 0.4), glass)    # side windows
	# roof beacon + work lights
	var beacon := Util.mim(Util.cyl(0.06, 0.14, 8), amber)
	beacon.position = Vector3(0.55, 2.94, 0.95)
	add_child(beacon)
	for sx in [-0.5, 0.5]:
		Util.part(self, Vector3(0.22, 0.1, 0.08), Vector3(sx, 2.78, -0.5), lamp)

	# --- driver area ---
	Util.part(self, Vector3(0.62, 0.14, 0.55), Vector3(0, 1.2, 0.4), seat_m)
	Util.part(self, Vector3(0.62, 0.62, 0.12), Vector3(0, 1.55, 0.74), seat_m)
	var col := Util.mim(Util.cyl(0.035, 0.5, 6), dark)
	col.position = Vector3(0, 1.45, -0.12)
	col.rotation_degrees.x = -30.0
	add_child(col)
	var sw := TorusMesh.new()
	sw.inner_radius = 0.07
	sw.outer_radius = 0.17
	sw.rings = 12
	sw.ring_segments = 6
	var wheel_n := Util.mim(sw, dark)
	wheel_n.position = Vector3(0, 1.68, -0.24)
	wheel_n.rotation_degrees.x = -60.0
	add_child(wheel_n)

	# --- fenders, steps, rear lights ---
	for sx in [-1.0, 1.0]:
		Util.part(self, Vector3(0.66, 0.07, 1.4), Vector3(1.07 * sx, 1.68, 0.9), green)
		Util.part(self, Vector3(0.06, 0.18, 1.4), Vector3(1.38 * sx, 1.6, 0.9), green)
		Util.part(self, Vector3(0.42, 0.05, 0.85), Vector3(0.92 * sx, 1.04, -1.3), green)
		Util.part(self, Vector3(0.3, 0.05, 0.5), Vector3(0.9 * sx, 0.78, -0.15), steel)
		Util.part(self, Vector3(0.16, 0.1, 0.05), Vector3(0.68 * sx, 1.0, 1.52), tail)

	# --- rear linkage (the arms the plow hangs on) ---
	for sx in [-1.0, 1.0]:
		Util.part(self, Vector3(0.07, 0.07, 1.0), Vector3(0.55 * sx, 0.5, 1.5), steel)
	Util.part(self, Vector3(0.2, 0.15, 0.55), Vector3(0, 0.62, 1.72), dark)
	Util.part(self, Vector3(0.06, 0.06, 0.95), Vector3(0, 1.0, 1.6), steel, Vector3(8, 0, 0))

	# --- wheels: big at the back, small at the front (front ones steer) ---
	_wheel(Vector3(-1.05, 0.78, 0.9), 0.78, 0.56, false)
	_wheel(Vector3(1.05, 0.78, 0.9), 0.78, 0.56, false)
	_wheel(Vector3(-0.92, 0.5, -1.3), 0.5, 0.36, true)
	_wheel(Vector3(0.92, 0.5, -1.3), 0.5, 0.36, true)

	# invisible points
	seat = Marker3D.new()
	seat.name = "Seat"
	seat.position = Vector3(0, 1.34, 0.35)
	add_child(seat)
	hitch_rear = Marker3D.new()
	hitch_rear.name = "HitchRear"
	hitch_rear.position = Vector3(0, 0.5, 2.0)
	add_child(hitch_rear)
	hitch_front = Marker3D.new()
	hitch_front.name = "HitchFront"
	hitch_front.position = Vector3(0, 0.5, -2.3)
	hitch_front.rotation.y = PI   # front attachments extend forward
	add_child(hitch_front)
	Util.bake(self)   # V29: merge all static parts per material = far fewer draw calls


# tire with tread blocks, yellow rim, hub and spokes. The spokes + tread make the turning visible.
func _wheel(pos: Vector3, r: float, w: float, steers: bool) -> void:
	var tire_m := Util.mat(Color(0.07, 0.07, 0.07), 0.95)
	var tread_m := Util.mat(Color(0.12, 0.12, 0.12), 0.95)
	var rim_m := Util.mat(Color(0.95, 0.76, 0.1), 0.45, 0.2)
	var hub_m := Util.mat(Color(0.5, 0.52, 0.56), 0.35, 0.8)
	var spoke_m := Util.mat(Color(0.2, 0.2, 0.22), 0.5, 0.4)

	var holder := Node3D.new()
	holder.position = pos
	add_child(holder)
	var spin := Node3D.new()
	holder.add_child(spin)

	var tire := Util.mim(Util.cyl(r, w, 16), tire_m)
	tire.rotation_degrees.z = 90.0
	spin.add_child(tire)
	var rim := Util.mim(Util.cyl(r * 0.6, w + 0.03, 12), rim_m)
	rim.rotation_degrees.z = 90.0
	spin.add_child(rim)
	var hub := Util.mim(Util.cyl(r * 0.2, w + 0.1, 10), hub_m)
	hub.rotation_degrees.z = 90.0
	spin.add_child(hub)
	for k in 3:
		var spoke := Util.mim(Util.box(Vector3(w + 0.06, r * 1.1, r * 0.1)), spoke_m)
		spoke.rotation_degrees.x = 60.0 * k
		spin.add_child(spoke)

	var lugs: Array = []
	var n := 20 if r > 0.6 else 14
	for k in n:
		var a := TAU * float(k) / float(n)
		var b := Basis(Vector3.RIGHT, a)
		lugs.append(Transform3D(b, b * Vector3(0, 0, r + 0.01)))
	Util.multi(spin, Util.box(Vector3(w * 0.96, r * 0.34, 0.12)), tread_m, lugs)

	spinners.append([spin, r])
	if steers:
		steerers.append(holder)


func stop_inputs() -> void:
	gas = false
	brake = false
	steer = 0.0


func kmh() -> float:
	return absf(speed) * 3.6


# the lowest speed limit (km/h) of the tractor and everything hooked on it, right now
func speed_limit_kmh() -> float:
	var l := MAX_KMH
	for k in slots:
		var a = slots[k]
		if a != null and a.has_method("speed_limit_kmh"):
			l = minf(l, a.speed_limit_kmh())
	return l


func set_lights(on: bool) -> void:
	lights_on = on
	Lights.set_on(_lights, on, _lens)


func _physics_process(delta: float) -> void:
	if _tail_mat != null:   # tail lights: dim by day, red at night, bright when braking
		_tail_mat.emission_energy_multiplier = 3.8 if (brake and gas == false) else (1.8 if lights_on else 0.6)
	var limit := speed_limit_kmh() / 3.6
	var empty := fuel <= 0.0   # no fuel: no engine
	# gravity along the slope: + = pushes the tractor forward (downhill), - = pulls it back (uphill)
	var slope_a := 0.0 if airborne else -SLOPE_G * sin(rotation.x)
	var held := false   # parked on a gentle slope
	if gas and not empty:
		if speed < limit:
			# the engine pulls less and less when it goes faster, so on a hill it settles at a lower top speed
			var acc := ACCEL * (1.0 - 0.55 * clampf(speed / MAX_FWD, 0.0, 1.0))
			speed = move_toward(speed, limit, acc * delta)
	elif brake and not empty:
		if speed > 0.2:
			speed = move_toward(speed, 0.0, BRAKE_FORCE * delta)
		else:
			speed = move_toward(speed, -MAX_REV, REV_ACCEL * delta)   # stopped + brake = reverse
	else:
		if absf(speed) < 0.15 and absf(slope_a) <= DRAG:
			speed = 0.0   # friction holds it on a gentle slope
			held = true
		else:
			speed = move_toward(speed, 0.0, DRAG * delta)
	if not held:
		speed += slope_a * delta   # hill: slower going up, faster going down

	# going downhill it may pass the speed limit a little; above that (or above a machine's limit) it slows down by itself
	var hard := limit * (1.0 + DOWNHILL_BONUS * clampf(slope_a / 4.0, 0.0, 1.0))
	if speed > hard:
		speed = move_toward(speed, hard, OVER_LIMIT_DECEL * delta)
	speed = maxf(speed, -MAX_REV * 2.0)
	# too steep to climb: it slides back
	if not airborne:
		if rotation.x > MAX_CLIMB and speed > 0.0:
			speed = move_toward(speed, -1.5, 14.0 * delta)
		elif rotation.x < -MAX_CLIMB and speed < 0.0:
			speed = move_toward(speed, 1.5, 14.0 * delta)

	# turning only while moving (reverse turns the other way, like a real vehicle); gentler when fast
	var f := clampf(speed / 3.0, -1.0, 1.0) * lerpf(1.0, 0.5, clampf(absf(speed) / MAX_FWD, 0.0, 1.0))
	if airborne:
		f *= 0.3
	rotation.y -= steer * TURN * f * delta

	# move along the ground (speed is along the slope, so the flat part is smaller on a steep hill)
	var fwd := -global_transform.basis.z
	velocity = Vector3(fwd.x * speed, 0.0, fwd.z * speed)
	move_and_slide()   # only trees / walls / the world edge stop it. The ground is followed by code:
	_follow_ground(delta)
	if absf(speed) > 0.05 and fuel > 0.0:
		var used := absf(speed) * delta / 1000.0 / FuelD.TRACTOR_KM_PER_L * FuelD.FUEL_SCALE
		if is_working():
			used *= FuelD.WORK_FUEL_MULT
		fuel = maxf(0.0, fuel - used)
	# crash sound: only the moment we touch the wall (not while sliding along it), louder when faster
	var hit := is_on_wall()
	crash_cd = maxf(0.0, crash_cd - delta)
	if hit and not was_hit and crash_cd <= 0.0 and absf(speed) > 1.5:
		snd_crash.volume_db = lerpf(-14.0, 0.0, clampf(absf(speed) / 8.0, 0.0, 1.0))
		snd_crash.play()
		crash_cd = 0.5
	was_hit = hit
	if hit:
		speed = move_toward(speed, 0.0, 25.0 * delta)
	_update_engine_sound(delta)

	for s in spinners:
		s[0].rotation.x -= speed / float(s[1]) * delta
	for h in steerers:
		h.rotation.y = lerpf(h.rotation.y, -steer * 0.45, 10.0 * delta)

	_update_attachments()


# ---------------------------------------------------------------- ground (hills and holes)

func setup_ground(c: Callable) -> void:
	ground = c
	_follow_ground(0.016, true)


func _h(p: Vector3) -> float:
	if ground.is_valid():
		return float(ground.call(p.x, p.z))
	return 0.0


# Reads the ground height under the 4 wheels, then: the tractor tilts (nose up / down, left / right) to match,
# rides at the right height, and flies (ballistic) when the ground falls away faster than gravity pulls it down.
func _follow_ground(delta: float, snap: bool = false) -> void:
	var yb := Basis(Vector3.UP, rotation.y)
	var o := global_position
	var fl := _h(o + yb * Vector3(-WHEEL_FRONT_X, 0.0, WHEEL_FRONT_Z))
	var fr := _h(o + yb * Vector3(WHEEL_FRONT_X, 0.0, WHEEL_FRONT_Z))
	var rl := _h(o + yb * Vector3(-WHEEL_REAR_X, 0.0, WHEEL_REAR_Z))
	var rr := _h(o + yb * Vector3(WHEEL_REAR_X, 0.0, WHEEL_REAR_Z))
	var hf := (fl + fr) * 0.5
	var hr := (rl + rr) * 0.5
	var t_pitch := atan2(hf - hr, WHEEL_REAR_Z - WHEEL_FRONT_Z)                                    # + = nose up
	var t_roll := atan2((fr + rr) * 0.5 - (fl + rl) * 0.5, WHEEL_FRONT_X + WHEEL_REAR_X)          # + = right side up
	var gy := hr + (hf - hr) * (WHEEL_REAR_Z / (WHEEL_REAR_Z - WHEEL_FRONT_Z))                     # ground height at the tractor origin
	var y := global_position.y
	if snap:
		y = gy
		vy = 0.0
		airborne = false
		rotation.x = t_pitch
		rotation.z = t_roll
	elif airborne:
		vy -= GRAVITY * delta
		y += vy * delta
		if y <= gy:
			y = gy
			airborne = false
			if vy < -7.0:
				speed *= 0.8
				snd_crash.volume_db = -8.0
				snd_crash.play()
			vy = 0.0
	else:
		# where would we be if nothing held us down?
		var y_free := y + vy * delta - 0.5 * GRAVITY * delta * delta
		if y_free > gy + 0.04:
			airborne = true
			y = y_free
			vy -= GRAVITY * delta
		else:
			vy = clampf((gy - y) / maxf(delta, 0.0001), -25.0, 25.0)
			y = gy
	if not snap:
		var k := 1.0 - exp(-(3.0 if airborne else 14.0) * delta)
		rotation.x = lerp_angle(rotation.x, t_pitch, k)
		rotation.z = lerp_angle(rotation.z, t_roll, k)
	global_position.y = y


# Engine sound: plays only while someone sits in the tractor and there is fuel.
# 3 "gears": the pitch climbs, drops a little at each shift, climbs again.
func _update_engine_sound(delta: float) -> void:
	var on := seat.get_child_count() > 0 and fuel > 0.0
	if not on:
		if snd_engine.playing:
			snd_engine.stop()
		return
	if not snd_engine.playing:
		snd_engine.pitch_scale = 0.8
		snd_engine.play()
	var rpm := clampf(absf(speed) / MAX_FWD, 0.0, 1.0)
	var g := mini(int(rpm * 3.0), 2)
	var frac := clampf(rpm * 3.0 - float(g), 0.0, 1.0)
	var want_pitch := 0.8 + frac * 0.75 + float(g) * 0.12
	var want_vol := engine_db + 7.0 * rpm
	if gas:
		want_pitch += 0.12
		want_vol += 3.0
	if is_working():
		want_vol += 1.5   # machine under load
	var k := minf(6.0 * delta, 1.0)
	snd_engine.pitch_scale = lerpf(snd_engine.pitch_scale, want_pitch, k)
	snd_engine.volume_db = lerpf(snd_engine.volume_db, want_vol, k)


func _hitch_point(side: String) -> Node3D:
	return hitch_rear if side == "rear" else hitch_front


# an attachment close enough to its hitch point and not connected yet (or null)
func candidate() -> Node3D:
	for a in get_tree().get_nodes_in_group("attachment"):
		var side: String = a.get_meta("side", "rear")
		if slots.get(side) != null:
			continue
		var h: Node3D = a.get_node_or_null("Hitch")
		if h == null:
			continue
		if h.global_position.distance_to(_hitch_point(side).global_position) < ATTACH_RANGE:
			return a
	return null








# --- WORK button: starts / stops every hooked machine ---
func is_working() -> bool:
	for k in slots:
		var a = slots[k]
		if a != null and a.get("working") == true:
			return true
	return false






func _update_attachments() -> void:
	for side in slots:
		var a: Node3D = slots[side]
		if a == null:
			continue
		var h: Node3D = a.get_node_or_null("Hitch")
		if h == null:
			continue
		a.global_transform = _hitch_point(side).global_transform * h.transform.affine_inverse()






