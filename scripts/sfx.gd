extends RefCounted
# Sound effects made from math. No sound files needed (like the horn in main.gd).
# Every function returns an AudioStreamWAV that you put into an AudioStreamPlayer.
#
#   Sfx.footstep(seed)  one step on grass / soil
#   Sfx.jump()          the push-off of a jump
#   Sfx.land()          landing thud
#   Sfx.engine()        tractor engine, LOOPS (change pitch_scale to change the RPM)
#   Sfx.crash()         tractor hits a wall / something hard
#
# To make a sound louder or quieter: change volume_db on the AudioStreamPlayer (0 = full, -6 = half).

const RATE := 22050


# floats (-1..1) -> a playable stream
static func _wav(s: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var peak := 0.0001
	for v in s:
		peak = maxf(peak, absf(v))
	var scale := 0.95 / peak   # loudest point = 95 %, never clips
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i] * scale, -1.0, 1.0) * 32000.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = data
	if loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = s.size()
	return st


# soft step on grass: a gentle "shff-crunch". No sharp start and no thump (a sharp start sounds like a gunshot).
static func footstep(seed_value: int = 1) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(RATE * 0.2)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp1 := 0.0
	var lp2 := 0.0
	var dull := 0.0
	var grit_t := rng.randf_range(0.03, 0.05)   # small second crunch of the grass
	for i in n:
		var t := float(i) / RATE
		# soft swell (about 25 ms up), then a slow fade
		var env := smoothstep(0.0, 0.025, t) * exp(-t * 17.0)
		var w := rng.randf_range(-1.0, 1.0)
		lp1 += 0.45 * (w - lp1)
		lp2 += 0.12 * (w - lp2)
		var rustle := (lp1 - lp2)   # band of noise: the swish of grass blades (no deep rumble, no hiss)
		dull += 0.05 * (w - dull)   # very soft low body of the step
		var crunch := smoothstep(grit_t, grit_t + 0.012, t) * exp(-(t - grit_t) * 40.0) if t > grit_t else 0.0
		s[i] = rustle * env * 1.2 + dull * env * 1.5 + (lp1 - lp2) * crunch * 0.7
	return _wav(s)


# "hup": a short airy whoosh + a rising little tone
static func jump() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := int(RATE * 0.26)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := float(i) / n
		var env := sin(PI * minf(k * 1.15, 1.0)) * exp(-t * 6.0)
		lp += lerpf(0.08, 0.45, k) * (rng.randf_range(-1.0, 1.0) - lp)
		ph += TAU * lerpf(170.0, 330.0, k) / RATE
		s[i] = (lp * 1.3 + sin(ph) * 0.35) * env
	return _wav(s)


# landing: low thump + a puff of dust
static func land() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var n := int(RATE * 0.28)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(46.0, 120.0, exp(-t * 22.0))
		ph += TAU * f / RATE
		lp += 0.3 * (rng.randf_range(-1.0, 1.0) - lp)
		var env := minf(t / 0.003, 1.0)
		s[i] = (sin(ph) * exp(-t * 15.0) * 0.9 + lp * exp(-t * 26.0) * 0.8) * env
	return _wav(s)


# tractor engine: a rumbling pulse train. EXACTLY 1 second, whole cycles only -> the loop has no click.
# The player changes pitch_scale (0.8 = idle ... 2 = full speed).
static func engine() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var n := RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var f0 := 28.0   # 28 "putt" per second at pitch 1
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in range(1, 14):
			# the harmonics around 100-250 Hz are the strongest (what a phone speaker can play)
			var w := 1.0 / sqrt(float(k)) * (1.0 if k >= 3 else 0.7)
			v += w * sin(TAU * f0 * k * t + float(k) * 0.9)
		var lump := 0.75 + 0.25 * sin(TAU * 7.0 * t)   # uneven firing, 7 times per second
		var chug := 0.65 + 0.35 * pow(maxf(0.0, sin(TAU * 14.0 * t)), 2.0)
		s[i] = v * lump * chug * 0.2 + rng.randf_range(-1.0, 1.0) * 0.05
	return _wav(s, true)


# crash: heavy thump + crunch + a metallic clang
static func crash() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := int(RATE * 0.9)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var ph := 0.0
	var partials := [[311.0, 9.0, 0.16], [523.0, 11.0, 0.13], [887.0, 14.0, 0.09], [1290.0, 18.0, 0.06]]
	for i in n:
		var t := float(i) / RATE
		ph += TAU * lerpf(34.0, 95.0, exp(-t * 14.0)) / RATE
		lp += 0.5 * (rng.randf_range(-1.0, 1.0) - lp)
		var v := sin(ph) * exp(-t * 7.0) * 1.0
		v += lp * exp(-t * 9.0) * 0.9
		for p in partials:
			var pf: float = p[0]
			var pd: float = p[1]
			var pa: float = p[2]
			v += sin(TAU * pf * t) * exp(-t * pd) * pa
		s[i] = v * minf(t / 0.002, 1.0)
	return _wav(s)


# rifle shot: sharp crack + low boom + a short tail
static func gunshot() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var n := int(RATE * 0.75)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(38.0, 150.0, exp(-t * 30.0))
		ph += TAU * f / RATE
		lp += 0.55 * (rng.randf_range(-1.0, 1.0) - lp)
		var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 90.0)
		var tail := lp * exp(-t * 9.0) * 0.45
		s[i] = (crack * 0.9 + sin(ph) * exp(-t * 11.0) * 0.9 + tail) * minf(t / 0.0007, 1.0)
	return _wav(s)


