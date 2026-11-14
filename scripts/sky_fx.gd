extends RefCounted
# F10/F11: the sky. Blue sky + soft cumulus clouds + real sun disc, and (F11) moon, stars and the red / orange
# glow of sunrise and sunset. One sky shader (no textures). All colours come from scripts/daynight.gd.
# Use:  var mat := SkyFx.make_material(sun_dir)   then every frame  mat.set_shader_parameter("cloud_time", t)

const CODE := """
shader_type sky;

uniform vec3 sun_dir = vec3(0.4, 0.5, 0.75);
uniform vec3 moon_dir = vec3(-0.4, -0.5, 0.3);
uniform vec3 top_color : source_color = vec3(0.10, 0.30, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.58, 0.77, 0.96);
uniform vec3 sun_tint = vec3(1.0, 0.93, 0.78);        // colour of the sunlight (red at sunrise, white at noon)
uniform float sun_power = 8.0;                        // brightness of the sun disc
uniform vec3 glow_color : source_color = vec3(1.0, 0.4, 0.12);
uniform float glow_amount = 0.0;                      // sunrise / sunset glow on the horizon
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.985, 0.95);
uniform vec3 cloud_shadow : source_color = vec3(0.58, 0.65, 0.80);
uniform float star_vis = 0.0;
uniform float cloud_time = 0.0;
uniform float cloud_cover = 0.5;     // 0 = clear sky, 1 = overcast
uniform float cloud_scale = 1.7;     // bigger = smaller clouds
uniform float sun_size = 1.1;        // degrees (real sun is 0.27, a bit bigger so it is easy to see on a phone)

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 m = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < 3; i++) {   // v1.0: 3 octaves (was 5) = cheaper sky
		v += a * vnoise(p);
		p = m * p;
		a *= 0.5;
	}
	return v;   // about 0 .. 0.97
}

float density(float s) {
	float thr = mix(0.78, 0.38, cloud_cover);
	return smoothstep(thr, thr + 0.2, s);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	vec3 sd = normalize(sun_dir);
	float cs = dot(dir, sd);

	// ---- clouds: a flat layer high above, seen in perspective (smaller and denser towards the horizon)
	float cloud_a = 0.0;
	vec3 cloud_col = vec3(1.0);
	if (!AT_CUBEMAP_PASS && h > 0.0) {
		vec2 uv = dir.xz / (h + 0.12) * cloud_scale;
		uv += vec2(cloud_time * 0.012, cloud_time * 0.005);   // slow wind
		float s = fbm(uv);
		float d = density(s);
		// light: look a little towards the sun; if it is thinner there, this side of the cloud is lit
		vec2 sdir2 = normalize(sd.xz + vec2(0.0001));
		float s2 = s;
		if (d > 0.002) { s2 = fbm(uv + sdir2 * 0.07); }   // v1.0: second noise only where a cloud is
		float lit = clamp(0.62 + (s - s2) * 3.2, 0.0, 1.0);
		cloud_col = mix(cloud_shadow, cloud_lit, lit);
		cloud_col *= mix(1.0, 0.82, smoothstep(0.55, 1.0, s) * (1.0 - lit));   // thick middle is a bit darker
		// silver lining near the sun
		cloud_col += sun_tint * pow(max(cs, 0.0), 10.0) * (1.0 - d) * 0.5 * smoothstep(0.0, 0.3, d + 0.2) * clamp(sun_power / 8.0, 0.0, 1.0);
		float fade = smoothstep(0.0, 0.22, h);   // far clouds fade into the haze at the horizon
		cloud_a = d * fade;
		cloud_col = mix(horizon_color, cloud_col, mix(0.55, 1.0, fade));
	}

	// ---- clear sky: deep blue up, pale at the horizon (the same colour below it = no hard line)
	float t = clamp(h, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(t, 0.5));
	if (h < 0.0) {
		col = mix(horizon_color, horizon_color * 0.92, smoothstep(0.0, -0.4, h));
	}

	// ---- sunrise / sunset: red-orange glow on the horizon, strongest towards the sun
	vec2 hd = normalize(dir.xz + vec2(0.0001));
	vec2 shd = normalize(sd.xz + vec2(0.0001));
	float az = max(dot(hd, shd), 0.0);
	float band = exp(-abs(h) * 4.5);
	float g = clamp(glow_amount * (0.25 + 0.75 * pow(az, 2.5)) * band, 0.0, 1.0);
	col = mix(col, glow_color, g * 0.8);

	// ---- stars (night only)
	if (!AT_CUBEMAP_PASS && star_vis > 0.001 && h > 0.0) {
		vec3 sp = dir * 260.0;
		vec3 cell = floor(sp);
		float hs = hash31(cell);
		if (hs > 0.994) {
			vec3 jit = vec3(hash31(cell + 7.1), hash31(cell + 13.3), hash31(cell + 3.7)) - 0.5;
			float k = smoothstep(0.5, 0.05, length(fract(sp) - 0.5 + jit * 0.5));
			float br = 0.4 + 0.6 * (hs - 0.994) / 0.006;
			col += vec3(0.85, 0.9, 1.0) * k * br * smoothstep(0.0, 0.12, h) * star_vis * (1.0 - cloud_a);
		}
	}

	// ---- sun: warm glow around + small bright disc
	float r = radians(sun_size);
	float disc = smoothstep(cos(r * 1.25), cos(r * 0.9), cs);
	float glow = pow(max(cs, 0.0), 220.0) * 0.9 + pow(max(cs, 0.0), 18.0) * 0.22 + pow(max(cs, 0.0), 4.0) * 0.06;
	float above = smoothstep(-0.05, 0.03, h);
	float sun_vis = above * (1.0 - cloud_a * 0.96);
	col += sun_tint * glow * above * (1.0 - cloud_a * 0.6) * clamp(sun_power / 8.0, 0.0, 1.0);

	col = mix(col, cloud_col, cloud_a);
	col = mix(col, sun_tint * sun_power, disc * sun_vis);   // HDR value: stays bright after tone mapping

	// ---- moon: pale disc with a faint halo, behind the clouds
	vec3 md = normalize(moon_dir);
	float mc = dot(dir, md);
	float mr = radians(1.3);
	float mdisc = smoothstep(cos(mr * 1.15), cos(mr * 0.95), mc);
	float mabove = smoothstep(-0.03, 0.04, h) * (1.0 - cloud_a * 0.92);
	col += vec3(0.6, 0.7, 1.0) * pow(max(mc, 0.0), 150.0) * 0.25 * mabove;
	col = mix(col, vec3(0.92, 0.94, 1.0), mdisc * mabove * 0.95);

	COLOR = col;
}
"""


static func make_material(sun_dir: Vector3, cover: float = 0.5) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = CODE
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("sun_dir", sun_dir)
	m.set_shader_parameter("cloud_cover", cover)
	return m
