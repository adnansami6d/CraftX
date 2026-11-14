extends Node
# Weapons + items. (Replaces the old combat.gd: no bandits / missions in My Plant.)
#   FIRE at a tree / bush / rock -> it breaks after some hits and gives WOOD / STONE blocks. The ground and the buildings can not be broken.
# Items go into `inv` (wood, stone). hud.gd shows them.
# Weapons: pistol / rifle (SWAP button). Infinite ammo, every magazine must be reloaded (RELOAD button).

const Util = preload("res://scripts/util.gd")
const DebrisScript = preload("res://scripts/debris.gd")
const Hardness = preload("res://scripts/hardness.gd")
const SaveGame = preload("res://scripts/savegame.gd")

const WEAPONS := [
	{"name": "PISTOL", "gap": 0.28, "mag": 12, "spread": 0.7, "reload": 1.1, "hits": 6, "dmg": 1, "edmg": 30.0},
	{"name": "RIFLE", "gap": 0.11, "mag": 30, "spread": 2.0, "reload": 1.8, "hits": 20, "dmg": 2, "edmg": 17.0},
]
const ITEM_COLORS := {"wood": Color(0.62, 0.42, 0.22), "stone": Color(0.56, 0.56, 0.6)}
const MAX_ITEMS := 40          # flying blocks at the same time
const TREE_HITS := 3
const TREE_WOOD := 2

var main
var player
var rig
var touch
var world
var hud

var cur := 1
var mag := [12, 30]
var reloading := false
var reload_t := 0.0
var reload_total := 1.0
var fire_t := 0.0
var aim_hold := 0.0
var firing := false
var holstered := false   # build mode: gun put away, no shooting
var bag_open := false
var _cut_dmg := {}      # shape instance id -> damage (trees, rocks, bushes)
var inv := {"wood": 0, "stone": 0}
var _items: Array = []   # {n: Node3D, kind: String, t: float, vel: Vector3}
var _debris            # falling pieces (scripts/debris.gd)

var _s_pistol: AudioStreamPlayer
var _s_rifle: AudioStreamPlayer
var _s_reload: AudioStreamPlayer
var _s_pick: AudioStreamPlayer
var _s_chop: AudioStreamPlayer


func setup(m, p, r, t, w) -> void:
	main = m
	player = p
	rig = r
	touch = t
	world = w
	_debris = DebrisScript.new()
	add_child(_debris)
	_debris.setup(Callable(world, "height_at"))
	_s_pistol = _player_snd(_noise_wav(0.28, 32.0, 120.0, 22.0, 1.0), -2.0)
	_s_rifle = _player_snd(_noise_wav(0.18, 45.0, 160.0, 35.0, 0.9), -4.0)
	_s_reload = _player_snd(_click_wav(), -2.0)
	_s_pick = _player_snd(_noise_wav(0.12, 30.0, 700.0, 18.0, 0.4), -8.0)
	_s_chop = _player_snd(_noise_wav(0.12, 40.0, 260.0, 40.0, 0.8), -4.0)


func on_foot() -> bool:
	return player != null and not main.driving and not main.flying


func weapon_name() -> String:
	return String(WEAPONS[cur]["name"])


func ammo_text() -> String:
	return "%d / %d" % [int(mag[cur]), int(WEAPONS[cur]["mag"])]


# ---------------------------------------------------------------- buttons

func swap_weapon() -> void:
	if not on_foot():
		return
	cur = 1 - cur
	reloading = false
	fire_t = 0.2
	hud.say(weapon_name(), 1.0)


func reload() -> void:
	if not on_foot() or reloading or int(mag[cur]) >= int(WEAPONS[cur]["mag"]):
		return
	reloading = true
	reload_total = float(WEAPONS[cur]["reload"])
	reload_t = reload_total
	_s_reload.play()


func toggle_bag() -> void:
	bag_open = not bag_open


func add_item(kind: String, n: int = 1) -> void:
	inv[kind] = int(inv.get(kind, 0)) + n


# ---------------------------------------------------------------- per frame

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var can := on_foot()
	fire_t -= delta
	aim_hold -= delta
	if reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			reloading = false
			mag[cur] = int(WEAPONS[cur]["mag"])
	player.gun_kind = cur if (can and not holstered) else -1
	player.aiming = can and not holstered and (firing or aim_hold > 0.0)
	if firing and can and not bag_open and not holstered:
		_try_fire()
	_tick_items(delta)


func _try_fire() -> void:
	if reloading or fire_t > 0.0:
		return
	if int(mag[cur]) <= 0:
		reload()
		return
	var w: Dictionary = WEAPONS[cur]
	fire_t = float(w["gap"])
	mag[cur] = int(mag[cur]) - 1
	aim_hold = 1.5
	if cur == 0:
		_s_pistol.play()
	else:
		_s_rifle.play()

	var cam: Camera3D = rig.cam
	var cam_fwd: Vector3 = -cam.global_transform.basis.z
	var origin: Vector3 = cam.global_position + cam_fwd * 1.5
	var fwd := cam_fwd
	if main.combat != null:   # v_007: light aim assist toward a bandit near the crosshair
		fwd = main.combat.assist_dir(origin, cam_fwd)
	var dir := _spread_dir(fwd, deg_to_rad(float(w["spread"])))
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 120.0)
	q.exclude = [player.get_rid()]
	var r: Dictionary = space.intersect_ray(q)
	var aim: Vector3 = origin + dir * 120.0
	var col: Object = null
	if not r.is_empty():
		aim = r["position"]
		col = r["collider"]

	var muzzle := _muzzle()
	var puff_col := Color(1.0, 0.85, 0.5)
	if col is Node:
		var cn := col as Node
		if main.combat != null and cn.is_in_group("enemy"):   # v_007: a bandit
			main.combat.hit_enemy(cn, aim, float(w["edmg"]))
			puff_col = Color(1.0, 0.1, 0.05)
		elif bool(cn.get_meta("cuttable", false)):   # trees, bushes, big rocks
			puff_col = _hit_cuttable(cn, r, w, dir)
		elif cn.is_in_group("tree"):
			_hit_tree(cn as Node3D)
			puff_col = Color(0.6, 0.45, 0.25)
	var tr_end := aim
	if muzzle.distance_to(aim) > 90.0:
		tr_end = muzzle + (aim - muzzle).normalized() * 90.0
	_tracer(muzzle, tr_end, Color(1.0, 0.9, 0.4))
	_puff(muzzle, Color(1.0, 0.8, 0.3), 0.13, 0.04)
	if not r.is_empty():
		_puff(aim, puff_col, 0.14, 0.12)
	rig.pitch = clampf(rig.pitch - (0.012 if cur == 0 else 0.005), rig.PITCH_MIN, rig.PITCH_MAX)
	if main.combat != null:   # v_007: shots are heard by bandits nearby
		main.combat.alert_near(player.global_position, 22.0 if cur == 0 else 35.0)


func _hit_tree(tree: Node3D) -> void:
	_s_chop.play()
	var hp := int(tree.get_meta("hp", TREE_HITS)) - 1
	tree.set_meta("hp", hp)
	if hp > 0:
		var tw := tree.create_tween()
		tw.tween_property(tree, "rotation:z", 0.06, 0.05)
		tw.tween_property(tree, "rotation:z", 0.0, 0.1)
		return
	var pos := tree.global_position + Vector3(0, 1.5, 0)
	tree.queue_free()
	for i in TREE_WOOD:
		_spawn_item("wood", pos + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4)))
	hud.say("Tree cut +%d wood" % TREE_WOOD, 1.5)


func _muzzle() -> Vector3:
	var yaw: float = player.pivot.rotation.y
	var f := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var rgt := Vector3(cos(yaw), 0.0, -sin(yaw))
	return player.global_position + (Vector3(0, 0.35, 0) + f * 0.85 + rgt * 0.25) * Util.CHAR_SCALE


func _spread_dir(fwd: Vector3, ang: float) -> Vector3:
	var b := Basis.looking_at(fwd, Vector3.UP)
	var a := randf() * TAU
	var m := randf() * ang
	return (b * Vector3(sin(m) * cos(a), sin(m) * sin(a), -cos(m))).normalized()


# ---------------------------------------------------------------- cut trees / bushes / rocks

# a bullet hit a tree / bush / rock (a CollisionShape3D with meta "kind" and "size"). Returns the colour of the hit puff.
func _hit_cuttable(body: Node, r: Dictionary, w: Dictionary, dir: Vector3) -> Color:
	var col := Color(0.6, 0.45, 0.25)
	var co := body as CollisionObject3D
	if co == null:
		return col
	var oid: int = co.shape_find_owner(int(r["shape"]))
	var cs := co.shape_owner_get_owner(oid) as Node3D
	if cs == null or not cs.has_meta("kind"):
		return col
	var kind := String(cs.get_meta("kind"))
	var hard := Hardness.for_kind(kind)
	if hard <= 0.0:
		return col   # not breakable
	if kind == "bush":
		col = Color(0.3, 0.55, 0.2)
	elif kind == "rock":
		col = Color(0.62, 0.62, 0.66)
		hard *= clampf(float(cs.get_meta("size", 1.0)), 0.4, 1.0)   # FIX: a small stone breaks faster than a big rock
	var id := cs.get_instance_id()
	var dmg: float = float(_cut_dmg.get(id, 0.0)) + (1.0 / float(w.get("hits", 10))) / hard
	if dmg < 0.999:
		_cut_dmg[id] = dmg
		_s_chop.play()
		return col
	_cut_dmg.erase(id)
	_cut_down(cs, kind, col, dir)
	return col


func _cut_down(cs: Node3D, kind: String, col: Color, dir: Vector3) -> void:
	var gp := cs.global_position
	var holder: Node = cs.get_parent().get_parent()   # shape -> body -> the node that holds the MultiMeshInstance3D copies
	var size := float(cs.get_meta("size", 1.0))
	_hide_copies(holder, gp)
	cs.set_deferred("disabled", true)
	SaveGame.note_cut(gp)   # v_012d: stays broken after restart (and when the 100 m square is built again)
	_s_chop.play()
	_debris.spawn(gp + Vector3(0, 0.8, 0), col, dir)
	if kind == "tree":
		var n := maxi(1, int(round(size * Hardness.TREE_WOOD_PER_SIZE)))
		for i in n:
			_spawn_item("wood", gp + Vector3(randf_range(-0.5, 0.5), 1.5, randf_range(-0.5, 0.5)))
		hud.say("Tree cut +%d wood" % n, 1.5)
	elif kind == "rock":
		var n2 := maxi(1, int(round(size * Hardness.ROCK_STONE_PER_SIZE)))
		for i in n2:
			_spawn_item("stone", gp + Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.5, 0.5)))
		hud.say("Rock broken +%d stone" % n2, 1.5)


# trees / bushes / rocks are copies in MultiMeshes: the copies standing at this place are shrunk to nothing
func _hide_copies(holder: Node, gp: Vector3) -> void:
	for ch in holder.get_children():
		var mmi := ch as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var mm := mmi.multimesh
		var gt := mmi.global_transform
		for i in mm.instance_count:
			var lt := mm.get_instance_transform(i)
			var o := gt * lt.origin
			if absf(o.x - gp.x) < 0.06 and absf(o.z - gp.z) < 0.06:
				mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), lt.origin))


# ---------------------------------------------------------------- item blocks (they fly out, then to the player)

func _spawn_item(kind: String, pos: Vector3) -> void:
	if _items.size() >= MAX_ITEMS:
		var old: Dictionary = _items.pop_front()
		(old["n"] as Node3D).queue_free()
		_collect(String(old["kind"]))
	var mi := Util.mi(Util.box(Vector3(0.3, 0.3, 0.3)), ITEM_COLORS.get(kind, Color.WHITE))
	add_child(mi)
	mi.global_position = pos
	mi.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
	_items.append({"n": mi, "kind": kind, "t": 0.0, "vel": Vector3(randf_range(-1.2, 1.2), randf_range(3.5, 5.0), randf_range(-1.2, 1.2))})


func _collect(kind: String) -> void:
	add_item(kind, 1)
	_s_pick.play()
	hud.pop(kind)


func _tick_items(delta: float) -> void:
	var i := _items.size() - 1
	while i >= 0:
		var it: Dictionary = _items[i]
		var n: Node3D = it["n"]
		it["t"] = float(it["t"]) + delta
		n.rotation.y += delta * 3.0
		if float(it["t"]) < 0.5:
			var v: Vector3 = it["vel"]
			v.y -= 14.0 * delta
			it["vel"] = v
			n.global_position += v * delta
			var gy: float = world.height_at(n.global_position.x, n.global_position.z) + 0.2
			if n.global_position.y < gy:
				n.global_position.y = gy
		elif on_foot():
			var target: Vector3 = player.global_position + Vector3(0, 0.5, 0)
			var to := target - n.global_position
			var d := to.length()
			var speed := 6.0 + 10.0 * (float(it["t"]) - 0.5)
			if d < 0.7:
				n.queue_free()
				_items.remove_at(i)
				_collect(String(it["kind"]))
				i -= 1
				continue
			n.global_position += to / d * minf(speed * delta, d)
		i -= 1


# ---------------------------------------------------------------- effects + sounds

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


func _player_snd(stream: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


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


func _click_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.55 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var a := exp(-t * 160.0)
		var b := 0.0
		if t >= 0.4:
			b = exp(-(t - 0.4) * 160.0)
		var v := (randf() * 2.0 - 1.0) * (a + b) * 0.6
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	return st
