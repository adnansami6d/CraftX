extends RefCounted
# FOREST PLAN F3: bark + leaf textures made by CODE (no image files).
#   FloraTex.tex["bark"], ["bark_n"] (normal map), ["broad"], ["needle"], ["palm"]  = ImageTexture (with mipmaps)
#   FloraTex.bark_material(), FloraTex.leaf_material("broad" / "needle" / "palm")   = ready materials for F4 - F12
# The pixels are made in a background thread (WorkerThreadPool): the game does not freeze.
# make_test_props() puts one bark trunk + 3 leaf cards near the spawn so the owner can look at the result.

const BW := 256       # bark tile width  (wraps around a trunk, seamless)
const BH := 512       # bark tile height (seamless)
const LEAF := 512     # leaf card size (square)

static var tex := {}
static var _task := -1
static var _imgs := {}
static var _t0 := 0


# ---------------------------------------------------------------------------- materials
static func bark_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex["bark"]
	m.normal_enabled = true
	m.normal_texture = tex["bark_n"]
	m.normal_scale = 1.3
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_scale = Vector3(1.0, 1.4, 1.0)   # one tile = about 2.5 m round x 5 m high on a normal trunk
	return m


# alpha SCISSOR (never alpha blend: sorting + overdraw on phones), two-sided
static func leaf_material(kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex[kind]
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.8
	m.backlight_enabled = true
	m.backlight = Color(0.32, 0.38, 0.14)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


# ---------------------------------------------------------------------------- bark
# noise on a cylinder (x wraps round, y cross-faded) = seamless in both directions
static func _pn(n: FastNoiseLite, px: float, py: float, z: float, zper: float, t: float) -> float:
	return lerpf(n.get_noise_3d(px, py, z), n.get_noise_3d(px, py, z - zper), t)


static func bark_images(seed_: int) -> Array:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 1.0
	n.seed = seed_

	var hgt := PackedFloat32Array()
	hgt.resize(BW * BH)
	var moss := PackedFloat32Array()
	moss.resize(BW * BH)
	for y in BH:
		var t := float(y) / float(BH)
		for x in BW:
			var a := TAU * float(x) / float(BW)
			var cx := cos(a)
			var sy := sin(a)
			# long vertical cracks: x detail high, y stretched
			var g1 := _pn(n, cx * 2.4, sy * 2.4, t * 1.3, 1.3, t)
			var g2 := _pn(n, cx * 5.5 + 31.0, sy * 5.5 + 31.0, t * 2.6, 2.6, t)
			var fn := _pn(n, cx * 11.0 + 7.0, sy * 11.0 + 7.0, t * 9.0, 9.0, t)
			var mv := _pn(n, cx * 0.9 + 50.0, sy * 0.9 + 50.0, t * 0.6, 0.6, t)
			# cracks are low (dark), plates between them are high
			var h := 0.62 * smoothstep(0.0, 0.28, absf(g1)) + 0.25 * smoothstep(0.0, 0.3, absf(g2)) \
					+ 0.10 * (fn * 0.5 + 0.5) + 0.03
			hgt[y * BW + x] = clampf(h, 0.0, 1.0)
			# moss patch: wanders with noise, more at the foot of the trunk
			moss[y * BW + x] = smoothstep(0.05, 0.35, mv + 0.18 * (1.0 - t))

	# knots: dark hollow with a raised ring (wrap-around safe)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for i in 5:
		var kx := rng.randf() * float(BW)
		var ky := rng.randf() * float(BH)
		var kr := 9.0 + rng.randf() * 9.0
		var ir := int(kr * 1.4)
		for yy in range(-ir, ir + 1):
			for xx in range(-ir, ir + 1):
				var d := sqrt(float(xx * xx + yy * yy)) / kr
				if d >= 1.3:
					continue
				var px := posmod(int(kx) + xx, BW)
				var py := posmod(int(ky) + yy, BH)
				var idx := py * BW + px
				var ring := 1.0 - smoothstep(0.0, 0.25, absf(d - 0.85))
				var hollow := 1.0 - smoothstep(0.35, 0.7, d)
				var h2 := lerpf(hgt[idx], 1.0, ring * 0.9)
				h2 = lerpf(h2, 0.04, hollow)
				hgt[idx] = h2
				moss[idx] *= (1.0 - hollow)

	var alb := Image.create(BW, BH, false, Image.FORMAT_RGB8)
	var nrm := Image.create(BW, BH, false, Image.FORMAT_RGB8)
	var dark := Color(0.06, 0.045, 0.035)
	var light := Color(0.40, 0.32, 0.24)
	var mossc := Color(0.17, 0.30, 0.08)
	var k := 3.0   # normal strength
	for y in BH:
		var y0 := posmod(y - 1, BH)
		var y1 := posmod(y + 1, BH)
		for x in BW:
			var x0 := posmod(x - 1, BW)
			var x1 := posmod(x + 1, BW)
			var h := hgt[y * BW + x]
			var c := dark.lerp(light, pow(h, 0.85))
			# small warm / cold colour change from the height detail
			var warm := (hgt[y * BW + x1] - hgt[y * BW + x0]) * 0.35
			c = Color(c.r + warm, c.g + warm * 0.6, c.b, 1.0)
			var ms := moss[y * BW + x]
			if ms > 0.0:
				c = c.lerp(mossc * (0.45 + h * 0.7), ms * 0.85)
			alb.set_pixel(x, y, c)
			var dx := hgt[y * BW + x1] - hgt[y * BW + x0]
			var dy := hgt[y1 * BW + x] - hgt[y0 * BW + x]
			var v := Vector3(-dx * k, dy * k, 1.0).normalized()
			nrm.set_pixel(x, y, Color(v.x * 0.5 + 0.5, v.y * 0.5 + 0.5, v.z * 0.5 + 0.5, 1.0))
	alb.generate_mipmaps()
	nrm.generate_mipmaps()
	return [alb, nrm]


# ---------------------------------------------------------------------------- leaf drawing helpers
static func _px(img: Image, px: int, py: int, c: Color) -> void:
	if px >= 0 and py >= 0 and px < LEAF and py < LEAF:
		img.set_pixel(px, py, c)


static func _line(img: Image, a: Vector2, b: Vector2, c: Color, r: float) -> void:
	var ln := a.distance_to(b)
	var steps := int(ln / 0.7) + 1
	var ri := int(ceil(r))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				if float(dx * dx + dy * dy) <= r * r + 0.25:
					_px(img, int(p.x) + dx, int(p.y) + dy, c)


# one leaf: base point, angle (radians, image y goes down), length, half width, colour
static func _leaf(img: Image, bx: float, by: float, ang: float, length: float, width: float,
		base: Color, rng: RandomNumberGenerator, vein: float, nz: FastNoiseLite) -> void:
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	var tint := 0.82 + rng.randf() * 0.36   # every leaf a little different
	var u := 0.0
	while u <= length:
		var f := u / length
		var w := width * pow(sin(PI * pow(f, 0.8)), 0.8)
		var v := -w
		while v <= w:
			var p := Vector2(bx, by) + dir * u + perp * v
			var side := absf(v) / maxf(w, 0.001)
			var shade := tint * (1.0 + nz.get_noise_2d(p.x * 0.9, p.y * 0.9) * 0.22)
			shade *= 1.0 - 0.38 * smoothstep(0.7, 1.0, side)   # darker edge
			shade *= 0.88 + 0.22 * f                             # lighter tip
			var c := Color(base.r * shade, base.g * shade, base.b * shade, 1.0)
			if absf(v) < 1.0:
				c = c.lerp(Color(0.62, 0.72, 0.35, 1.0), 0.55)   # midrib
			elif vein > 0.0 and w > 6.0:
				var vp := fposmod(f * vein - side * 0.9, 1.0)
				if vp < 0.06:
					c = c.lerp(Color(0.55, 0.68, 0.30, 1.0), 0.35)   # side veins
			_px(img, int(p.x), int(p.y), c)
			v += 0.6
		u += 0.6


static func _new_card(bg: Color) -> Image:
	var img := Image.create(LEAF, LEAF, false, Image.FORMAT_RGBA8)
	# transparent, but the same colour as the leaf: mipmaps do not get dark edges
	img.fill(Color(bg.r, bg.g, bg.b, 0.0))
	return img


static func _noise2(seed_: int) -> FastNoiseLite:
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 0.05
	nz.seed = seed_
	return nz


# ---------------------------------------------------------------------------- leaf cards
# broad leaves (banyan, shal ...): a twig with leaves on both sides
static func broad_image(seed_: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var nz := _noise2(seed_)
	var base := Color(0.20, 0.40, 0.10)
	var img := _new_card(base)
	var stem := Color(0.28, 0.20, 0.12)
	_line(img, Vector2(256.0, 508.0), Vector2(256.0, 40.0), stem, 2.0)
	for i in 8:
		var y := 470.0 - float(i) * 52.0
		var ll := 170.0 - float(i) * 6.0 + rng.randf() * 14.0
		for side: float in [-1.0, 1.0]:
			var ang := -PI * 0.5 + side * (0.85 + rng.randf() * 0.25)
			_leaf(img, 256.0, y - (4.0 if side > 0.0 else 0.0), ang, ll, 34.0 + rng.randf() * 6.0, base, rng, 7.0, nz)
	_leaf(img, 256.0, 62.0, -PI * 0.5, 120.0, 30.0, base, rng, 7.0, nz)
	img.generate_mipmaps()
	return img


# pine / fir twig: a stem with many thin needles
static func needle_image(seed_: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ + 11
	var nz := _noise2(seed_ + 11)
	var base := Color(0.10, 0.27, 0.12)
	var img := _new_card(base)
	var stem := Color(0.25, 0.17, 0.10)
	_line(img, Vector2(256.0, 508.0), Vector2(256.0, 24.0), stem, 2.2)
	var y := 480.0
	while y > 40.0:
		var f := (480.0 - y) / 440.0
		var nlen := 95.0 * pow(sin(PI * clampf(f * 0.9 + 0.08, 0.0, 1.0)), 0.6) + 20.0
		for side: float in [-1.0, 1.0]:
			var a := 0.9 + rng.randf() * 0.35
			var tip := Vector2(256.0 + side * sin(a) * nlen, y - cos(a) * nlen)
			var shade := 0.8 + rng.randf() * 0.4 + nz.get_noise_2d(256.0, y) * 0.2
			var c := Color(base.r * shade, base.g * shade, base.b * shade, 1.0)
			_line(img, Vector2(256.0, y), tip, c, 1.3)
		y -= 5.0
	img.generate_mipmaps()
	return img


# palm frond: an arched middle rib with narrow leaflets on both sides
static func palm_image(seed_: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ + 23
	var nz := _noise2(seed_ + 23)
	var base := Color(0.18, 0.38, 0.09)
	var img := _new_card(base)
	var p0 := Vector2(40.0, 480.0)
	var p1 := Vector2(120.0, 90.0)
	var p2 := Vector2(470.0, 150.0)
	var prev := p0
	var steps := 64
	# rib first, leaflets on top
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var p := p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		_line(img, prev, p, Color(0.30, 0.24, 0.12, 1.0), 2.4 - 1.4 * t)
		prev = p
	prev = p0
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var p := p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		var tg := (p - prev).normalized()
		prev = p
		if t < 0.12:
			continue
		var llen := 125.0 * pow(sin(PI * clampf(0.08 + 0.85 * t, 0.0, 1.0)), 0.55) + 18.0
		for side: float in [-1.0, 1.0]:
			var ang := tg.angle() + side * (0.95 + rng.randf() * 0.2)
			_leaf(img, p.x, p.y, ang, llen, 5.5, base, rng, 0.0, nz)
	img.generate_mipmaps()
	return img


# ---------------------------------------------------------------------------- background thread
static func start() -> void:
	if _task != -1 or tex.has("bark"):
		return
	_t0 = Time.get_ticks_msec()
	_task = WorkerThreadPool.add_task(_work, false, "FloraTex")


static func _work() -> void:
	var b := bark_images(1337)
	_imgs["bark"] = b[0]
	_imgs["bark_n"] = b[1]
	_imgs["broad"] = broad_image(2024)
	_imgs["needle"] = needle_image(2024)
	_imgs["palm"] = palm_image(2024)


# main thread: pixels -> ImageTexture
static func _finish() -> void:
	for key in _imgs:
		tex[key] = ImageTexture.create_from_image(_imgs[key])
	_imgs.clear()
	_task = -1


# ---------------------------------------------------------------------------- test props
# report = Callable(String) -> void   (we tell the overlay what happened)
static func make_test_props(world: Node, pos: Vector3, report: Callable) -> void:
	start()
	report.call("flora_tex: making textures ...")
	var t := Timer.new()
	t.wait_time = 0.2
	world.add_child(t)
	t.timeout.connect(_poll.bind(t, world, pos, report))
	t.start()


static func _poll(t: Timer, world: Node, pos: Vector3, report: Callable) -> void:
	if _task != -1:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_finish()
	t.queue_free()
	_build_props(world, pos)
	report.call("flora_tex: OK  bark 256x512 + 3 leaf cards, %d ms" % (Time.get_ticks_msec() - _t0))


static func _build_props(world: Node, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "FloraTexTest"
	world.add_child(root)
	var trunk := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.38
	cm.bottom_radius = 0.5
	cm.height = 5.0
	cm.radial_segments = 24
	cm.rings = 1
	trunk.mesh = cm
	trunk.material_override = bark_material()
	root.add_child(trunk)
	trunk.position = Vector3(pos.x - 4.0, _ground(world, pos.x - 4.0, pos.z) + 2.5, pos.z)
	var kinds := ["broad", "needle", "palm"]
	for i in 3:
		var card := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(2.4, 2.4)
		card.mesh = q
		card.material_override = leaf_material(kinds[i])
		root.add_child(card)
		var cx := pos.x - 1.0 + float(i) * 2.8
		card.position = Vector3(cx, _ground(world, cx, pos.z) + 1.7, pos.z)


static func _ground(world: Node, x: float, z: float) -> float:
	if world.has_method("height_at"):
		return float(world.call("height_at", x, z))
	return 0.0
