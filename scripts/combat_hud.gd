extends Control
# Combat HUD (v_007, from Fx99 combat_hud.gd): damage flash, health bar, hit marker, objective, banner, death screen.
# The crosshair (red over a bandit), ammo and short messages are drawn by hud.gd (My Plant HUD), so nothing is drawn twice.

var combat
var hit_t := 0.0
var hit_kill := false
var flash := 0.0
var _ban_text := ""
var _ban_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# short message: shown by the My Plant HUD
func say(t: String, secs: float = 1.8) -> void:
	if combat != null and combat.main != null and combat.main.hud != null:
		combat.main.hud.say(t, secs)


func banner(t: String, secs: float = 4.0) -> void:
	_ban_text = t
	_ban_t = secs


func hit(kill: bool) -> void:
	hit_t = 0.18
	hit_kill = kill


func hurt() -> void:
	flash = 0.45


func _process(delta: float) -> void:
	hit_t = maxf(0.0, hit_t - delta)
	flash = maxf(0.0, flash - delta)
	_ban_t = maxf(0.0, _ban_t - delta)
	queue_redraw()


func _text(s: String, pos: Vector2, size: int, col: Color, width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := ThemeDB.fallback_font
	draw_string_outline(f, pos, s, align, width, size, 6, Color(0, 0, 0, 0.9))
	draw_string(f, pos, s, align, width, size, col)


func _draw() -> void:
	if combat == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var c := vp / 2.0
	var u := clampf(vp.y / 720.0, 0.7, 1.5)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.8, 0.0, 0.0, minf(flash, 0.45) * 0.5))

	# hit marker (white = hit, red = kill)
	if combat.on_foot() and hit_t > 0.0:
		var hc := Color(1.0, 0.15, 0.1) if hit_kill else Color(1, 1, 1)
		for sgn in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			draw_line(c + sgn * 8.0, c + sgn * 18.0, hc, 3.0)

	# health bar (top left corner)
	var bw := 300.0 * u
	var bh := 22.0 * u
	var bx := 24.0 * u
	var by := 36.0 * u
	var frac := clampf(combat.hp / combat.MAX_HP, 0.0, 1.0)
	draw_rect(Rect2(bx - 3, by - 3, bw + 6, bh + 6), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(bx, by, bw * frac, bh), Color(0.9, 0.15, 0.1).lerp(Color(0.25, 0.85, 0.25), frac))
	_text("HP %d" % int(ceil(combat.hp)), Vector2(bx, by + bh - 4.0), int(20.0 * u), Color.WHITE, bw, HORIZONTAL_ALIGNMENT_CENTER)

	# objective (under the health bar)
	var obj: String = combat.objective_text()
	if obj != "":
		var lines := obj.split("\n")
		var y := by + bh + 34.0 * u
		for ln in lines:
			_text(ln, Vector2(bx, y), int(22.0 * u), Color(1.0, 0.92, 0.5))
			y += 28.0 * u

	if _ban_t > 0.0:
		var by2 := c.y - 130.0 * u
		for ln2 in _ban_text.split("\n"):
			_text(ln2, Vector2(0, by2), int(40.0 * u), Color(1.0, 0.85, 0.2), vp.x, HORIZONTAL_ALIGNMENT_CENTER)
			by2 += 46.0 * u

	if combat.dead:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55))
		_text("YOU DIED", Vector2(0, c.y), int(70.0 * u), Color(0.95, 0.2, 0.15), vp.x, HORIZONTAL_ALIGNMENT_CENTER)
