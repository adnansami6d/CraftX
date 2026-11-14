extends Node3D
# Third-person camera that orbits the target. Drag = look left/right and up/down.
# set_target(node, distance, height, follow_heading)
#   follow_heading = true: camera slowly swings behind the target (used for the tractor)

const PITCH_MIN := -1.35  # camera low, looking up at the sky (about 77 degrees up; was -0.1 = stuck near the horizon)
const PITCH_MAX := 1.2    # camera high, looking down
const GROUND_CLEARANCE := 0.35   # the camera never goes lower than this above the ground UNDER IT (the ground), so it can not sink into the floor
const VEHICLE_PITCH := 0.22      # camera height angle while driving
const FOOT_PITCH := 0.04
const VEHICLE_AIM_LIFT := 1.6    # driving: aim this many meters above the vehicle, so the vehicle sits low on screen and the road fills the view (bigger = vehicle lower)
const WALL_MARGIN := 0.25        # the camera stays this far in front of walls / objects behind the character

var target: Node3D
var yaw := 0.0
var pitch := 0.04   # V29.1: almost level like Free Fire (was 0.2 = looking down, too much ground)
var dist := 2.2
var height := 1.0
var follow_heading := false
var idle := 0.0
var cam: Camera3D
const LOOK_DROP := 0.3   # on foot the camera is high but looks down at the body, so the feet stay on screen (bigger = looks lower)
var shoulder := 0.7   # on foot the character stands a bit left of the crosshair
var ground := Callable()   # (x, z) -> height of the ground. main.gd sets it (world.height_at). Without it the ground is y = 0.
var _clear := 999.0        # how far the camera may be from the pivot right now (walls pull it in at once, it eases back out)
var _floor_y := -999.0     # lowest camera height right now (climbs a hill up at once)
var _dt := 0.016


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 60.0   # V29: closer, Free Fire-like view
	cam.far = 600.0   # V30: the flat field goes on to the horizon (haze hides the end)
	cam.near = 0.2
	add_child(cam)
	cam.current = true


func look(dx: float, dy: float) -> void:
	yaw -= dx * 0.006
	pitch = clampf(pitch + dy * 0.006, PITCH_MIN, PITCH_MAX)
	idle = 0.0


func _ground_y(x: float, z: float) -> float:
	if ground.is_valid():
		return float(ground.call(x, z))
	return 0.0


# lowest allowed camera height at p: ground under the camera + clearance. Going down it eases (no jumps), going up it is instant.
func _floor_at(p: Vector3) -> float:
	var raw := _ground_y(p.x, p.z) + GROUND_CLEARANCE
	if raw >= _floor_y:
		_floor_y = raw
	else:
		_floor_y = lerpf(_floor_y, raw, minf(10.0 * _dt, 1.0))
	return _floor_y


func _center() -> Vector3:
	var c := target.global_position + Vector3(0, height, 0)
	if target.is_in_group("player"):
		c += Basis(Vector3.UP, yaw) * Vector3(shoulder, 0, 0)
	return c


func _orbit_basis() -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)


# Free Fire style: the camera swings on a ball around the character. Looking up swings it DOWN,
# but never below GROUND_CLEARANCE. The view direction comes from yaw/pitch only (not "look at the body"),
# so when the camera is held up by the ground you still look at the sky and the character slides down the screen.
func _wanted_pos() -> Vector3:
	var body := target.global_position + Vector3(0, height, 0)
	var c := _center()
	var excl: Array = []
	if target is CollisionObject3D:
		excl = [(target as CollisionObject3D).get_rid()]
	elif target.has_method("body_rid"):
		excl = [target.call("body_rid")]   # FIX: the helicopter has a solid body now: the camera must not hit it
	# 1) the shoulder offset (0.7 m to the side) must not go through a wall: this was the bug. Standing next to a wall,
	#    the camera pivot ended up on the OTHER side of it, so the ray below started outside and never hit the wall.
	var h0 := _ray(body, c, excl)
	if not h0.is_empty():
		c = h0.position + h0.normal * 0.2
	var basis_o := _orbit_basis()
	var p := c + basis_o * Vector3(0, 0, dist)
	p.y = maxf(p.y, _ground_y(p.x, p.z) + GROUND_CLEARANCE)
	# 2) something solid between the pivot and the camera (house, fence, edge wall)? move the camera in front of it.
	#    3 rays (middle, left, right) so the camera can not slip through a wall corner or a thin wall at a slant.
	var full := p - c
	var full_len := full.length()
	if full_len > 0.001:
		var dir := full / full_len
		var side := basis_o.x * 0.2
		var best := full_len
		for off in [Vector3.ZERO, side, -side]:
			var h := _ray(c + off, p + off, excl)
			if not h.is_empty():
				var d: float = (h.position - (c + off)).length()
				best = minf(best, d)
		var allowed := full_len
		if best < full_len:
			allowed = maxf(best - WALL_MARGIN, 0.3)
		# a wall pulls the camera in at once, but the camera eases back out (no sudden jumps)
		_clear = allowed if allowed < _clear else minf(allowed, _clear + 8.0 * _dt)
		p = c + dir * minf(full_len, _clear)
	p.y = maxf(p.y, _floor_at(p))
	return p


func _ray(from: Vector3, to: Vector3, excl: Array) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 3   # things (layer 1) AND the ground (layer 2): a hill or a wall stops the camera
	q.exclude = excl
	return get_world_3d().direct_space_state.intersect_ray(q)


func _aim_basis() -> Basis:
	var b := _orbit_basis()
	if target.is_in_group("player"):
		# small extra tilt down so the feet stay on screen (replaces the old LOOK_DROP look_at)
		b = b * Basis(Vector3.RIGHT, -atan2(LOOK_DROP, dist))
	else:
		b = b * Basis(Vector3.RIGHT, atan2(VEHICLE_AIM_LIFT, dist))   # tilt up a little: vehicle moves down, road ahead shows
	return b


func set_target(t: Node3D, d: float = 2.2, h: float = 1.0, follow: bool = false) -> void:
	if follow:
		pitch = VEHICLE_PITCH   # driving: camera up behind the vehicle, looking slightly down so the road ahead is visible
	elif follow_heading:
		pitch = FOOT_PITCH      # got out: back to the almost-level on-foot view
	target = t
	_clear = 999.0
	_floor_y = -999.0
	dist = d
	height = h
	follow_heading = follow
	idle = 0.0
	if follow:
		yaw = t.rotation.y
	cam.global_position = _wanted_pos()
	cam.global_basis = _aim_basis()
	cam.reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	_dt = delta
	idle += delta
	if follow_heading and idle > 3.0:
		yaw = lerp_angle(yaw, target.rotation.y, 1.5 * delta)
	if target.is_in_group("player"):
		# on foot: the camera is glued to the character (no lag), so running does not change the view (like Free Fire)
		cam.global_position = _wanted_pos()
	else:
		cam.global_position = _wanted_pos()   # glued to the vehicle: no lag, so the camera does not drop behind when you speed up
	cam.global_basis = _aim_basis()
