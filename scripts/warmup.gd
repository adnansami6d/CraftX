extends RefCounted
# v1.1 step3 WARM-UP: runs at the end of loading (the loading screen is on top, the player sees nothing).
# It makes the phone draw everything once, so nothing "freezes" the first time you see it
# (looking around, BUILD button, first block, first glass, gun effects).
# Switch: Cfg.WARMUP in config.gd


const Cfg = preload("res://scripts/config.gd")


# trees are built in the background (textures first, then 200 own-shape trees in small pieces) and appear a little later:
# wait for ALL of them, so the warm-up below draws them too (conifers, banyans, coconut palms, big trees, new trees).
# v_006: waits up to 120 s (was 25 s) and tells the player what it waits for. A slow phone just gets a longer loading screen.
const WAIT_MAX_MS := 120000


static func _wait_trees(main) -> void:
	var tree: SceneTree = main.get_tree()
	var need: Array = []
	var label := {}
	if Cfg.NEW_BANYANS:
		need.append("Banyans")
		label["Banyans"] = "banyan trees"
	if Cfg.CONIFERS:
		need.append("Conifers")
		label["Conifers"] = "conifer trees"
	if Cfg.COCONUTS:
		need.append("CoconutPalms")
		label["CoconutPalms"] = "coconut palms"
	if Cfg.BIG_TREES:
		need.append("BigTrees")
		label["BigTrees"] = "big shade trees"
	if Cfg.NEW_TREES:
		need.append("MixTrees")
		label["MixTrees"] = "new trees"
	var t0 := Time.get_ticks_msec()
	var last_msg := -1000
	while Time.get_ticks_msec() - t0 < WAIT_MAX_MS:
		var missing: Array = []
		for n in need:
			if main.world.get_node_or_null(n) == null:
				missing.append(String(label[n]))
		if missing.is_empty():
			break
		if Time.get_ticks_msec() - last_msg > 400:
			last_msg = Time.get_ticks_msec()
			main.loader.set_progress(0.86, "Growing trees: %s ... %d s" % [", ".join(missing), (Time.get_ticks_msec() - t0) / 1000])
		await tree.process_frame


# v_007: waits until the combat (sounds, HUD) is completely built (up to 20 s)
static func _wait_combat(main) -> void:
	var tree: SceneTree = main.get_tree()
	var t0 := Time.get_ticks_msec()
	while main.combat != null and not main.combat.ready_ok and Time.get_ticks_msec() - t0 < 20000:
		main.loader.set_progress(0.995, "Preparing bandits...")
		await tree.process_frame


static func _frames(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.process_frame


static func _collect(n: Node, geos: Array, olds: Array, vis: Array) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		geos.append(g)
		olds.append(g.extra_cull_margin)
		vis.append(Vector2(g.visibility_range_begin, g.visibility_range_end))
	for c in n.get_children():
		_collect(c, geos, olds, vis)


static func run(main) -> void:
	var tree: SceneTree = main.get_tree()
	var rig = main.rig
	var player = main.player
	var build = main.build
	var shooter = main.shooter
	var touch = main.touch
	# loading screen above HUD + buttons, so nothing flashes while warming up
	main.layer.move_child(main.loader, main.layer.get_child_count() - 1)
	var yaw0: float = rig.yaw
	var pitch0: float = rig.pitch

	# 1/4: draw EVERY mesh once, also the far ones (culling AND the "far = not drawn" distance of banyans / palms are switched off for a few frames)
	await main._step(0.86, "Warming up 1/7...")
	await _wait_trees(main)
	main.loader.set_progress(0.87, "Warming up 1/7 (all trees)...")
	var geos: Array = []
	var olds: Array = []
	var vis: Array = []
	_collect(main, geos, olds, vis)
	var cam: Camera3D = rig.cam
	var far0: float = cam.far
	for g in geos:
		var gi := g as GeometryInstance3D
		gi.extra_cull_margin = 16384.0
		gi.visibility_range_begin = 0.0
		gi.visibility_range_end = 0.0
	cam.far = 4000.0
	await _frames(tree, 8)   # v_006: 8 frames (was 3): every tree mesh and material is surely drawn
	cam.far = far0
	for i in geos.size():
		if is_instance_valid(geos[i]):
			var g2 := geos[i] as GeometryInstance3D
			g2.extra_cull_margin = float(olds[i])
			var vr: Vector2 = vis[i]
			g2.visibility_range_begin = vr.x
			g2.visibility_range_end = vr.y

	# 2/4: look all around (6 directions x level / up / down)
	await main._step(0.90, "Warming up 2/7...")
	for pitch in [0.04, -1.2, 0.9]:
		rig.pitch = pitch
		for k in 6:
			rig.yaw = yaw0 + TAU * float(k) / 6.0
			await _frames(tree, 3)
	rig.yaw = yaw0
	rig.pitch = pitch0
	await _frames(tree, 2)

	tree.call_group("stream_warm", "free_warm")   # v_001: the hidden rock / reed / puddle copies have done their job

	# v_003: Label3D draws every new letter / digit the first time it is needed (freeze). Make all of them now.
	var labs := tree.get_nodes_in_group("rail_label")
	var old_txt: Array = []
	for lb in labs:
		old_txt.append((lb as Label3D).text)
		(lb as Label3D).text = "LEAVES ARRIVING TRAIN IN\n0123456789:-"
	await _frames(tree, 3)
	for i in labs.size():
		(labs[i] as Label3D).text = String(old_txt[i])

	# 3/4: BUILD mode: buttons + text, ghost, outline, one block of every type (glass too)
	await main._step(0.94, "Warming up 3/7...")
	touch.build_mode = true
	await build.warmup()
	touch.build_mode = false

	# 4/4: gun effects (tracer + smoke)
	await main._step(0.98, "Warming up 4/7...")
	var f: Vector3 = -rig.cam.global_transform.basis.z
	var p: Vector3 = player.global_position + Vector3(0, 1.5, 0) + f * 4.0
	shooter._tracer(p, p + f * 3.0, Color(1.0, 0.8, 0.3))
	shooter._puff(p, Color(1.0, 0.7, 0.3), 0.15, 0.25)
	shooter._puff(p + Vector3(0, 0.5, 0), Color(0.6, 0.55, 0.5), 0.3, 0.25)
	await _frames(tree, 3)

	# 5/6: driving + helicopter: drive buttons (GAS, BRAKE, GET OUT, horn icon), speed text, engine / horn / crash sound, heli buttons
	await main._step(0.99, "Warming up 5/7...")
	var tractor = main.tractor
	touch.drive_mode = true
	touch.action_visible = true
	touch.action_enabled = true
	touch.action_text = "GET OUT"
	main.hud.info_text = "0123456789 km/h alt m"
	main.heli_ui.visible = true
	tractor.snd_engine.volume_db = -80.0
	tractor.snd_engine.play()
	tractor.snd_crash.volume_db = -80.0
	tractor.snd_crash.play()
	main.horn.volume_db = -80.0
	main.horn.play()
	tractor.set_lights(true)   # v_002: draw the headlights once, so the first night drive does not freeze
	main.heli.set_lights(true)
	await _frames(tree, 4)
	tractor.set_lights(false)
	main.heli.set_lights(false)
	tractor.snd_engine.stop()
	tractor.snd_crash.stop()
	main.horn.stop()
	main.horn.volume_db = -4.0
	main.heli_ui.visible = false
	main.hud.info_text = ""
	touch.drive_mode = false
	touch.action_text = "GET IN"
	touch.action_visible = false
	touch.release_all()
	await _frames(tree, 2)

	# 6/7: v_008 torch: flame shader, glow, real light, sparks, place click + crackle (muted), then removed
	await main._step(0.992, "Warming up 6/7 (torches)...")
	await build.warmup_torch()

	# 7/7: v_007 combat: both bandit models, health label, shot / hit effects, pickup, flag, combat HUD, sounds
	if main.combat != null:
		await main._step(0.995, "Warming up 7/7 (bandits)...")
		await _wait_combat(main)
		await main.combat.warmup()
