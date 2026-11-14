extends Node
# v_012d: SAVE EVERYTHING. One file: user://savegame.json  (written safely: temp file first, then renamed).
# Saved: game clock (day / night), player place + camera, health, kills, weapon + magazines, wood / stone bag,
#        selected block, tractor + helicopter place, and EVERY tree / bush / rock you have broken.
# (Built blocks + torches are saved by build.gd in user://blocks.dat, as before.)
# Saving happens: every AUTOSAVE_SECONDS, right after something big changes, and when the app is paused / closed.
# A new game (no save file) always starts at Cfg.START_HOUR (06:00).

const Cfg = preload("res://scripts/config.gd")
const PATH := "user://savegame.json"
const TMP := "user://savegame.tmp"
const AUTOSAVE_SECONDS := 10.0
const FORMAT := 1

# broken trees / bushes / rocks: key (Vector2i, 10 cm grid) -> Vector2(x, z). Static: shooter.gd, stream.gd and main.gd share it.
static var cuts := {}
static var cuts_dirty := false

var main
var enabled := false      # false while loading: nothing may overwrite the save file with start values
var _t := 0.0
var _foot := Vector3.ZERO  # last place of the player on foot (used when saved inside a vehicle)
var _have_foot := false


static func key_of(x: float, z: float) -> Vector2i:
	return Vector2i(roundi(x * 10.0), roundi(z * 10.0))


# shooter.gd calls this when a tree / bush / rock breaks
static func note_cut(p: Vector3) -> void:
	cuts[key_of(p.x, p.z)] = Vector2(p.x, p.z)
	cuts_dirty = true


# Hides every broken thing that lives in this holder (the node with the MultiMeshInstance3D copies + the cuttable bodies).
# stream.gd calls it after a square is built, main.gd calls it for the big map.
static func apply_cuts(holder: Node) -> void:
	if cuts.is_empty() or holder == null or not holder.is_inside_tree():
		return
	var hit := {}   # key -> Vector2 : broken things found in this holder
	for ch in holder.get_children():
		var body := ch as StaticBody3D
		if body == null or not body.has_meta("cuttable"):
			continue
		for c in body.get_children():
			var cs := c as CollisionShape3D
			if cs == null or cs.disabled or not cs.has_meta("kind"):
				continue
			var gp := cs.global_position
			var k := key_of(gp.x, gp.z)
			if cuts.has(k):
				hit[k] = Vector2(gp.x, gp.z)
				cs.disabled = true
	if hit.is_empty():
		return
	for ch in holder.get_children():   # one pass over all copies (fast, even for the big map)
		var mmi := ch as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var mm := mmi.multimesh
		var gt := mmi.global_transform
		for i in mm.instance_count:
			var lt := mm.get_instance_transform(i)
			var o := gt * lt.origin
			var k0 := key_of(o.x, o.z)
			var found := false
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var v = hit.get(k0 + Vector2i(dx, dz))
					if v != null and absf(o.x - v.x) < 0.06 and absf(o.z - v.y) < 0.06:
						found = true
			if found:
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), lt.origin))


# main.gd: call once when the world, player, vehicles, shooter, build and combat all exist (still behind the loading screen)
func start(m) -> void:
	main = m
	var d := _read()
	if not d.is_empty():
		_restore(d)
	enabled = true


func _read() -> Dictionary:
	for p in [PATH, TMP]:
		if FileAccess.file_exists(p):
			var v = JSON.parse_string(FileAccess.get_file_as_string(p))
			if v is Dictionary:
				return v
	return {}


func _restore(d: Dictionary) -> void:
	# --- broken trees / rocks first (so streamed squares and the big map stay broken)
	cuts.clear()
	for e in d.get("cuts", []):
		if e is Array and e.size() >= 2:
			var x := float(e[0])
			var z := float(e[1])
			cuts[key_of(x, z)] = Vector2(x, z)
	apply_cuts(main.world)
	for c in main.world.get_children():   # squares of the stream that already exist (the others apply it when they are built)
		if c.get("_chunks") is Dictionary:
			for n in (c.get("_chunks") as Dictionary).values():
				apply_cuts(n)

	# --- day and night
	if main.daynight != null and d.has("hour"):
		main.set_clock(float(d["hour"]))

	# --- weapon, bag, block
	var sh = main.shooter
	if sh != null:
		sh.cur = clampi(int(d.get("weapon", 0)), 0, 1)
		var mg = d.get("mag")
		if mg is Array and mg.size() >= 2:
			sh.mag = [int(mg[0]), int(mg[1])]
		var inv = d.get("inv")
		if inv is Dictionary:
			for kd in inv:
				sh.inv[String(kd)] = int(inv[kd])
	if main.build != null:
		main.build.select_block(int(d.get("block", 1)))

	# --- health
	if main.combat != null:
		var hp := float(d.get("hp", main.combat.MAX_HP))
		main.combat.hp = main.combat.MAX_HP if hp <= 0.0 else clampf(hp, 1.0, main.combat.MAX_HP)
		main.combat.kills = int(d.get("kills", 0))

	# --- vehicles (stay where you left them)
	var tr = d.get("tractor")
	if tr is Array and tr.size() >= 4 and _inside(float(tr[0]), float(tr[2])):
		main.tractor.global_position = Vector3(float(tr[0]), float(tr[1]), float(tr[2]))
		main.tractor.rotation.y = float(tr[3])
		main.tractor.speed = 0.0
		main.tractor.reset_physics_interpolation()
	var hl = d.get("heli")
	if hl is Array and hl.size() >= 4 and _inside(float(hl[0]), float(hl[2])):
		main.heli.global_position = Vector3(float(hl[0]), float(hl[1]), float(hl[2]))
		main.heli.rotation.y = float(hl[3])
		main.heli.reset_physics_interpolation()

	# --- player (always comes back standing on foot)
	var pp = d.get("player")
	if pp is Array and pp.size() >= 3 and _inside(float(pp[0]), float(pp[2])):
		var pos := Vector3(float(pp[0]), float(pp[1]) + 0.4, float(pp[2]))
		main.player.stand(main, pos)
		main.rig.set_target(main.player)
		main.rig.yaw = float(d.get("cam_yaw", 0.0))
		if d.has("body_yaw"):
			main.player.pivot.rotation.y = float(d["body_yaw"])
		_foot = pos
		_have_foot = true


func _inside(x: float, z: float) -> bool:
	return main.world.contains(x, z)


func _snapshot() -> Dictionary:
	var d := {"format": FORMAT}
	if main.daynight != null:
		d["hour"] = main.daynight.hour
	var ppos: Vector3 = main.player.global_position
	if main.driving:
		ppos = main.tractor.global_position + main.tractor.global_transform.basis.x * -2.3 + Vector3(0, 1.0, 0)
	elif main.flying:
		ppos = _foot if _have_foot else main.world.spawn   # in the air: come back to the last place on foot
	else:
		_foot = ppos
		_have_foot = true
	d["player"] = [ppos.x, ppos.y, ppos.z]
	d["cam_yaw"] = main.rig.yaw
	d["body_yaw"] = main.player.pivot.rotation.y
	var tp: Vector3 = main.tractor.global_position
	d["tractor"] = [tp.x, tp.y, tp.z, main.tractor.rotation.y]
	if not main.flying or main.heli.on_ground():   # a helicopter in the air is not saved (it would hang in the sky)
		var hp3: Vector3 = main.heli.global_position
		d["heli"] = [hp3.x, hp3.y, hp3.z, main.heli.rotation.y]
	if main.shooter != null:
		d["weapon"] = main.shooter.cur
		d["mag"] = [int(main.shooter.mag[0]), int(main.shooter.mag[1])]
		d["inv"] = main.shooter.inv.duplicate()
	if main.build != null:
		d["block"] = main.build.sel
	if main.combat != null:
		d["hp"] = main.combat.hp
		d["kills"] = main.combat.kills
	var arr := []
	for k in cuts:
		var v: Vector2 = cuts[k]
		arr.append([snappedf(v.x, 0.001), snappedf(v.y, 0.001)])
	d["cuts"] = arr
	return d


func save_now() -> void:
	if not enabled or main == null or not main._game_ready:
		return
	if main.player == null or main.tractor == null or main.heli == null:
		return
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_snapshot()))
	f.close()
	var da := DirAccess.open("user://")
	if da != null:
		da.rename("savegame.tmp", "savegame.json")   # replaces the old file in one step
		# (if rename can not replace on some device, copy as a fallback)
		if FileAccess.file_exists(TMP):
			da.copy("savegame.tmp", "savegame.json")
			da.remove("savegame.tmp")
	cuts_dirty = false


func _process(delta: float) -> void:
	if not enabled:
		return
	_t += delta
	if _t >= AUTOSAVE_SECONDS or (cuts_dirty and _t >= 2.0):
		_t = 0.0
		save_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save_now()
