extends Node3D
# BUILD SYSTEM (Minecraft / Craftland style). 1 block = 1 m cube, snapped to a grid.
#   BUILD button  -> build mode (the gun is put away)
#   PLACE         -> puts the selected block on the face you look at (hold = keeps placing)
#   BREAK         -> removes the block you look at (hold = keeps breaking)
#   NEXT          -> next block type (the bar at the bottom shows all types)
# How it works: blocks live in a Dictionary (cell -> type id). The world is cut in 16x16x16 chunks;
# each chunk is ONE mesh that only has the faces you can see (fast on phones) + one collision shape.
# Saved automatically to user://blocks.dat (3 s after the last change, and when the game is closed / paused).

const CREATIVE := true    # true = unlimited blocks of every type.  false = survival: only WOOD, taken from the bag
const CHUNK := 16
const REACH := 7.0        # how far (m) from the player you can build
const REPEAT := 0.28      # seconds between blocks while PLACE / BREAK is held
const SAVE_PATH := "user://blocks.dat"

# block id = position in this list + 1 (only ADD at the end, saves use these numbers).
# col = average colour (shown in the bottom bar).  kind = bag item used in survival ("" = not available in survival)
# tiles = texture of [top, side, bottom] (names are in _px() below)
const TYPES := [
	{"name": "DIRT", "col": Color(0.46, 0.31, 0.18), "kind": "", "alpha": false, "tiles": ["dirt", "dirt", "dirt"]},
	{"name": "WOOD", "col": Color(0.72, 0.52, 0.28), "kind": "wood", "alpha": false, "tiles": ["wood_top", "wood_side", "wood_top"]},
	{"name": "STONE", "col": Color(0.55, 0.55, 0.58), "kind": "", "alpha": false, "tiles": ["stone", "stone", "stone"]},
	{"name": "BRICK", "col": Color(0.72, 0.36, 0.28), "kind": "", "alpha": false, "tiles": ["brick", "brick", "brick"]},
	{"name": "GLASS", "col": Color(0.65, 0.85, 0.95, 0.5), "kind": "", "alpha": true, "tiles": ["glass", "glass", "glass"]},
	{"name": "SAND", "col": Color(0.88, 0.82, 0.55), "kind": "", "alpha": false, "tiles": ["sand", "sand", "sand"]},
	{"name": "GRASS", "col": Color(0.30, 0.62, 0.25), "kind": "", "alpha": false, "tiles": ["grass_top", "grass_side", "dirt"]},
	{"name": "WHITE", "col": Color(0.93, 0.93, 0.92), "kind": "", "alpha": false, "tiles": ["white", "white", "white"]},
	{"name": "ROOF", "col": Color(0.50, 0.20, 0.14), "kind": "", "alpha": false, "tiles": ["roof", "roof", "roof"]},
	{"name": "TORCH", "col": Color(1.0, 0.62, 0.2), "kind": "wood", "alpha": true, "tiles": ["wood_side", "wood_side", "wood_side"], "torch": true},
]
const TORCH_ID := 10      # v_008: the torch is NOT a full block: no chunk mesh, no collision, own Node3D (flame, light, sparks)
const TORCH_TILT := 22.0  # degrees outward when it sits on the side of a wall
const CRACKLE_DB := -8.0
const TS := 16   # texture size of one block face (pixels)

# the 6 faces of a cube. n = direction, v = 4 corners (clockwise seen from outside = front face in Godot)
const FACES := [
	{"n": Vector3i(0, 1, 0), "k": 0, "s": 1.00, "v": [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)]},
	{"n": Vector3i(0, -1, 0), "k": 2, "s": 0.58, "v": [Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0)]},
	{"n": Vector3i(1, 0, 0), "k": 1, "s": 0.90, "v": [Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)]},
	{"n": Vector3i(-1, 0, 0), "k": 1, "s": 0.76, "v": [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1)]},
	{"n": Vector3i(0, 0, 1), "k": 1, "s": 0.84, "v": [Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1)]},
	{"n": Vector3i(0, 0, -1), "k": 1, "s": 0.68, "v": [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)]},
]

const Util = preload("res://scripts/util.gd")
const Cfg = preload("res://scripts/config.gd")

var main
var player
var rig
var touch
var shooter
var hud
var world

var sel := 1                     # selected block id
var cells := {}                  # Vector3i -> block id
var chunk_cells := {}            # Vector3i (chunk) -> Dictionary of cells
var chunk_nodes := {}            # Vector3i (chunk) -> StaticBody3D
var _dirty := {}                 # chunks to rebuild
var _save_t := -1.0
var _rep := 0.0
var _tgt_ok := false
var _tgt_cell := Vector3i.ZERO
var _place_ok := false
var _place_cell := Vector3i.ZERO
var _tile_mats := {}             # tile name -> material (made when first needed)
var _ghost: MeshInstance3D
var _wire: MeshInstance3D
var torch_dir := {}               # v_008: torch cell -> Vector3i face normal it sits on (UP = on top of something)
var torch_nodes := {}             # torch cell -> Node3D
var _torch_lpos := {}             # torch cell -> light position (world)
var _place_nrm := Vector3i.UP
var _t_stick: ArrayMesh
var _t_flame: ArrayMesh
var _t_glow: QuadMesh
var _t_spark: QuadMesh
var _t_spark_ramp: Gradient
var _t_flame_mat: ShaderMaterial
var _lights: Array = []           # pool of real lights (Cfg.TORCH_REAL_LIGHTS): moved to the nearest torches
var _lt_cell: Array = []
var _lt_goal: Array = []
var _fl_t := 0.0
var _tk_t := 0.0
var _s_tplace: AudioStreamPlayer
var _crackle: AudioStreamPlayer3D
var warming := false              # v1.1 step3: true while warmup() runs (loading screen)


func setup(m, p, r, t, s, h, w) -> void:
	main = m
	player = p
	rig = r
	touch = t
	shooter = s
	hud = h
	world = w
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(1, 1, 1, 0.28)
	_ghost = Util.mim(Util.box(Vector3.ONE * 1.004), gm)
	_ghost.visible = false
	add_child(_ghost)
	_wire = _make_wire()
	_wire.visible = false
	add_child(_wire)
	_torch_init()
	_load()


func block_name() -> String:
	return String(TYPES[sel - 1]["name"])


func next_block() -> void:
	sel = sel % TYPES.size() + 1


# v_009: tap on a hotbar slot selects that block (slot number 1..TYPES.size())
func select_block(i: int) -> void:
	sel = clampi(i, 1, TYPES.size())


# v_009: small picture of a block for the hotbar (made from the same tiles as the real block, 64x64, cached)
var _icon_cache := {}

func icon_tex(id: int) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var img := Image.create(TS, TS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var t: Dictionary = TYPES[id - 1]
	if bool(t.get("torch", false)):
		var half := {1: 1.0, 2: 2.0, 3: 3.0, 4: 3.0, 5: 2.0}
		for y in TS:
			for x in TS:
				var dx := absf(float(x) - 7.5)
				if half.has(y) and dx < float(half[y]):
					img.set_pixel(x, y, Color(1.0, 0.92, 0.4) if dx < 1.0 else (Color(1.0, 0.6, 0.15) if y < 5 else Color(1.0, 0.4, 0.1)))
				elif (x == 7 or x == 8) and y >= 6 and y <= 15:
					img.set_pixel(x, y, Color(0.45, 0.3, 0.15) if x == 7 else Color(0.62, 0.43, 0.2))
	else:
		var tile: String = String(t["tiles"][1])
		for y in TS:
			for x in TS:
				var c := _px(tile, x, y)
				if tile == "glass":
					c.a = minf(1.0, c.a + 0.35)
				img.set_pixel(x, y, c)
	img.resize(64, 64, Image.INTERPOLATE_NEAREST)
	var tex := ImageTexture.create_from_image(img)
	_icon_cache[id] = tex
	return tex


# ---------------------------------------------------------------- blocks

func _ck(cell: Vector3i) -> Vector3i:
	return Vector3i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)), floori(cell.z / float(CHUNK)))


# id 0 = remove the block
func set_block(cell: Vector3i, id: int) -> void:
	var ck := _ck(cell)
	if id == 0:
		if not cells.has(cell):
			return
		var old: int = cells[cell]
		cells.erase(cell)
		if chunk_cells.has(ck):
			(chunk_cells[ck] as Dictionary).erase(cell)
		if old == TORCH_ID:
			_torch_remove(cell)
		else:
			_pop_torches(cell)
	else:
		if id != TORCH_ID and torch_nodes.has(cell):
			_torch_remove(cell)
		cells[cell] = id
		if not chunk_cells.has(ck):
			chunk_cells[ck] = {}
		(chunk_cells[ck] as Dictionary)[cell] = true
		if id == TORCH_ID:
			_torch_add(cell)
	_dirty[ck] = true
	# a block on the border of a chunk also changes the faces of the next chunk
	for f in FACES:
		var nc := _ck(cell + (f["n"] as Vector3i))
		if nc != ck:
			_dirty[nc] = true
	_save_t = 3.0


# ---------------------------------------------------------------- textures (made by code, no files)
# Mipmaps + "nearest with mipmaps" filter: sharp pixels close up, smooth average colour far away = no shimmering.
# One material (= one 16x16 texture) per tile, so mipmaps never mix two tiles together.

func _hash(x: int, y: int, sd: int) -> float:
	var n: int = x * 374761393 + y * 668265263 + sd * 1274126177
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65535.0


func _noisy(base: Color, x: int, y: int, sd: int, amt: float) -> Color:
	var v := 1.0 + (_hash(x, y, sd) - 0.5) * 2.0 * amt
	return Color(base.r * v, base.g * v, base.b * v, base.a)


func _px(tile: String, x: int, y: int) -> Color:
	match tile:
		"dirt":
			return _noisy(Color(0.46, 0.31, 0.18), x, y, 1, 0.09)
		"grass_top":
			return _noisy(Color(0.30, 0.62, 0.25), x, y, 2, 0.08)
		"grass_side":
			var edge := 3 + int(_hash(x, 0, 9) * 2.0)
			if y < edge:
				return _noisy(Color(0.30, 0.62, 0.25), x, y, 2, 0.08)
			return _noisy(Color(0.46, 0.31, 0.18), x, y, 1, 0.09)
		"wood_side":   # horizontal planks with a joint in every plank
			var row := y / 4
			if y % 4 == 0:
				return Color(0.45, 0.30, 0.15)
			if x == (row * 7 + 3) % TS:
				return Color(0.50, 0.34, 0.17)
			return _noisy(Color(0.72, 0.52, 0.28) * (0.94 + 0.12 * _hash(0, row, 5)), x / 3, y, 6, 0.04)
		"wood_top":    # vertical planks (so the top / bottom look different from the sides)
			var col := x / 4
			if x % 4 == 0:
				return Color(0.40, 0.27, 0.13)
			return _noisy(Color(0.62, 0.44, 0.22) * (0.94 + 0.12 * _hash(col, 0, 5)), x, y / 3, 6, 0.04)
		"stone":
			var c := _noisy(Color(0.55, 0.55, 0.58), x, y, 3, 0.07)
			if _hash(x, y, 11) > 0.93:
				c = c * 0.82
			return Color(c.r, c.g, c.b, 1.0)
		"brick":
			var row := y / 4
			var off := (row % 2) * 4
			var bx := (x + off) % 8
			if y % 4 == 0 or bx == 0:
				return Color(0.80, 0.78, 0.72)   # mortar
			return _noisy(Color(0.72, 0.36, 0.28) * (0.92 + 0.16 * _hash((x + off) / 8, row, 7)), x, y, 8, 0.03)
		"roof":        # dark shingles in rows: easy to see from far away
			var row := y / 4
			var off := (row % 2) * 4
			if y % 4 == 0:
				return Color(0.26, 0.10, 0.07)
			var c := Color(0.52, 0.21, 0.15) * (0.9 + 0.2 * _hash((x + off) / 8, row, 8)) * (1.0 - 0.07 * float(y % 4))
			if (x + off) % 8 == 0:
				c = c * 0.8
			return Color(c.r, c.g, c.b, 1.0)
		"sand":
			return _noisy(Color(0.88, 0.82, 0.55), x, y, 4, 0.05)
		"white":       # plaster wall; the slightly darker border shows where one block ends
			var c := _noisy(Color(0.93, 0.93, 0.92), x, y, 5, 0.02)
			if x == 0 or y == 0:
				c = c * 0.90
			return Color(c.r, c.g, c.b, 1.0)
		"glass":
			if x == 0 or y == 0 or x == TS - 1 or y == TS - 1:
				return Color(0.85, 0.93, 0.98, 0.8)    # frame
			if x + y == 7 or x + y == 8:
				return Color(1.0, 1.0, 1.0, 0.55)       # shine
			return Color(0.65, 0.85, 0.95, 0.30)
	return Color.MAGENTA


func _tile_mat(tile: String) -> StandardMaterial3D:
	if _tile_mats.has(tile):
		return _tile_mats[tile]
	var img := Image.create(TS, TS, false, Image.FORMAT_RGBA8)
	for y in TS:
		for x in TS:
			img.set_pixel(x, y, _px(tile, x, y))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.vertex_color_use_as_albedo = true      # vertex colour = brightness of that side
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	m.texture_repeat = false
	m.roughness = 1.0
	m.metallic_specular = 0.0
	if tile == "glass":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tile_mats[tile] = m
	return m


# ---------------------------------------------------------------- chunk mesh

func _rebuild(ck: Vector3i) -> void:
	if chunk_nodes.has(ck):
		(chunk_nodes[ck] as Node).queue_free()
		chunk_nodes.erase(ck)
	var cs: Dictionary = chunk_cells.get(ck, {})
	if cs.is_empty():
		chunk_cells.erase(ck)
		return
	var sts := {}   # tile name -> SurfaceTool
	for c in cs:
		var cell: Vector3i = c
		var id: int = cells[cell]
		if id == TORCH_ID:
			continue   # v_008: a torch is not part of the mesh / collision and does not hide the faces next to it
		var tiles: Array = TYPES[id - 1]["tiles"]
		for f in FACES:
			var dir: Vector3i = f["n"]
			var oid: int = cells.get(cell + dir, 0)
			# hidden face: same type next to it, or a solid block next to it
			if oid != 0 and (oid == id or not bool(TYPES[oid - 1]["alpha"])):
				continue
			var tname: String = tiles[int(f["k"])]
			if not sts.has(tname):
				var nst := SurfaceTool.new()
				nst.begin(Mesh.PRIMITIVE_TRIANGLES)
				sts[tname] = nst
			var st: SurfaceTool = sts[tname]
			var sh: float = f["s"]
			var vc := Color(sh, sh, sh, 1.0)
			var vs: Array = f["v"]
			for k in [0, 1, 2, 0, 2, 3]:
				var lv: Vector3 = vs[k]
				var uv: Vector2
				if dir.y != 0:
					uv = Vector2(lv.x, lv.z)
				elif dir.x != 0:
					uv = Vector2(lv.z, 1.0 - lv.y)
				else:
					uv = Vector2(lv.x, 1.0 - lv.y)
				st.set_color(vc)
				st.set_normal(Vector3(dir))
				st.set_uv(uv)
				st.add_vertex(Vector3(cell) + lv)
	var mesh := ArrayMesh.new()
	for tn in sts:
		(sts[tn] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _tile_mat(String(tn)))
	if mesh.get_surface_count() == 0:
		return
	var body := StaticBody3D.new()
	body.add_to_group("block")
	body.collision_layer = 1   # "things": the player and the tractor both collide with it
	body.collision_mask = 0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var cshape := CollisionShape3D.new()
	cshape.shape = mesh.create_trimesh_shape()
	body.add_child(cshape)
	add_child(body)
	chunk_nodes[ck] = body


# ---------------------------------------------------------------- warm-up (loading screen)
# puts one block of EVERY type in the air in front of the camera for a few frames, then removes them (nothing is saved).
# This builds the chunk mesh + collision, the textures and the glass shader once, so the first real block does not freeze.

func warmup() -> void:
	warming = true
	var tree := get_tree()
	var fwd: Vector3 = -rig.cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = fwd.cross(Vector3.UP)
	var origin: Vector3 = player.global_position + fwd * 7.0 + Vector3(0, 1.0, 0)
	var added: Array = []
	for i in TYPES.size():
		var pos: Vector3 = origin + right * float((i % 5) - 2) * 2.0 + Vector3(0, float(i / 5) * 2.0, 0)
		var cell := _floor3(pos)
		if cells.has(cell):
			continue
		set_block(cell, i + 1)
		added.append(cell)
	var gc := _floor3(origin + Vector3(0, 4, 0))
	_ghost.visible = true
	_ghost.global_position = Vector3(gc) + Vector3(0.5, 0.5, 0.5)
	_wire.visible = true
	_wire.global_position = Vector3(gc) + Vector3(1.5, 0.5, 0.5)
	await tree.physics_frame
	await tree.physics_frame
	for t in TYPES:   # also draws every block name once (text cache)
		touch.next_text = String(t["name"])
		await tree.process_frame
	await tree.process_frame
	for c in added:
		set_block(c, 0)
	await tree.physics_frame
	await tree.physics_frame
	_ghost.visible = false
	_wire.visible = false
	_save_t = -1.0
	warming = false


# v_008: draws the torch once: flame shader, glow quad, real light, sparks, place click + crackle (muted). Then removes it.
func warmup_torch() -> void:
	warming = true
	var tree := get_tree()
	var fwd: Vector3 = -rig.cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = fwd.cross(Vector3.UP)
	var origin: Vector3 = player.global_position + fwd * 5.0 + Vector3(0, 1.0, 0)
	var made: Array = []
	for i in 2:
		var cell := _floor3(origin + right * (float(i) * 2.0 - 1.0))
		if cells.has(cell):
			continue
		torch_dir[cell] = Vector3i.UP if i == 0 else Vector3i(1, 0, 0)   # one standing, one leaning
		set_block(cell, TORCH_ID)
		made.append(cell)
	var old_db: float = _crackle.volume_db
	_crackle.volume_db = -80.0
	_s_tplace.volume_db = -80.0
	_s_tplace.play()
	_torch_update()
	if not _crackle.playing:
		_crackle.play()
	for i in 45:   # the sparks need some time to be born and drawn
		await tree.process_frame
	for c in made:
		set_block(c, 0)
	_s_tplace.stop()
	_s_tplace.volume_db = -4.0
	_crackle.stop()
	_crackle.volume_db = old_db
	for i in 12:   # the light fades out
		await tree.process_frame
	_save_t = -1.0
	warming = false


# ---------------------------------------------------------------- torch (v_008)

func _is_torch(cell: Vector3i) -> bool:
	return int(cells.get(cell, 0)) == TORCH_ID


func _torch_init() -> void:
	# stick: one mesh, 2 boxes with vertex colours (wood + burnt head)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_into(st, Vector3(0, 0.25, 0), Vector3(0.14, 0.5, 0.14), Color(0.42, 0.27, 0.13))
	_box_into(st, Vector3(0, 0.55, 0), Vector3(0.15, 0.1, 0.15), Color(0.07, 0.05, 0.04))
	_t_stick = st.commit()
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.roughness = 1.0
	_t_stick.surface_set_material(0, sm)
	# flame: 3 crossed quads, one mesh
	var fs := SurfaceTool.new()
	fs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := PI * float(k) / 3.0
		var r := Vector3(cos(a), 0.0, sin(a)) * 0.17
		var up := Vector3(0, 0.42, 0)
		var pts: Array = [-r, r, r + up, -r + up]
		var uvs: Array = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			fs.set_normal(Vector3(-sin(a), 0.0, cos(a)))
			fs.set_uv(uvs[idx])
			fs.add_vertex(pts[idx])
	_t_flame = fs.commit()
	var sh := Shader.new()
	sh.code = TORCH_SHADER
	_t_flame_mat = ShaderMaterial.new()
	_t_flame_mat.shader = sh
	_t_flame.surface_set_material(0, _t_flame_mat)
	# soft glow quad (always on, also far away where the real light is off)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.55, 0.2, 0.55))
	g.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.albedo_texture = gt
	_t_glow = QuadMesh.new()
	_t_glow.size = Vector2(1.6, 1.6)
	_t_glow.material = gm
	# sparks
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.vertex_color_use_as_albedo = true
	_t_spark = QuadMesh.new()
	_t_spark.size = Vector2(0.06, 0.06)
	_t_spark.material = pm
	_t_spark_ramp = Gradient.new()
	_t_spark_ramp.set_color(0, Color(1.0, 0.75, 0.3, 1.0))
	_t_spark_ramp.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	# pool of real lights
	for i in int(Cfg.TORCH_REAL_LIGHTS):
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.62, 0.28)
		l.omni_range = 14.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)
		_lt_cell.append(null)
		_lt_goal.append(1.9)
	# sounds
	_s_tplace = AudioStreamPlayer.new()
	_s_tplace.stream = _noise_wav(0.06, 80.0, 900.0, 70.0, 0.6)
	_s_tplace.volume_db = -4.0
	add_child(_s_tplace)
	_crackle = AudioStreamPlayer3D.new()
	_crackle.stream = _crackle_wav()
	_crackle.max_distance = 12.0
	_crackle.unit_size = 3.0
	_crackle.volume_db = CRACKLE_DB
	add_child(_crackle)


const TORCH_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
varying float v_ph;
void vertex() {
	float ph = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(12.9898, 78.233, 37.719))) * 43758.5453) * 6.2831;
	float tt = TIME * 6.0 + ph;
	float h = 1.0 - UV.y;
	VERTEX.y *= 1.0 + 0.15 * (0.5 * sin(tt * 1.7) + 0.5 * sin(tt * 2.9 + 1.3));
	VERTEX.xz *= 1.0 - 0.3 * h;
	VERTEX.x += sin(tt * 1.3) * 0.06 * h;
	VERTEX.z += cos(tt * 1.1 + 0.7) * 0.06 * h;
	v_ph = ph;
}
void fragment() {
	float h = 1.0 - UV.y;
	float x = abs(UV.x - 0.5) * 2.0;
	float w = clamp(1.0 - pow(h, 1.5) * 0.95, 0.05, 1.0);
	float shape = 1.0 - smoothstep(w * 0.45, w, x);
	float fade = 1.0 - smoothstep(0.7, 1.0, h);
	float n = 0.78 + 0.22 * sin(h * 10.0 - TIME * 10.0 + v_ph);
	vec3 col = mix(vec3(1.0, 0.35, 0.05), vec3(1.0, 0.78, 0.15), smoothstep(0.0, 0.45, h));
	col = mix(col, vec3(1.0, 0.95, 0.7), smoothstep(0.5, 0.95, h));
	col += vec3(0.35, 0.25, 0.05) * (1.0 - x) * (1.0 - h);
	ALBEDO = col * 1.5;
	ALPHA = clamp(shape * fade * n, 0.0, 1.0);
}
"""


func _box_into(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	for f in FACES:
		var dir: Vector3i = f["n"]
		var vs: Array = f["v"]
		for k in [0, 1, 2, 0, 2, 3]:
			var lv: Vector3 = vs[k]
			st.set_color(col)
			st.set_normal(Vector3(dir))
			st.add_vertex(center + (lv - Vector3(0.5, 0.5, 0.5)) * size)


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


# soft fire crackle, 2 s loop: quiet hiss + random small pops
func _crackle_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var pop := 0.0
	for i in n:
		var w := randf() * 2.0 - 1.0
		lp += (w - lp) * 0.08
		if randf() < 0.0009:
			pop = randf_range(0.5, 1.0)
		var v := lp * 0.5 + w * pop * 0.6
		pop *= 0.992
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 14000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n
	return st


func _make_torch(cell: Vector3i, nrm: Vector3i) -> Node3D:
	var n := Node3D.new()
	var axis := Vector3.UP
	var base := Vector3(cell) + Vector3(0.5, 0.0, 0.5)
	if nrm.y != 1:   # on the side of a wall: leans outward
		var out := Vector3(nrm)
		var tilt := deg_to_rad(TORCH_TILT)
		axis = (out * sin(tilt) + Vector3.UP * cos(tilt)).normalized()
		base = Vector3(cell) + Vector3(0.5, 0.3, 0.5) - out * 0.44
	n.position = base
	n.basis = Basis(Quaternion(Vector3.UP, axis))
	var stick := MeshInstance3D.new()
	stick.mesh = _t_stick
	n.add_child(stick)
	var flame := MeshInstance3D.new()
	flame.mesh = _t_flame
	flame.position = Vector3(0, 0.58, 0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(flame)
	var glow := MeshInstance3D.new()
	glow.mesh = _t_glow
	glow.position = Vector3(0, 0.8, 0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(glow)
	var sp := CPUParticles3D.new()
	sp.amount = 5
	sp.lifetime = 0.8
	sp.mesh = _t_spark
	sp.direction = Vector3.UP
	sp.spread = 28.0
	sp.initial_velocity_min = 0.5
	sp.initial_velocity_max = 1.0
	sp.gravity = Vector3(0, 0.3, 0)
	sp.randomness = 1.0
	sp.color = Color(1, 1, 1, 1)
	sp.color_ramp = _t_spark_ramp
	sp.emitting = false
	sp.position = Vector3(0, 0.95, 0)
	n.add_child(sp)
	n.set_meta("sp", sp)
	_torch_lpos[cell] = base + axis * 0.85
	return n


func _torch_add(cell: Vector3i) -> void:
	if torch_nodes.has(cell):
		return
	var nrm: Vector3i = torch_dir.get(cell, Vector3i.UP)
	torch_dir[cell] = nrm
	var n := _make_torch(cell, nrm)
	add_child(n)
	torch_nodes[cell] = n
	var cb = main.combat if main != null else null
	if cb != null:
		cb.torch_added(Vector3(cell) + Vector3(0.5, 0.5, 0.5))


func _torch_remove(cell: Vector3i) -> void:
	if torch_nodes.has(cell):
		(torch_nodes[cell] as Node).queue_free()
		torch_nodes.erase(cell)
		var cb = main.combat if main != null else null
		if cb != null:
			cb.torch_removed(Vector3(cell) + Vector3(0.5, 0.5, 0.5))
	torch_dir.erase(cell)
	_torch_lpos.erase(cell)
	for i in _lt_cell.size():
		if _lt_cell[i] != null and _lt_cell[i] == cell:
			_lt_cell[i] = null


# a block is removed: torches that sat on it fall off
func _pop_torches(cell: Vector3i) -> void:
	if torch_dir.is_empty():
		return
	for f in FACES:
		var nb: Vector3i = cell + (f["n"] as Vector3i)
		if torch_dir.has(nb) and _is_torch(nb):
			var d: Vector3i = torch_dir[nb]
			if nb - d == cell:
				set_block(nb, 0)
				if not CREATIVE and shooter != null:
					shooter.add_item("wood", 1)


# every 0.5 s: far torches hidden (> 60 m), sparks only near (< 25 m), the real lights + crackle go to the nearest torches
func _torch_update() -> void:
	if torch_nodes.is_empty():
		for i in _lt_cell.size():
			_lt_cell[i] = null
		if _crackle.playing:
			_crackle.stop()
		return
	var pp: Vector3 = player.global_position
	var near: Array = []
	for c in torch_nodes:
		var n: Node3D = torch_nodes[c]
		var d: float = n.global_position.distance_to(pp)
		var vis := d < 60.0
		if n.visible != vis:
			n.visible = vis
		var sp: CPUParticles3D = n.get_meta("sp")
		var em := d < 25.0
		if sp.emitting != em:
			sp.emitting = em
		if d < 24.0:
			near.append([d, c])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var want: Array = []
	for i in mini(near.size(), _lights.size()):
		want.append(near[i][1])
	var free: Array = []
	for i in _lights.size():
		if _lt_cell[i] != null and want.has(_lt_cell[i]):
			want.erase(_lt_cell[i])
		else:
			_lt_cell[i] = null
			free.append(i)
	for c2 in want:
		if free.is_empty():
			break
		var li: int = free.pop_back()
		_lt_cell[li] = c2
		var l: OmniLight3D = _lights[li]
		l.light_energy = 0.0
		l.global_position = _torch_lpos[c2]
	if not near.is_empty() and float(near[0][0]) < 12.0:
		_crackle.global_position = _torch_lpos[near[0][1]]
		if not _crackle.playing:
			_crackle.play()
	elif _crackle.playing:
		_crackle.stop()


# light flicker: a new value every 0.05-0.1 s, smooth lerp
func _process(delta: float) -> void:
	if player == null or _lights.is_empty():
		return
	var roll := false
	_fl_t -= delta
	if _fl_t <= 0.0:
		_fl_t = randf_range(0.05, 0.1)
		roll = true
	for i in _lights.size():
		var l: OmniLight3D = _lights[i]
		if roll:
			_lt_goal[i] = randf_range(1.6, 2.2)
		var goal: float = float(_lt_goal[i]) if _lt_cell[i] != null else 0.0
		var e := lerpf(l.light_energy, goal, minf(1.0, delta * 10.0))
		l.light_energy = e
		var vis := e > 0.03
		if l.visible != vis:
			l.visible = vis


# ---------------------------------------------------------------- aiming + actions

func _floor3(v: Vector3) -> Vector3i:
	return Vector3i(floori(v.x), floori(v.y), floori(v.z))


func _round3(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x), roundi(v.y), roundi(v.z))


# looks where the crosshair points: sets the block you aim at (_tgt) and the empty cell next to it (_place)
func _aim() -> void:
	_tgt_ok = false
	_place_ok = false
	var cam: Camera3D = rig.cam
	var fwd: Vector3 = -cam.global_transform.basis.z
	var from: Vector3 = cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 40.0)
	q.exclude = [player.get_rid()]
	q.collision_mask = 0xFFFFFFFB   # DIG5: not layer 3 (bushes)
	var r: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	var maxd := 40.0
	if not r.is_empty():
		var rp: Vector3 = r["position"]
		maxd = from.distance_to(rp)
	var tc: Variant = _aim_torch(from, fwd, maxd)   # v_008: torches have no collision: aim at them by distance to the ray
	if tc != null:
		_tgt_cell = tc
		_tgt_ok = true
		return
	if r.is_empty():
		return
	var col: Object = r["collider"]
	if not (col is Node):
		return
	var pos: Vector3 = r["position"]
	var nrm: Vector3 = r["normal"]
	if pos.distance_to(player.global_position) > REACH:
		return
	var cn := col as Node
	if cn.is_in_group("block"):
		_tgt_cell = _floor3(pos - nrm * 0.5)
		_tgt_ok = cells.has(_tgt_cell)
		_place_nrm = _round3(nrm)
		_place_cell = _tgt_cell + _place_nrm
		_place_ok = _tgt_ok
	elif cn.is_in_group("terrain") or cn.is_in_group("voxel_ground"):   # v1.5: the block ground counts as ground too
		_place_cell = _floor3(pos + nrm * 0.5)
		_place_nrm = Vector3i.UP if nrm.y > 0.5 else _round3(nrm)
		_place_ok = true


func _aim_torch(from: Vector3, fwd: Vector3, maxd: float) -> Variant:
	if torch_nodes.is_empty():
		return null
	var best_t := maxd
	var best: Variant = null
	var pp: Vector3 = player.global_position
	for c in torch_nodes:
		var n: Node3D = torch_nodes[c]
		if n.global_position.distance_to(pp) > REACH + 1.5:
			continue
		var ax: Vector3 = n.global_transform.basis.y
		for k in 4:
			var p: Vector3 = n.global_position + ax * (0.1 + 0.2 * float(k))
			var t: float = (p - from).dot(fwd)
			if t < 0.0 or t >= best_t:
				continue
			var onray: Vector3 = from + fwd * t
			if onray.distance_to(pp) > REACH:
				continue
			if p.distance_to(onray) < 0.2:
				best_t = t
				best = c
				break
	return best


# the player is a capsule centred on its origin: 0.56 m wide, 1.7 m tall
func _hits_player(cell: Vector3i) -> bool:
	var p: Vector3 = player.global_position
	var lo := Vector3(cell)
	var hi := lo + Vector3.ONE
	var plo := p + Vector3(-0.3, -0.85, -0.3)
	var phi := p + Vector3(0.3, 0.85, 0.3)
	return lo.x < phi.x and hi.x > plo.x and lo.y < phi.y and hi.y > plo.y and lo.z < phi.z and hi.z > plo.z


func _place() -> void:
	if not _place_ok or cells.has(_place_cell):
		return
	var is_torch := sel == TORCH_ID
	if is_torch:
		# on top of something, or on the side of a block. Not under a block, not on the side of the bare ground
		if not (_place_nrm == Vector3i.UP or (_tgt_ok and _place_nrm.y == 0)):
			hud.say("Torch: not there", 0.8)
			return
		torch_dir[_place_cell] = _place_nrm
	elif _hits_player(_place_cell):   # a torch has no collision: you can walk through it
		hud.say("You are standing there", 0.8)
		return
	if not CREATIVE:
		var kind: String = TYPES[sel - 1]["kind"]
		if kind == "":
			hud.say("%s needs creative mode" % block_name(), 1.0)
			return
		if int(shooter.inv.get(kind, 0)) <= 0:
			hud.say("No %s left" % kind, 1.0)
			return
		shooter.inv[kind] = int(shooter.inv[kind]) - 1
	set_block(_place_cell, sel)
	if is_torch:
		_s_tplace.play()
		_torch_update()
	else:
		shooter._s_pick.play()


func _break() -> void:
	if not _tgt_ok:
		return
	var id: int = cells.get(_tgt_cell, 0)
	if id == 0:
		return
	set_block(_tgt_cell, 0)
	shooter._s_chop.play()
	if not CREATIVE:
		var kind: String = TYPES[id - 1]["kind"]
		if kind != "":
			shooter.add_item(kind, 1)
			hud.pop(kind)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	for ck in _dirty.keys():
		_rebuild(ck)
	_dirty.clear()
	if _save_t > 0.0:
		_save_t -= delta
		if _save_t <= 0.0:
			_save_t = -1.0
			_save()

	_tk_t -= delta
	if _tk_t <= 0.0:
		_tk_t = 0.5
		_torch_update()

	if warming:
		return
	var active: bool = touch.build_mode and shooter.on_foot() and not touch.blocked
	_ghost.visible = false
	_wire.visible = false
	if not active:
		_rep = 0.0
		return
	_aim()
	if _place_ok:
		_ghost.visible = true
		_ghost.global_position = Vector3(_place_cell) + Vector3(0.5, 0.5, 0.5)
	if _tgt_ok:
		_wire.visible = true
		_wire.global_position = Vector3(_tgt_cell) + Vector3(0.5, 0.5, 0.5)

	var want_place: bool = touch.held.get("place", false)
	var want_break: bool = touch.held.get("break", false)
	if not (want_place or want_break):
		_rep = 0.0
		return
	_rep -= delta
	if _rep > 0.0:
		return
	_rep = REPEAT
	if want_break:
		_break()
	else:
		_place()


# thin black outline of the 12 edges of a cube (centred on its origin)
func _make_wire() -> MeshInstance3D:
	var h := 0.503
	var c := []
	for i in 8:
		c.append(Vector3(h if (i & 1) != 0 else -h, h if (i & 2) != 0 else -h, h if (i & 4) != 0 else -h))
	var pts := PackedVector3Array()
	for i in 8:
		for bit in [1, 2, 4]:
			if (i & bit) == 0:
				pts.append(c[i])
				pts.append(c[i | bit])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0, 0, 0, 1)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	return mi


# ---------------------------------------------------------------- save / load

func _save() -> void:
	var arr := PackedInt32Array()
	for c in cells:
		var cell: Vector3i = c
		arr.append(cell.x)
		arr.append(cell.y)
		arr.append(cell.z)
		arr.append(int(cells[c]))
	var tarr := PackedInt32Array()   # v_008: torch directions (2nd part of the file; old files have only the first part)
	for tc in torch_dir:
		var tcell: Vector3i = tc
		var tn: Vector3i = torch_dir[tc]
		tarr.append_array(PackedInt32Array([tcell.x, tcell.y, tcell.z, tn.x, tn.y, tn.z]))
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_var(arr)
		f.store_var(tarr)


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var v = f.get_var()
	var v2 = null
	if f.get_position() < f.get_length():
		v2 = f.get_var()
	if v2 is PackedInt32Array:
		var ta: PackedInt32Array = v2
		var j := 0
		while j + 5 < ta.size():
			torch_dir[Vector3i(ta[j], ta[j + 1], ta[j + 2])] = Vector3i(ta[j + 3], ta[j + 4], ta[j + 5])
			j += 6
	if v is PackedInt32Array:
		var arr: PackedInt32Array = v
		var i := 0
		while i + 3 < arr.size():
			var id: int = arr[i + 3]
			if id >= 1 and id <= TYPES.size():
				set_block(Vector3i(arr[i], arr[i + 1], arr[i + 2]), id)
			i += 4
	for tk in torch_dir.keys():
		if not _is_torch(tk):
			torch_dir.erase(tk)
	_save_t = -1.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _save_t > 0.0:
			_save_t = -1.0
			_save()
