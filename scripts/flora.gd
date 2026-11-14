extends RefCounted
# FOREST PLAN F2: ONE shared question for every new plant / tree:  "may something grow at (x, z)?"
#   Flora.spot_ok(x, z, margin)  -> true when the spot is free
#   Flora.biome_w(x, z)          -> [farm, forest, rock, desert, swamp] (same as Biome.weights)
# fx_map.gd calls Flora.setup(...) once. The "blocked" list already holds: start area, hill foot + beaches (edges),
# roads, plots, buildings, ponds (all with their own safety margin).

const Biome = preload("res://scripts/biome.gd")

const EDGE := 28.0   # no plants this close to the map edge (hill, sea)

static var blocked: Array = []   # Rect2 list (x, z), filled by fx_map.gd
static var rail = null           # railway.gd (near_track)
static var half := 500.0         # half size of the map


static func setup(blocked_rects: Array, railway, map_half: float) -> void:
	blocked = blocked_rects
	rail = railway
	half = map_half


static func biome_w(x: float, z: float) -> Array:
	return Biome.weights(x, z)


# margin = extra free distance in metres (a big tree = 3, a fern = 0)
static func spot_ok(x: float, z: float, margin: float = 0.0) -> bool:
	var lim := half - EDGE - margin
	if absf(x) > lim or absf(z) > lim:
		return false
	var p := Vector2(x, z)
	for b in blocked:
		if (b as Rect2).grow(margin).has_point(p):
			return false
	if rail != null:
		var m := int(ceil(margin / 8.0))
		for i in range(-m, m + 1):
			for j in range(-m, m + 1):
				if rail.near_track(x + float(i) * 8.0, z + float(j) * 8.0):
					return false
	return true


# text for the debug overlay: checks a few known places
static func self_test() -> String:
	var ok := true
	ok = ok and not spot_ok(0.0, 0.0, 0.0)               # start area must be blocked
	ok = ok and not spot_ok(half - 5.0, 0.0, 0.0)        # beach / hill foot
	ok = ok and not spot_ok(half + 10.0, 0.0, 0.0)       # outside the map
	var found := 0
	for i in 40:                                         # some free land must exist
		if spot_ok(-80.0 - float(i) * 9.0, -150.0 - float(i) * 5.0, 0.0):
			found += 1
	ok = ok and found > 0
	var w := biome_w(-300.0, -300.0)
	ok = ok and w.size() == 5
	return ("free spot test OK (%d/40 free)" % found) if ok else "free spot test FAILED"
