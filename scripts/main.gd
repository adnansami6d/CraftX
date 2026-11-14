extends Node3D
# MY PLANT main: builds the world (the Fx99 map, fx_map.gd), the character, tractor, helicopter, camera, controls, gun.
#
# Where things come from (demo version):
#   Farm_v10 : camera (camera_rig.gd), tractor turning + engine / crash sound (tractor.gd, sfx.gd, audio_lib.gd)
#   Fx99     : character (player.gd, human.gd, rig_anim.gd, characters/valery.glb), trees, helicopter, touch controls
#   Fx99     : the map (fx_map.gd, props.gd, coast.gd, railway.gd, train.gd ...).   new: shooter.gd (gun, items), build.gd, hud.gd

const Util = preload("res://scripts/util.gd")
const PlayerScript = preload("res://scripts/player.gd")
const CameraRigScript = preload("res://scripts/camera_rig.gd")
const TouchScript = preload("res://scripts/touch_controls.gd")
const Catalog = preload("res://scripts/catalog.gd")
const LoadingScript = preload("res://scripts/loading.gd")
const TractorScript = preload("res://scripts/tractor.gd")
const HeliScript = preload("res://scripts/helicopter.gd")
const HeliUiScript = preload("res://scripts/heli_ui.gd")
const FxMapScript = preload("res://scripts/fx_map.gd")
const ShooterScript = preload("res://scripts/shooter.gd")
const HudScript = preload("res://scripts/hud.gd")
const BuildScript = preload("res://scripts/build.gd")
const BiomeScript = preload("res://scripts/biome.gd")
const Cfg = preload("res://scripts/config.gd")
const SkyFx = preload("res://scripts/sky_fx.gd")
const DayNight = preload("res://scripts/daynight.gd")
const DebugOverlayScript = preload("res://scripts/debug_overlay.gd")
const FloraScript = preload("res://scripts/flora.gd")
const TreeBanyanScript = preload("res://scripts/tree_banyan.gd")
const CoconutScript = preload("res://scripts/coconut.gd")
const ConiferScript = preload("res://scripts/tree_conifer.gd")
const BlobScript = preload("res://scripts/tree_blob.gd")
const MixScript = preload("res://scripts/tree_mix.gd")
const WarmupScript = preload("res://scripts/warmup.gd")
const CombatScript = preload("res://scripts/combat.gd")
const SaveGameScript = preload("res://scripts/savegame.gd")

var layer: CanvasLayer
var loader
var _game_ready := false
var world
var player
var rig
var touch
var tractor
var heli
var heli_ui
var shooter
var build
var combat   # v_007: bandits / health (scripts/combat.gd), null when Cfg.COMBAT is false
var hud
var debug_overlay
var horn: AudioStreamPlayer
var driving := false
var flying := false
var savegame   # v_012d: saves + restores everything (scripts/savegame.gd)
var daynight   # F11: day / night clock (scripts/daynight.gd)
var sky_shader_mat: ShaderMaterial   # F10: sky with clouds (time is updated in _process)
var sun_light: DirectionalLight3D   # F8: the sun (day / night later)


func _ready() -> void:
	randomize()
	get_viewport().scaling_3d_scale = Cfg.RENDER_SCALE   # v1.0: lighter graphics (1.0 = full)
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA   # smooths the far block edges (no shimmer)
	layer = CanvasLayer.new()
	add_child(layer)
	loader = LoadingScript.new()
	layer.add_child(loader)
	loader.set_progress(0.05, "Loading...")
	await get_tree().process_frame   # make sure the loading screen is drawn first
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout   # logo is on screen before the heavy work starts
	# put your character (.glb/.gltf/.tscn) in res://characters/ -> it is used automatically. No file = built-in character.
	var custom: Array = Catalog.list("res://characters")
	await _start_game(String(custom[0]) if not custom.is_empty() else "")
	loader.set_progress(1.0, "Ready")
	await get_tree().create_timer(0.5).timeout
	set_clock(Cfg.START_HOUR)   # a new game always begins at 06:00 morning ...
	savegame = SaveGameScript.new()
	add_child(savegame)
	savegame.start(self)   # ... a saved game goes on exactly where it was left (clock, place, health, bag, broken trees ...)
	_game_ready = true
	loader.queue_free()


# sets the game clock and updates sun, sky and light at once
func set_clock(h: float) -> void:
	if daynight == null:
		return
	daynight.hour = fposmod(h, 24.0)
	daynight._step_t = 99.0   # turn the light to the new time right now
	daynight.update(0.0)


func _step(p: float, m: String) -> void:
	loader.set_progress(p, m)
	await get_tree().process_frame
	await get_tree().process_frame


# loads a .tscn/.glb and returns it as a Node3D (or null if it fails)
func _load_scene(path: String) -> Node3D:
	if path == "":
		return null
	var res = load(path)
	if res is PackedScene:
		var n = res.instantiate()
		if n is Node3D:
			return n
		n.queue_free()
	push_warning("Could not load: " + path)
	return null


func _make_environment() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_2X if Cfg.MSAA else Viewport.MSAA_DISABLED   # F11b
	var we := WorldEnvironment.new()
	var env := Environment.new()
	# F10: own sky shader = blue sky + cloud shapes + real sun disc (the sun disc is drawn by the shader,
	# the DirectionalLight below only lights the world)
	var sun_dir := Basis.from_euler(Vector3(deg_to_rad(-Cfg.SUN_ELEVATION), deg_to_rad(Cfg.SUN_AZIMUTH), 0.0)).z
	sky_shader_mat = SkyFx.make_material(sun_dir, Cfg.CLOUD_COVER if Cfg.CLOUDS else 0.0)
	var sky := Sky.new()
	sky.sky_material = sky_shader_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32   # ambient light is a plain colour, so the sky cube map can be tiny
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Cfg.AMBIENT_COLOR if Cfg.SUN else Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = Cfg.AMBIENT_ENERGY if Cfg.SUN else 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC if (Cfg.SUN and Cfg.SUN_FILMIC) else Environment.TONE_MAPPER_LINEAR
	if Cfg.SUN and Cfg.SUN_FILMIC:   # F9: a little more contrast, colours not too loud
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.1
		env.adjustment_saturation = 0.95
	env.tonemap_exposure = Cfg.EXPOSURE
	env.fog_enabled = Cfg.FOG   # F10: false = no fog
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	if Cfg.SUN:   # F8: real sun
		sun.rotation_degrees = Vector3(-Cfg.SUN_ELEVATION, Cfg.SUN_AZIMUTH, 0.0)
		sun.light_color = Cfg.SUN_COLOR
		sun.light_energy = Cfg.SUN_ENERGY
		sun.light_angular_distance = 2.0   # size of the sun disc in the sky (real sun 0.5, bigger is easier to see)
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY   # F10: the sun disc comes from the sky shader
		sun.shadow_enabled = Cfg.SHADOWS
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL   # one split = the cheapest
		sun.directional_shadow_max_distance = Cfg.SHADOW_DISTANCE
		sun.directional_shadow_fade_start = 0.85
		sun.shadow_bias = 0.06
		sun.shadow_normal_bias = 1.0
		sun.shadow_blur = 1.6   # F9: softer shadow edge (the blocky edge in the screenshot)
	else:
		sun.rotation_degrees = Vector3(-50, 30, 0)
		sun.light_energy = 0.55
		sun.shadow_enabled = false
	sun_light = sun
	add_child(sun)
	if Cfg.DAY_NIGHT:   # F11
		daynight = DayNight.new()
		daynight.setup(sun, env, sky_shader_mat)


func _start_game(char_path: String) -> void:
	await _step(0.15, "Building the world...")
	_make_environment()
	world = FxMapScript.new()   # the Fx99 map is the only world (fx_map.gd)
	add_child(world)
	world.build()
	var start: Vector3 = world.spawn

	await _step(0.5, "Spawning...")
	player = PlayerScript.new()
	player.position = start
	add_child(player)
	var model := _load_scene(char_path)
	if model != null:
		player.use_model(model)
	tractor = TractorScript.new()
	tractor.position = start + Vector3(5, -0.95, -3)
	add_child(tractor)
	tractor.setup_ground(Callable(world, "height_at"))
	heli = HeliScript.new()
	heli.position = start + Vector3(-9, 0, -4)
	heli.rotation.y = 0.6
	heli.area_check = Callable(world, "contains")
	add_child(heli)

	await _step(0.75, "Preparing controls...")
	rig = CameraRigScript.new()
	rig.ground = Callable(world, "height_at")
	add_child(rig)
	rig.set_target(player)

	hud = HudScript.new()
	layer.add_child(hud)
	touch = TouchScript.new()
	layer.add_child(touch)
	touch.hidden_ids = ["hitch", "poi"]   # buttons of the farm game that My Plant does not use
	touch.look_dragged.connect(func(dx: float, dy: float) -> void: rig.look(dx, dy))
	touch.jump_pressed.connect(func() -> void: player.jump())
	touch.run_pressed.connect(func() -> void: player.toggle_run())
	touch.action_pressed.connect(_on_action)

	shooter = ShooterScript.new()
	add_child(shooter)
	shooter.hud = hud
	shooter.setup(self, player, rig, touch, world)
	hud.shooter = shooter
	hud.main = self
	touch.reload_pressed.connect(shooter.reload)
	touch.swap_pressed.connect(shooter.swap_weapon)
	touch.bag_pressed.connect(shooter.toggle_bag)

	build = BuildScript.new()
	add_child(build)
	build.setup(self, player, rig, touch, shooter, hud, world)
	touch.slot_pressed.connect(build.select_block)
	touch.hotbar_n = build.TYPES.size()

	if Cfg.COMBAT:   # v_007: bandits, health, combat HUD (switch: config.gd)
		combat = CombatScript.new()
		add_child(combat)
		combat.setup(self, player, rig, touch, layer)

	heli_ui = HeliUiScript.new()
	layer.add_child(heli_ui)
	heli_ui.exit_pressed.connect(_leave_heli)
	heli_ui.look_dragged.connect(func(dx: float, dy: float) -> void: rig.look(dx, dy))

	horn = _make_horn()

	if Cfg.DEBUG_OVERLAY:   # v1.1: small info text (FPS, position ...). Switch: scripts/config.gd
		debug_overlay = DebugOverlayScript.new()
		debug_overlay.main = self
		layer.add_child(debug_overlay)
		debug_overlay.set_value("world", "FX99 MAP   %d m" % int(world.map_half * 2.0))
		debug_overlay.set_value("flora", FloraScript.self_test())   # F2
		debug_overlay.set_value("ground", BiomeScript.report)   # F16

	if Cfg.NEW_BANYANS:   # F5: 30 banyans (switch: config.gd)
		var banyan_report := func(s: String) -> void:
			if debug_overlay != null:
				debug_overlay.set_value("banyan", s)
		TreeBanyanScript.place_all(world, banyan_report)

	if Cfg.CONIFERS:   # 40 conifers (switch: config.gd)
		var conifer_report := func(s: String) -> void:
			if debug_overlay != null:
				debug_overlay.set_value("conifer", s)
		ConiferScript.wait_banyans = Cfg.NEW_BANYANS
		ConiferScript.place_all(world, conifer_report)

	if Cfg.BIG_TREES:   # 100 big shade trees (switch: config.gd)
		var blob_report := func(s: String) -> void:
			if debug_overlay != null:
				debug_overlay.set_value("bigtree", s)
		BlobScript.wait_banyans = Cfg.NEW_BANYANS
		BlobScript.wait_conifers = Cfg.CONIFERS
		BlobScript.place_all(world, blob_report)

	if Cfg.NEW_TREES:   # v_006: 100 new flowering / autumn / weeping / umbrella trees (switch: config.gd). Placed after the big trees.
		var mix_report := func(s: String) -> void:
			if debug_overlay != null:
				debug_overlay.set_value("newtree", s)
		var mix_wait: Array = []
		if Cfg.NEW_BANYANS:
			mix_wait.append("Banyans")
		if Cfg.CONIFERS:
			mix_wait.append("Conifers")
		if Cfg.BIG_TREES:
			mix_wait.append("BigTrees")
		MixScript.wait_nodes = mix_wait
		MixScript.place_all(world, mix_report)

	if Cfg.COCONUTS:   # F7: coconut palms on all beaches (switch: config.gd)
		var coco_report := func(s: String) -> void:
			if debug_overlay != null:
				debug_overlay.set_value("coconut", s)
		CoconutScript.place_all(world, coco_report)

	if Cfg.SUN and debug_overlay != null:   # F8
		debug_overlay.set_value("sun", "elev %d az %d  shadows %s %d m" % [int(Cfg.SUN_ELEVATION), int(Cfg.SUN_AZIMUTH), "ON" if Cfg.SHADOWS else "off", int(Cfg.SHADOW_DISTANCE)])

	if Cfg.MOUNTAIN and debug_overlay != null:   # F6
		debug_overlay.set_value("mountain", world.mountain_info)

	if Cfg.WARMUP:   # v1.1 step3: draw everything once while the loading screen is still on top
		await WarmupScript.run(self)


# two-note horn made from math (no sound file needed). Loops while the HORN button is held.
func _make_horn() -> AudioStreamPlayer:
	var rate := 22050
	var n := 4410   # 0.2 s = exactly 60 cycles of 300 Hz and 80 cycles of 400 Hz, so the loop has no click
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var v := 0.0
		for f in [300.0, 400.0]:
			v += sin(TAU * f * t) + 0.5 * sin(TAU * 2.0 * f * t) + 0.25 * sin(TAU * 3.0 * f * t)
		data.encode_s16(i * 2, int(clampf(v * 0.3, -1.0, 1.0) * 22000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n
	var pl := AudioStreamPlayer.new()
	pl.stream = st
	pl.volume_db = -4.0
	add_child(pl)
	return pl


# ---------------------------------------------------------------- helpers for the HUD

func actor_position() -> Vector3:
	if flying:
		return heli.global_position
	if driving:
		return tractor.global_position
	return player.global_position


func map_label() -> String:
	return "Fx99"


# ---------------------------------------------------------------- get in / out

func _near_tractor() -> bool:
	return player.global_position.distance_to(tractor.global_position) < 4.5


func _near_heli() -> bool:
	return player.global_position.distance_to(heli.global_position) < 6.0


func _leave_heli() -> void:
	if not flying or not heli.on_ground():
		return
	flying = false
	heli.stop_flight()
	heli_ui.release_all()
	heli_ui.visible = false
	touch.visible = true
	var side: Vector3 = heli.global_transform.basis.x * -3.2
	player.stand(self, heli.global_position + side + Vector3(0, 1.0, 0))
	rig.set_target(player)
	touch.release_all()


func _on_action() -> void:
	if flying:
		return
	if not driving and _near_heli():
		flying = true
		player.sit(heli.seat)
		heli.start_flight()
		heli_ui.visible = true
		touch.visible = false
		touch.release_all()
		rig.set_target(heli, 17.0, 3.0, true)
		return
	if driving:
		if absf(tractor.speed) > 1.5:
			return
		driving = false
		horn.stop()
		tractor.stop_inputs()
		var side: Vector3 = tractor.global_transform.basis.x * -2.3
		player.stand(self, tractor.global_position + side + Vector3(0, 1.0, 0))
		rig.set_target(player)
		touch.release_all()
	elif _near_tractor():
		driving = true
		player.sit(tractor.seat)
		rig.set_target(tractor, 6.5, 2.0, true)   # v10 tractor camera
		touch.release_all()


# fell out of the world: back to the start
func _respawn_player() -> void:
	if flying:
		flying = false
		heli.stop_flight()
		heli_ui.release_all()
		heli_ui.visible = false
		touch.visible = true
	if driving:
		driving = false
		horn.stop()
		tractor.stop_inputs()
	player.stand(self, world.spawn)
	rig.set_target(player)
	touch.release_all()


# ---------------------------------------------------------------- per frame

func _physics_process(_delta: float) -> void:
	if not _game_ready:
		return
	# safety net: anything that fell out of the world comes back to the start
	if not driving and not flying and player.global_position.y < -30.0:
		_respawn_player()
	if tractor.global_position.y < -30.0:
		tractor.global_position = world.spawn + Vector3(5, 0.5, -3)
		tractor.speed = 0.0
		tractor.reset_physics_interpolation()
	if heli.global_position.y < -30.0 and not flying:
		heli.global_position = world.spawn + Vector3(-9, 1.0, -4)
		heli.reset_physics_interpolation()
	# no fuel system in the demo
	tractor.fuel = tractor.fuel_cap
	heli.fuel = heli.fuel_cap

	player.cam_yaw = rig.yaw
	shooter.holstered = touch.build_mode
	shooter.firing = bool(touch.held["fire"]) and not touch.blocked and not touch.build_mode and not (combat != null and combat.dead)
	if combat != null:
		combat.firing = shooter.firing
	if flying:
		var a: Vector3 = heli_ui.axes()
		heli.turn = a.x
		heli.fwd = a.y
		heli.lift = a.z
		heli_ui.can_exit = heli.on_ground() and absf(heli.speed) < 1.5
	elif driving:
		tractor.gas = touch.held["gas"]
		tractor.brake = touch.held["brake"]
		tractor.steer = float(touch.held["right"]) - float(touch.held["left"])
	else:
		player.move_dir = Vector2.ZERO if (combat != null and combat.dead) else touch.move_dir


var _cloud_t := 0.0   # F10: cloud clock


func _process(_delta: float) -> void:
	if daynight != null:   # F11: sun, sky, light colours follow the clock
		daynight.update(_delta if _game_ready else 0.0)   # clock is frozen while loading: the game always starts at Cfg.START_HOUR (06:00)
		if debug_overlay != null:
			debug_overlay.set_value("time", daynight.clock_text())
	if daynight != null and Cfg.LIGHTS and _game_ready:   # v_002: headlights while driving / flying at dusk and night
		var dark: bool = daynight.sun_elev < Cfg.LIGHT_ON_ELEV
		tractor.set_lights(driving and dark)
		heli.set_lights(flying and dark)
	if sky_shader_mat != null and Cfg.CLOUDS:   # F10: clouds drift
		_cloud_t += _delta * Cfg.CLOUD_SPEED
		sky_shader_mat.set_shader_parameter("cloud_time", _cloud_t)
	if not _game_ready:
		return
	touch.run_on = player.running
	touch.swap_text = shooter.weapon_name()
	touch.next_text = build.block_name()
	touch.drive_mode = driving
	touch.work_available = false
	touch.seed_available = false
	if flying:
		hud.info_text = "%d km/h   alt %d m" % [int(round(heli.kmh())), int(round(heli.height()))]
		return
	if driving:
		hud.info_text = "%d km/h" % int(round(tractor.kmh()))
		if touch.held["horn"] and not horn.playing:
			horn.play()
		elif not touch.held["horn"] and horn.playing:
			horn.stop()
		touch.action_visible = true
		touch.action_text = "GET OUT"
		touch.action_enabled = absf(tractor.speed) < 1.5
	else:
		hud.info_text = ""
		var near := _near_tractor() or _near_heli()
		touch.action_visible = near
		touch.action_text = "GET IN"
		touch.action_enabled = near
