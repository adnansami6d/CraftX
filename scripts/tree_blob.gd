extends RefCounted
# BIG SHADE TREES (100). v_006: every tree is its OWN shape (see tree_gen.gd) - different height, different type, different thickness.
#   The old version made one mesh and copied it 100 times, with a thin trunk under a huge crown and no branches.
#   Now: thick trunk with a flared foot, real branches that carry the leaf masses, crown size that fits the trunk.
#   6 types x random numbers = 100 different trees. Same seed = same forest.
#   Cost: trees of one map cell are merged into 1 mesh (1 draw call per cell), no texture, no alpha, no shadow.
#   Switch + numbers: config.gd (BIG_TREES) and the tables below.

const Gen = preload("res://scripts/tree_gen.gd")

const COUNT := 100
const MIN_DIST := 15.0         # metres between two big trees
const SPOT_MARGIN := 5.0       # free space round the trunk (houses, roads, rails)
const WORLD_SEED := 9091
const DESERT_MAX := 0.01       # no big tree where the desert weight is higher
const SWAMP_MAX := 0.6
const TRUNK_HIT := 0.85        # collision radius = trunk radius x this

# leaf colours: [dark (low in the crown), light (top)]
const LEAF := [
	[Color(0.10, 0.26, 0.09), Color(0.42, 0.62, 0.18)],   # 0 deep forest green
	[Color(0.16, 0.30, 0.10), Color(0.52, 0.68, 0.22)],   # 1 classic green
	[Color(0.20, 0.30, 0.08), Color(0.62, 0.70, 0.20)],   # 2 olive / yellow-green
	[Color(0.09, 0.28, 0.16), Color(0.36, 0.62, 0.34)],   # 3 blue-green
	[Color(0.14, 0.24, 0.07), Color(0.46, 0.56, 0.16)],   # 4 dry olive
	[Color(0.12, 0.32, 0.08), Color(0.60, 0.78, 0.25)],   # 5 bright lime
	[Color(0.07, 0.20, 0.07), Color(0.30, 0.50, 0.14)],   # 6 dark mango green
]
# bark colours: [foot, top]
const BARK := [
	[Color(0.20, 0.14, 0.09), Color(0.36, 0.26, 0.17)],   # 0 brown
	[Color(0.15, 0.11, 0.08), Color(0.28, 0.21, 0.15)],   # 1 dark
	[Color(0.28, 0.24, 0.20), Color(0.46, 0.40, 0.34)],   # 2 grey-brown
	[Color(0.28, 0.16, 0.10), Color(0.45, 0.28, 0.18)],   # 3 reddish
	[Color(0.34, 0.28, 0.20), Color(0.52, 0.45, 0.35)],   # 4 pale
]

# the 6 types. Every value is a RANGE [from, to]; every tree draws its own numbers.
const TYPES := [
	# 0 round shade tree: thick trunk, 4-6 limbs, round crown
	{"shape": "round", "h": [10.0, 15.0], "r": [0.75, 1.15], "th": [0.30, 0.40], "limbs": [4, 6], "ll": [3.0, 4.8], "up": [0.7, 1.3],
		"tw": [0, 1], "br": [2.6, 3.6], "fl": [0.70, 0.85], "fr": [4.2, 6.0], "lean": 0.6, "leaf": [0, 1, 2, 3, 5], "bark": [0, 1, 2, 3]},
	# 1 tall oval tree: tall, narrow, steep limbs
	{"shape": "vase", "h": [14.0, 22.0], "r": [0.75, 1.15], "th": [0.38, 0.46], "limbs": [3, 5], "ll": [3.0, 5.0], "up": [1.6, 2.6],
		"tw": [0, 1], "br": [2.2, 3.0], "fl": [1.1, 1.5], "fr": [2.8, 3.8], "lean": 0.8, "leaf": [0, 1, 3, 6], "bark": [0, 1, 2, 4]},
	# 2 wide spreading tree: very thick short trunk, long flat limbs, huge flat crown
	{"shape": "umbrella", "h": [8.0, 12.0], "r": [1.0, 1.6], "th": [0.30, 0.40], "limbs": [5, 7], "ll": [5.0, 8.0], "up": [0.15, 0.40],
		"tw": [0, 1], "br": [3.0, 4.2], "fl": [0.40, 0.55], "fr": [6.0, 8.5], "lean": 0.4, "leaf": [1, 2, 4, 5, 6], "bark": [0, 2, 3, 4]},
	# 3 layered tree: tall trunk, flat leaf layers one above the other
	{"shape": "layered", "h": [14.0, 20.0], "r": [0.70, 1.10], "th": [0.42, 0.50], "limbs": [8, 8], "ll": [3.5, 6.0], "up": [0.15, 0.35],
		"tw": [0, 0], "br": [2.2, 3.2], "fl": [0.40, 0.55], "fr": [3.0, 4.5], "lean": 0.5, "leaf": [0, 2, 3, 5], "bark": [0, 1, 3]},
	# 4 low dome tree: short fat trunk, big round crown close to the ground
	{"shape": "round", "h": [7.0, 10.0], "r": [0.90, 1.40], "th": [0.20, 0.28], "limbs": [5, 7], "ll": [3.0, 4.5], "up": [0.5, 0.9],
		"tw": [0, 1], "br": [3.2, 4.4], "fl": [0.75, 0.90], "fr": [5.0, 7.0], "lean": 0.4, "leaf": [1, 4, 5, 6], "bark": [0, 1, 2]},
	# 5 old open tree: thick trunk, big bare limbs, leaf masses only at the ends
	{"shape": "open", "h": [9.0, 13.0], "r": [0.90, 1.40], "th": [0.28, 0.36], "limbs": [5, 6], "ll": [4.5, 7.0], "up": [0.6, 1.2],
		"tw": [0, 1], "br": [2.0, 2.8], "fl": [0.65, 0.85], "fr": [0.0, 0.0], "lean": 1.0, "leaf": [0, 2, 3, 4], "bark": [1, 2, 4]},
]


static var wait_banyans := false
static var wait_conifers := false


# one tree = one table of numbers (type = i % 6, so every type gets about the same number of trees)
static func make(rng: RandomNumberGenerator, i: int, _count: int) -> Dictionary:
	var T: Dictionary = TYPES[i % TYPES.size()]
	return Gen.params(rng, T, LEAF, BARK)


static func place_all(world: Node, report: Callable) -> void:
	var wait: Array = []
	if wait_banyans:
		wait.append("Banyans")
	if wait_conifers:
		wait.append("Conifers")
	Gen.start(world, report, {
		"name": "BigTrees", "report_key": "bigtree", "count": COUNT, "min_dist": MIN_DIST, "margin": SPOT_MARGIN, "seed": WORLD_SEED,
		"desert_max": DESERT_MAX, "swamp_max": SWAMP_MAX, "wait_nodes": wait, "trunk_hit": TRUNK_HIT,
		"own_r": 6.0, "desert_ring": 22.0, "desert_ring_max": 0.03,
		"maker": func(r: RandomNumberGenerator, i: int, n: int) -> Dictionary: return make(r, i, n),
	})
