extends RefCounted
# F11: day and night. One game day = Cfg.DAY_SECONDS real seconds (1440 = 24 minutes).
#   - the sun rises in the east (+x), climbs, sets in the west (-x); sunrise 06:00, sunset 18:00
#   - sunlight colour is calculated like the real air does it: the longer the light path through the air, the more
#     blue (then green) is removed -> red at the horizon, orange, yellow, nearly white at noon
#   - sky colours, horizon glow, clouds, ambient light follow the sun height (twilight before sunrise / after sunset)
#   - night: the same light node becomes the moon (blue, weak), stars, dark blue sky
# main.gd calls update(delta) every frame.

const Cfg = preload("res://scripts/config.gd")

const EXT := Vector3(0.04, 0.085, 0.18)   # how much the air removes of red / green / blue per air mass

# sun height (degrees), zenith colour, horizon colour
const SKY_KEYS := [
	[-18.0, Color(0.004, 0.008, 0.025), Color(0.015, 0.030, 0.070)],   # night
	[-9.0, Color(0.020, 0.040, 0.120), Color(0.080, 0.100, 0.220)],    # deep twilight
	[-4.0, Color(0.070, 0.130, 0.330), Color(0.450, 0.320, 0.420)],    # first light / last light, pinkish
	[0.0, Color(0.140, 0.250, 0.550), Color(0.930, 0.520, 0.300)],     # sun on the horizon, orange
	[5.0, Color(0.140, 0.340, 0.720), Color(0.950, 0.700, 0.520)],     # golden hour
	[12.0, Color(0.120, 0.320, 0.760), Color(0.720, 0.790, 0.900)],
	[25.0, Color(0.100, 0.300, 0.780), Color(0.580, 0.770, 0.960)],    # full day
]

var hour: float = Cfg.START_HOUR
var sun_elev := 0.0
var _step_t := 99.0   # the light turns in small steps (see update): a smoothly turning light makes every shadow edge crawl
var _sun: DirectionalLight3D
var _env: Environment
var _sky: ShaderMaterial


func setup(sun: DirectionalLight3D, env: Environment, sky_mat: ShaderMaterial) -> void:
	_sun = sun
	_env = env
	_sky = sky_mat
	update(0.0)


func clock_text() -> String:
	var h := int(hour)
	return "%02d:%02d" % [h, int((hour - float(h)) * 60.0)]


func _key_color(e: float, idx: int) -> Color:
	var keys: Array = SKY_KEYS
	if e <= float(keys[0][0]):
		return keys[0][idx]
	for i in range(1, keys.size()):
		if e <= float(keys[i][0]):
			var t := inverse_lerp(float(keys[i - 1][0]), float(keys[i][0]), e)
			var c0: Color = keys[i - 1][idx]
			var c1: Color = keys[i][idx]
			return c0.lerp(c1, t)
	return keys[keys.size() - 1][idx]


func update(delta: float) -> void:
	hour = fposmod(hour + delta * 24.0 / Cfg.DAY_SECONDS, 24.0)
	var a := PI * (hour - 6.0) / 12.0
	var sun_dir := Vector3(cos(a), sin(a), 0.3).normalized()   # east -> overhead -> west (a little to the south)
	var e := rad_to_deg(asin(sun_dir.y))
	sun_elev = e
	var moon_dir := Vector3(-sun_dir.x, -sun_dir.y, 0.35).normalized()

	# ---- sunlight through the air (Kasten-Young air mass)
	var eh := maxf(e, 0.0)
	var am := 1.0 / (sin(deg_to_rad(eh)) + 0.50572 * pow(eh + 6.07995, -1.6364))
	var tr := Vector3(exp(-am * EXT.x), exp(-am * EXT.y), exp(-am * EXT.z))
	var tint := Vector3(1.0, tr.y / tr.x, tr.z / tr.x)

	# ---- the light node: sun by day, moon at night
	var light_dir := sun_dir
	if e > -2.5:
		_sun.light_color = Color(tint.x, tint.y, tint.z)
		_sun.light_energy = Cfg.SUN_ENERGY * pow(tr.x, 1.6) * smoothstep(-2.5, 0.5, e)
	else:
		light_dir = moon_dir
		_sun.light_color = Color(0.6, 0.7, 1.0)
		_sun.light_energy = Cfg.MOON_ENERGY * (1.0 - smoothstep(-9.0, -2.5, e))
	_step_t += delta
	if _step_t >= Cfg.LIGHT_STEP:   # F11b: shadow direction changes every LIGHT_STEP seconds, not every frame = no shimmering
		_step_t = 0.0
		_sun.basis = Basis.looking_at(-light_dir, Vector3.UP)

	# ---- ambient light (sky light in the shadows)
	var t_amb := smoothstep(-9.0, -1.0, e)
	var d_amb := smoothstep(0.0, 18.0, e)
	_env.ambient_light_color = Color(0.10, 0.13, 0.26).lerp(Color(0.42, 0.40, 0.58), t_amb).lerp(Cfg.AMBIENT_COLOR, d_amb)
	_env.ambient_light_energy = lerpf(lerpf(0.14, 0.22, t_amb), Cfg.AMBIENT_ENERGY, d_amb)

	# ---- sky
	var top := _key_color(e, 1)
	var hor := _key_color(e, 2)
	var lit_amt := smoothstep(-8.0, 2.0, e)
	var white := Vector3(1.0, 1.0, 1.0)
	var day_lit := white.lerp(tint, 0.5) * (0.6 + 0.4 * smoothstep(0.0, 12.0, e))
	var night_lit := Vector3(0.07, 0.09, 0.15)
	var cl := night_lit.lerp(day_lit, lit_amt)
	var lum := hor.r * 0.3 + hor.g * 0.59 + hor.b * 0.11
	var cs := Color(lum, lum, lum).lerp(hor, 0.5) * (0.85 * (0.3 + 0.7 * lit_amt))
	_sky.set_shader_parameter("sun_dir", sun_dir)
	_sky.set_shader_parameter("moon_dir", moon_dir)
	_sky.set_shader_parameter("top_color", top)
	_sky.set_shader_parameter("horizon_color", hor)
	_sky.set_shader_parameter("sun_tint", tint)
	_sky.set_shader_parameter("sun_power", 2.0 + 6.0 * tr.x)
	_sky.set_shader_parameter("glow_color", Color(1.0, maxf(tint.y, 0.32), maxf(tint.z, 0.08)))
	_sky.set_shader_parameter("glow_amount", smoothstep(-9.0, -1.0, e) * (1.0 - smoothstep(2.0, 16.0, e)))
	_sky.set_shader_parameter("cloud_lit", Color(cl.x, cl.y, cl.z))
	_sky.set_shader_parameter("cloud_shadow", Color(cs.r, cs.g, cs.b))
	_sky.set_shader_parameter("star_vis", clampf((-e - 5.0) / 9.0, 0.0, 1.0))
