extends Control
# My Plant HUD (all drawn in code): crosshair, ammo, item boxes (dirt / wood), bag panel, map name + position, messages.

var shooter
var main
var info_text := ""        # extra line under the map name (speed / altitude while driving / flying)
var _say_text := ""
var _say_t := 0.0
var _pop := {}             # kind -> seconds left of the "+1" flash
var _pulse := {}           # kind -> seconds left of the box pulse


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func say(t: String, secs: float = 1.8) -> void:
	_say_text = t
	_say_t = secs


func pop(kind: String) -> void:
	_pop[kind] = 0.7
	_pulse[kind] = 0.25


func _process(delta: float) -> void:
	_say_t = maxf(0.0, _say_t - delta)
	for k in _pop.keys():
		_pop[k] = maxf(0.0, float(_pop[k]) - delta)
	for k in _pulse.keys():
		_pulse[k] = maxf(0.0, float(_pulse[k]) - delta)
	queue_redraw()


func _text(s: String, pos: Vector2, size: int, col: Color, width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := ThemeDB.fallback_font
	draw_string_outline(f, pos, s, align, width, size, 6, Color(0, 0, 0, 0.9))
	draw_string(f, pos, s, align, width, size, col)


func _draw() -> void:
	if shooter == null or main == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var c := vp / 2.0
	var u := clampf(vp.y / 720.0, 0.7, 1.5)
	var foot: bool = shooter.on_foot()

	# crosshair
	if foot:
		var on_bandit: bool = main.combat != null and main.combat.target_on   # v_007: red over a bandit
		var cgap := 13.0 if on_bandit else 9.0
		var ccol := Color(1.0, 0.1, 0.05) if on_bandit else Color(1, 1, 1, 0.9)
		for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * cgap, c + d * (cgap + 12.0), ccol, 4.0 if on_bandit else 3.0)
		draw_circle(c, 2.5 if on_bandit else 2.0, Color(1.0, 0.2, 0.2))

	# v_010: the map name / x z position line is removed (only speed / altitude is shown while driving / flying)
	if info_text != "":
		var lines := info_text.split("\n")
		var y := 130.0 * u
		for ln in lines:
			_text(ln, Vector2(24.0 * u, y), int(26.0 * u), Color(1.0, 0.92, 0.5))
			y += 30.0 * u

	var kinds := ["wood", "stone"]   # v_009: the Wood / Stone boxes moved into the BAG panel
	# "+1" flash next to the BAG button when something is picked up
	var bagc: Vector2 = Vector2(main.touch.btn["bag"]["pos"]) * vp
	var fy := 0.0
	for k in kinds:
		var pp := float(_pop.get(k, 0.0))
		if pp > 0.0:
			_text("+1 %s" % k.capitalize(), Vector2(bagc.x - 120.0 * u, bagc.y + 80.0 * u + fy - (0.7 - pp) * 30.0 * u), int(26.0 * u), Color(1.0, 0.95, 0.4, minf(pp * 3.0, 1.0)), 240.0 * u, HORIZONTAL_ALIGNMENT_CENTER)
			fy += 30.0 * u

	# build mode: the block types (bottom center). The yellow frame = selected block (NEXT button)
	if foot and main.touch.build_mode:
		var rects: Array = main.touch.hotbar_rects()
		var types: Array = main.build.TYPES
		for i in mini(rects.size(), types.size()):
			var sr: Rect2 = rects[i]
			var chosen: bool = i + 1 == main.build.sel
			draw_rect(sr, Color(1, 1, 1, 0.22 if chosen else 0.12))
			draw_texture_rect(main.build.icon_tex(i + 1), sr.grow(-sr.size.x * 0.14), false)
			if chosen:
				draw_rect(sr, Color(1.0, 0.9, 0.3), false, 4.0 * u)
			else:
				draw_rect(sr, Color(1, 1, 1, 0.5), false, 2.0)
		var top: float = (rects[0] as Rect2).position.y
		_text(main.build.block_name(), Vector2(0, top - 10.0 * u), int(26.0 * u), Color.WHITE, vp.x, HORIZONTAL_ALIGNMENT_CENTER)
	# ammo (bottom center, on foot)
	elif foot:
		var ay := vp.y - 40.0 * u
		_text("%s   %s" % [shooter.weapon_name(), shooter.ammo_text()], Vector2(0, ay), int(32.0 * u), Color.WHITE, vp.x, HORIZONTAL_ALIGNMENT_CENTER)
		if shooter.reloading:
			var rw := 220.0 * u
			var rf := 1.0 - clampf(shooter.reload_t / shooter.reload_total, 0.0, 1.0)
			draw_rect(Rect2(c.x - rw / 2.0, ay - 56.0 * u, rw, 10.0 * u), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(c.x - rw / 2.0, ay - 56.0 * u, rw * rf, 10.0 * u), Color(1.0, 0.85, 0.2))

	if _say_t > 0.0:
		_text(_say_text, Vector2(0, c.y + 130.0 * u), int(28.0 * u), Color.WHITE, vp.x, HORIZONTAL_ALIGNMENT_CENTER)

	# bag panel (BAG button)
	if shooter.bag_open:
		var pw := 420.0 * u
		var ph := 300.0 * u
		var px := c.x - pw / 2.0
		var py := c.y - ph / 2.0
		draw_rect(Rect2(px, py, pw, ph), Color(0.05, 0.05, 0.07, 0.88))
		draw_rect(Rect2(px, py, pw, ph), Color(1, 1, 1, 0.5), false, 3.0)
		_text("BAG", Vector2(px, py + 44.0 * u), int(34.0 * u), Color(1.0, 0.9, 0.4), pw, HORIZONTAL_ALIGNMENT_CENTER)
		var ry := py + 100.0 * u
		for k in kinds:
			var col2: Color = shooter.ITEM_COLORS[k]
			draw_rect(Rect2(px + 40.0 * u, ry - 26.0 * u, 34.0 * u, 34.0 * u), col2)
			_text("%s" % k.capitalize(), Vector2(px + 90.0 * u, ry), int(30.0 * u), Color.WHITE)
			_text("x %d" % int(shooter.inv.get(k, 0)), Vector2(px, ry), int(30.0 * u), Color.WHITE, pw - 40.0 * u, HORIZONTAL_ALIGNMENT_RIGHT)
			ry += 56.0 * u
		_text("tap BAG again to close", Vector2(px, py + ph - 16.0 * u), int(18.0 * u), Color(1, 1, 1, 0.6), pw, HORIZONTAL_ALIGNMENT_CENTER)
