extends RefCounted
# Sound folders. Every sound of the game has its OWN folder in res://audio/ :
#   walk, run, jump, land, engine, crash, horn
# Put your real sound file (.ogg, .wav or .mp3) in a folder = the game plays YOUR sound.
# Folder empty = the game plays the built-in default sound made from math (scripts/sfx.gd).

const ROOT := "res://audio/"
const EXT := ["ogg", "wav", "mp3"]


# All your sound files inside audio/<folder>/ (sorted by name). Empty array = no custom sound.
static func custom_streams(folder: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(ROOT + folder)
	if dir == null:
		return out
	var names: Array = []
	for f in dir.get_files():
		var n: String = f
		# in an exported game the files are listed as "x.ogg.import" / "x.ogg.remap"
		if n.ends_with(".import"):
			n = n.trim_suffix(".import")
		elif n.ends_with(".remap"):
			n = n.trim_suffix(".remap")
		if EXT.has(n.get_extension().to_lower()) and not names.has(n):
			names.append(n)
	names.sort()
	for n in names:
		var st = load(ROOT + folder + "/" + n)
		if st is AudioStream:
			out.append(st)
		else:
			push_warning("audio: could not load " + ROOT + folder + "/" + str(n))
	return out


# a copy of the sound that repeats forever (engine, horn)
static func looped(st: AudioStream) -> AudioStream:
	var c: AudioStream = st.duplicate()
	if c is AudioStreamWAV:
		var w := c as AudioStreamWAV
		var bytes := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
		if w.stereo:
			bytes *= 2
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.data.size() / bytes)
	else:
		c.set("loop", true)   # ogg / mp3
	return c
