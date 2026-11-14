extends Control
# DEBUG OVERLAY: a few small lines at the top of the screen so the owner can check every step on the phone.
# Other scripts can add their own line without editing this file:
#   main.debug_overlay.set_value("seed", "12345")      (remove it with  set_value("seed", ""))
# Lines are shown in the order they were first set.

const Cfg = preload("res://scripts/config.gd")
const Util = preload("res://scripts/util.gd")

var main                      # main.gd (set by main.gd before add_child)
var _values := {}             # key -> text (added by other scripts)
var _lines: Array = []
var _t := 0.0
var _spikes: Array = []   # v_003: the last 3 frames slower than 100 ms: "ms at x z (what)"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # touches go through to the game
	_refresh()


func set_value(key: String, text: String) -> void:
	if text == "":
		_values.erase(key)
	else:
		_values[key] = text


func _process(delta: float) -> void:
	if delta > 0.1 and main != null and main.get("_game_ready") == true:
		var p: Vector3 = main.actor_position()
		var what := String(Util.dbg.get("what", ""))
		_spikes.append("%d ms at x %d z %d  %s" % [int(delta * 1000.0), int(p.x), int(p.z), what])
		if _spikes.size() > 3:
			_spikes.pop_front()
		var f := FileAccess.open("user://spikes.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://spikes.txt") else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line("%s  t=%.1f  %s" % [Cfg.VERSION, Time.get_ticks_msec() / 1000.0, _spikes[_spikes.size() - 1]])
	_t += delta
	if _t < Cfg.DEBUG_OVERLAY_INTERVAL:
		return
	_t = 0.0
	_refresh()


func _refresh() -> void:
	var lines: Array = []
	var fps := int(Engine.get_frames_per_second())
	var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	lines.append("%s   FPS %d   draw calls %d   mem %d MB" % [Cfg.VERSION, fps, calls, int(mem)])
	if main != null and main.get("_game_ready") == true:
		var p: Vector3 = main.actor_position()
		var mode := "foot"
		if main.flying:
			mode = "helicopter"
		elif main.driving:
			mode = "tractor"
		lines.append("%s   x %.1f  y %.1f  z %.1f   block %d %d %d" % [mode, p.x, p.y, p.z, floori(p.x), floori(p.y), floori(p.z)])
	for sp in _spikes:
		lines.append("SPIKE " + String(sp))
	for k in _values:
		lines.append("%s: %s" % [k, _values[k]])
	_lines = lines
	queue_redraw()


func _draw() -> void:
	if _lines.is_empty():
		return
	var vp := get_viewport().get_visible_rect().size
	var u := clampf(vp.y / 720.0, 0.7, 1.5)
	var fs := int(17.0 * u)
	var f := ThemeDB.fallback_font
	var x := vp.x * 0.27   # top centre: the HUD text is top left, BAG / menu are top right
	var y := 20.0 * u
	for ln in _lines:
		draw_string_outline(f, Vector2(x, y), String(ln), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, 5, Color(0, 0, 0, 0.9))
		draw_string(f, Vector2(x, y), String(ln), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(0.7, 1.0, 0.7))
		y += float(fs) + 4.0 * u
