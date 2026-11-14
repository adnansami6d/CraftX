extends Node
# COMBAT (v_007): bandits, player health, health pickups, camp missions, aim help. From Fx99 combat.gd.
# Weapons, ammo, reload and the bag stay in shooter.gd (My Plant). No farm coins, no minimap yet.
# v_007: NIGHT ATTACK (no missions): when the sun is down bandits + zombies spawn around the player on free ground (Flora.spot_ok), the sun burns them at dawn.
# The shooter calls: hit_enemy(), assist_dir(), alert_near(). Switch: Cfg.COMBAT in config.gd.

const Util = preload("res://scripts/util.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const HudScript = preload("res://scripts/combat_hud.gd")
const Flora = preload("res://scripts/flora.gd")
const Biome = preload("res://scripts/biome.gd")
const Cfg = preload("res://scripts/config.gd")
const MAX_HP := 100.0
var main
var player
var rig
var touch
var hud
var ready_ok := false

var hp := MAX_HP
var dead := false
var firing := false
var heal_wait := 0.0
var death_t := 0.0
var kills := 0
var target_on := false
var night := false
var _spawn_t := 3.0
var _n_total := 0     # spawned this night
var _n_wave := 0      # spawned in this wave
var _wave_no := 1
var _wave_pause := 0.0
var _burn_t := 1.0
var pickups: Array = []
var torches: Array = []   # v_008: torch positions (Vector3, cell centre): no new spawns near them (Cfg.TORCH)
var enemy_sound: AudioStreamWAV

var _s_hit: AudioStreamPlayer
var _s_hurt: AudioStreamPlayer
var _s_pick: AudioStreamPlayer
var _info_t := 0.0
var _probe: SphereShape3D


func setup(m, p, r, t, layer: CanvasLayer) -> void:
	main = m
	player = p
	rig = r
	touch = t
	hud = HudScript.new()
	hud.combat = self
	layer.add_child(hud)
	enemy_sound = _noise_wav(0.3, 28.0, 85.0, 18.0, 0.9)
	_s_hit = _player_snd(_noise_wav(0.08, 90.0, 1100.0, 60.0, 0.5), -6.0)
	_s_hurt = _player_snd(_noise_wav(0.22, 18.0, 140.0, 14.0, 0.8), -2.0)
	_s_pick = _player_snd(_noise_wav(0.15, 30.0, 700.0, 18.0, 0.4), -4.0)
	_probe = SphereShape3D.new()
	_probe.radius = 1.0
	if main.build != null:   # torches loaded from the save file before the combat existed
		for c in main.build.torch_dir:
			var cc: Vector3i = c
			torches.append(Vector3(cc) + Vector3(0.5, 0.5, 0.5))
	ready_ok = true


func on_foot() -> bool:
	return player != null and not dead and not main.driving and not main.flying


# ---------------------------------------------------------------- sounds (made from math, no files)

func _noise_wav(dur: float, decay: float, tone: float, tone_decay: float, vol: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var v := (randf() * 2.0 - 1.0) * exp(-t * decay)
		if tone > 0.0:
			v += sin(TAU * tone * t) * exp(-t * tone_decay) * 0.9
		data.encode_s16(i * 2, int(clampf(v * vol, -1.0, 1.0) * 30000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	return st


func _player_snd(stream: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


# ---------------------------------------------------------------- effects

func _tracer(a: Vector3, b: Vector3, col: Color) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, len)
	var mi := Util.mim(bm, Util.glow(col, 3.0))
	add_child(mi)
	mi.global_position = (a + b) / 2.0
	var up := Vector3.UP
	if absf((b - a).normalized().dot(Vector3.UP)) > 0.98:
		up = Vector3.RIGHT
	mi.look_at(b, up)
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)


func _puff(pos: Vector3, col: Color, r: float, life: float) -> void:
	var mi := Util.mim(Util.sphere(r, 6, 3), Util.glow(col, 3.0))
	add_child(mi)
	mi.global_position = pos
	get_tree().create_timer(life).timeout.connect(mi.queue_free)


# ---------------------------------------------------------------- the shooter calls these

# a bullet of the player hit a bandit
func hit_enemy(en, end: Vector3, dmg: float) -> void:
	var head: bool = end.y > (en as Node3D).global_position.y + 0.5 * Util.CHAR_SCALE
	var killed: bool = en.take_hit(dmg, head)
	hud.hit(killed)
	_s_hit.play()
	_puff(end, Color(1.0, 0.1, 0.05), 0.12, 0.12)


# light aim assist: pulls the shot toward a bandit near the crosshair
func assist_dir(origin: Vector3, cam_fwd: Vector3) -> Vector3:
	var tgt: Node3D = _assist_target(origin, cam_fwd, 7.0)
	if tgt == null:
		return cam_fwd
	var td: Vector3 = (tgt.global_position + Vector3(0, 0.25, 0) - origin).normalized()
	return cam_fwd.slerp(td, 0.65)


func alert_near(pos: Vector3, radius: float) -> void:
	var list: Array = get_tree().get_nodes_in_group("enemy")
	for e in list:
		if not e.dead and e.global_position.distance_to(pos) < radius:
			e.alert()


# ---------------------------------------------------------------- enemies call these

func enemy_shot(e, from: Vector3, hit: bool, amount: float) -> void:
	var tgt: Vector3 = player.global_position + Vector3(0, 0.3, 0)
	var end := tgt
	if not hit:
		end = tgt + Vector3(randf_range(-1.6, 1.6), randf_range(-0.8, 0.8), randf_range(-1.6, 1.6))
	var d := end - from
	var tr_end := from + d.normalized() * minf(d.length() + 4.0, 70.0)
	_tracer(from, tr_end, Color(1.0, 0.45, 0.2))
	_puff(from, Color(1.0, 0.6, 0.2), 0.12, 0.04)
	e.play_shot()
	if hit:
		hurt(amount)


func melee_hit(e, amount: float) -> void:
	e.play_shot()
	hurt(amount)


func hurt(amount: float) -> void:
	if dead or main.flying:
		return
	hp -= amount
	heal_wait = 6.0
	hud.hurt()
	_s_hurt.play()
	if hp <= 0.0:
		hp = 0.0
		dead = true
		death_t = 3.0
		firing = false


func on_enemy_killed(e) -> void:
	kills += 1
	_spawn_t = maxf(_spawn_t, randf_range(10.0, 20.0))   # a kill: the next one comes slowly
	_drop(e.global_position, e.boss)
	alert_near(e.global_position, 18.0)


# ---------------------------------------------------------------- pickups (health only: ammo is endless in My Plant)

func _pickup_node() -> Node3D:
	var n := Node3D.new()
	Util.part(n, Vector3(0.5, 0.32, 0.38), Vector3.ZERO, Util.mat(Color(0.95, 0.95, 0.95)))
	Util.part(n, Vector3(0.3, 0.34, 0.08), Vector3(0, 0, 0.2), Util.glow(Color(1.0, 0.1, 0.1), 1.2))
	Util.part(n, Vector3(0.08, 0.34, 0.3), Vector3(0, 0, 0.2), Util.glow(Color(1.0, 0.1, 0.1), 1.2))
	return n


func _drop(pos: Vector3, boss: bool) -> void:
	var roll := randf()
	var count := 0
	if boss:
		count = 2
	elif roll >= 0.3 and roll < 0.48:
		count = 1
	var gy: float = main.world.height_at(pos.x, pos.z)
	for i in count:
		var n := _pickup_node()
		n.position = Vector3(pos.x + float(i) * 0.9, gy + 0.55, pos.z)
		add_child(n)
		pickups.append({"n": n, "t": 0.0, "cd": 0.0, "y": gy + 0.55})


func _tick_pickups(delta: float) -> void:
	var pp: Vector3 = player.global_position
	for i in range(pickups.size() - 1, -1, -1):
		var p: Dictionary = pickups[i]
		var n: Node3D = p["n"]
		var t: float = float(p["t"]) + delta
		p["t"] = t
		n.rotation.y += delta * 2.0
		n.position.y = float(p["y"]) + 0.12 * sin(t * 3.0)
		var cd: float = float(p.get("cd", 0.0))
		if cd > 0.0:
			p["cd"] = cd - delta
		var near: bool = cd <= 0.0 and Vector2(n.position.x - pp.x, n.position.z - pp.z).length() < 1.9
		if near and not dead:
			hp = minf(MAX_HP, hp + 40.0)
			hud.say("+40 health")
			_s_pick.play()
		if (near and not dead) or t > 90.0:
			n.queue_free()
			pickups.remove_at(i)


# ---------------------------------------------------------------- torches (v_008)
# Minecraft rule: light stops NEW spawns only. Enemies that already exist are never pushed away or scared.

func torch_added(pos: Vector3) -> void:
	torches.append(pos)


func torch_removed(pos: Vector3) -> void:
	torches.erase(pos)


func _torch_blocks(x: float, z: float, gy: float) -> bool:
	var r2: float = Cfg.TORCH_SAFE_RADIUS * Cfg.TORCH_SAFE_RADIUS
	for t in torches:
		var tp: Vector3 = t
		var dx := tp.x - x
		var dz := tp.z - z
		if dx * dx + dz * dz < r2 and absf(tp.y - gy) < 8.0:
			return true
	return false


# ---------------------------------------------------------------- free spots for bandits

func _desert(x: float, z: float) -> bool:
	var w: Array = Biome.weights(x, z)
	if float(w[3]) > 0.01:
		return true
	for k in 4:
		var a := TAU * float(k) / 4.0
		var w2: Array = Biome.weights(x + cos(a) * 12.0, z + sin(a) * 12.0)
		if float(w2[3]) > 0.03:
			return true
	return false


# free = no desert, free of map blocks (roads, buildings, rails, ponds, edges), flat ground, no tree / wall in 1 m
func _free_spot(x: float, z: float, margin: float) -> bool:
	if not Flora.spot_ok(x, z, margin):
		return false
	if _desert(x, z):
		return false
	var gh: float = float(main.world.height_at(x, z))
	if absf(gh) > 0.3:
		return false
	if Cfg.TORCH and _torch_blocks(x, z, gh):
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.transform = Transform3D(Basis.IDENTITY, Vector3(x, 1.45, z))
	q.collision_mask = 1
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	return space.intersect_shape(q, 1).is_empty()


# ---------------------------------------------------------------- night attack

func _spawn_night() -> bool:
	var pp: Vector3 = main.actor_position()
	for t in 12:
		var a := randf() * TAU
		var d := randf_range(40.0, 60.0)
		var x := pp.x + cos(a) * d
		var z := pp.z + sin(a) * d
		if _free_spot(x, z, 1.5):
			var z_type := randf() < 0.6   # 60% zombie, 40% gunner
			var e := EnemyScript.new()
			e.setup(self, player, Vector3(x, 0.0, z), false, 1.0, z_type)
			add_child(e)
			if z_type:
				e.alert()   # zombies hunt you at once
			return true
	return false


func _night_tick(delta: float) -> void:
	var was := night
	night = main.daynight != null and main.daynight.sun_elev < Cfg.NIGHT_ELEV
	if night and not was:
		_spawn_t = 3.0
		_n_total = 0
		_n_wave = 0
		_wave_no = 1
		_wave_pause = 0.0
	elif was and not night:
		pass   # v_011: no DAWN banner
	var pp: Vector3 = main.actor_position()
	var alive := 0
	var list: Array = get_tree().get_nodes_in_group("enemy")
	for e in list:
		if e.dead:
			continue
		if e.global_position.distance_to(pp) > 120.0:
			e.queue_free()   # far away: gone (keeps the count low)
			continue
		alive += 1
	if night:
		if not dead and _n_total < Cfg.NIGHT_TOTAL:   # waves, slow spawn, a limit per night
			if _wave_pause > 0.0:
				_wave_pause -= delta
				if _wave_pause <= 0.0:
					_n_wave = 0
					_wave_no += 1
					_spawn_t = 3.0
			elif _n_wave >= Cfg.WAVE_SIZE:
				if alive == 0:
					_wave_pause = randf_range(30.0, 60.0)
			else:
				_spawn_t -= delta
				if _spawn_t <= 0.0:
					_spawn_t = randf_range(5.0, 8.0)
					if alive < Cfg.NIGHT_MAX and _spawn_night():
						_n_total += 1
						_n_wave += 1
	elif alive > 0:
		_burn_t -= delta   # day: the sun burns one bandit after the other
		if _burn_t <= 0.0:
			_burn_t = randf_range(0.3, 1.2)
			for e2 in list:
				if not e2.dead:
					e2.burn()
					break


func objective_text() -> String:
	return ""   # v_011: the NIGHT / wave line is removed
	if dead or not night:
		return ""
	return "NIGHT: wave %d   bandits %d / %d" % [_wave_no, _n_total, Cfg.NIGHT_TOTAL] if _n_total < Cfg.NIGHT_TOTAL else "NIGHT: calm - wait for dawn"


# ---------------------------------------------------------------- per frame

func _physics_process(delta: float) -> void:
	if player == null or not bool(main._game_ready):
		return   # nothing happens while the game is still loading / warming up
	if dead:
		death_t -= delta
		if death_t <= 0.0:
			dead = false
			hp = MAX_HP
			main._respawn_player()
		return

	var can: bool = on_foot() and not main.shooter.holstered and not main.shooter.bag_open
	_aim_check(delta, can)

	if hp < MAX_HP:
		heal_wait -= delta
		if heal_wait <= 0.0:
			hp = minf(MAX_HP, hp + 4.0 * delta)

	_tick_pickups(delta)

	_night_tick(delta)

	_info_t -= delta
	if _info_t <= 0.0:
		_info_t = 0.5
		if main.debug_overlay != null:
			main.debug_overlay.set_value("combat", "%s  bandits %d  hp %d  kills %d" % ["NIGHT" if night else "day", get_tree().get_nodes_in_group("enemy").size(), int(hp), kills])


# ---------------------------------------------------------------- aim help

func _assist_target(cam_pos: Vector3, cam_fwd: Vector3, max_deg: float) -> Node3D:
	var best: Node3D = null
	var best_a := deg_to_rad(max_deg)
	var list: Array = get_tree().get_nodes_in_group("enemy")
	for e in list:
		if e.dead:
			continue
		var d: Vector3 = e.global_position + Vector3(0, 0.25, 0) - cam_pos
		var dl := d.length()
		if dl > 70.0 or dl < 2.0:
			continue
		var a := cam_fwd.angle_to(d / dl)
		if a < best_a:
			best_a = a
			best = e
	return best


# crosshair turns red over a bandit; while firing the camera is pulled gently toward a bandit near the crosshair
func _aim_check(delta: float, can: bool) -> void:
	target_on = false
	if not can:
		return
	var cam: Camera3D = rig.cam
	var cf: Vector3 = -cam.global_transform.basis.z
	var o: Vector3 = cam.global_position + cf * 1.5
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(o, o + cf * 110.0, 5)
	q.exclude = [player.get_rid()]
	var r: Dictionary = space.intersect_ray(q)
	if not r.is_empty():
		var col: Object = r["collider"]
		target_on = col is Node and (col as Node).is_in_group("enemy")
	var tg: Node3D = _assist_target(cam.global_position, cf, 9.0 if firing else 2.5)
	if tg != null and not firing:
		target_on = true
	if firing and tg != null:
		var d: Vector3 = tg.global_position + Vector3(0, 0.25, 0) - cam.global_position
		var k := 1.0 - exp(-3.0 * delta)
		rig.yaw = lerp_angle(rig.yaw, atan2(-d.x, -d.z), k)
		rig.pitch = clampf(lerpf(rig.pitch, -asin(clampf(d.normalized().y, -1.0, 1.0)), k), rig.PITCH_MIN, rig.PITCH_MAX)


# ---------------------------------------------------------------- warm-up (called by warmup.gd while the loading screen is on top)
# draws everything of the combat once: both bandit models, health label, shot / hit effects, pickup, flag, HUD parts, sounds.
func warmup() -> void:
	var tree := get_tree()
	var cam: Camera3D = rig.cam
	var f: Vector3 = -cam.global_transform.basis.z
	f.y = 0.0
	f = f.normalized() if f.length() > 0.01 else Vector3(0, 0, -1)
	var base: Vector3 = cam.global_position + f * 7.0
	base.y = main.world.height_at(base.x, base.z)
	var side := Vector3(f.z, 0.0, -f.x)
	var made: Array = []
	for k in 3:
		var e := EnemyScript.new()
		e.setup(self, player, base + side * (-2.8 + 2.8 * float(k)), k == 1, 1.0, k == 2)
		add_child(e)
		e.set_physics_process(false)   # the dummy must not walk or shoot
		e.take_hit(1.0, false)         # shows the health label (draws the "|" letters once)
		made.append(e)
	var up := Vector3(0, 1.2, 0)
	_tracer(base + up, base + up + f * 3.0, Color(1.0, 0.45, 0.2))
	_puff(base + up, Color(1.0, 0.6, 0.2), 0.12, 0.1)
	_puff(base + up + side * 0.5, Color(1.0, 0.1, 0.05), 0.12, 0.1)
	var pk := _pickup_node()
	pk.position = base + Vector3(0, 0.6, 0) + side * 3.0
	add_child(pk)
	# HUD parts + sounds (muted)
	var olds: Array = [_s_hit.volume_db, _s_hurt.volume_db, _s_pick.volume_db]
	_s_hit.volume_db = -80.0
	_s_hurt.volume_db = -80.0
	_s_pick.volume_db = -80.0
	_s_hit.play()
	_s_hurt.play()
	_s_pick.play()
	for e2 in made:
		e2._snd.volume_db = -80.0
		e2.play_shot()
	hud.flash = 0.45
	hud.hit_t = 0.18
	hud.hit_kill = true
	target_on = true
	dead = true   # draws YOU DIED (the real physics code is off until the game is ready)
	for i in 6:
		await tree.process_frame
	dead = false
	target_on = false
	hud.flash = 0.0
	hud.hit_t = 0.0
	hud._ban_t = 0.0
	_s_hit.stop()
	_s_hurt.stop()
	_s_pick.stop()
	_s_hit.volume_db = float(olds[0])
	_s_hurt.volume_db = float(olds[1])
	_s_pick.volume_db = float(olds[2])
	for e3 in made:
		e3.queue_free()
	pk.queue_free()
	await tree.process_frame
	await tree.process_frame
