extends RefCounted
# 100 NEW TREES of a completely new kind (v_006): flowering, autumn, weeping, columnar, umbrella and bottle trees.
#   12 types, every tree its OWN random numbers (height, thickness, limbs, colours), real branches, no two alike.
#   Made by tree_gen.gd. Not in the desert. Same seed = same forest.
#   Switch: config.gd (NEW_TREES).
#   Types: 0 birch (white trunk)  1 cherry blossom (pink)  2 maple (autumn red / orange / yellow)  3 weeping willow
#          4 cypress / poplar (tall column)  5 acacia (flat umbrella)  6 baobab (very fat bottle trunk)  7 jarul (purple flowers)
#          8 old gnarled tree  9 rain tree (tall, very thick)  10 krishnachura (red flame umbrella)  11 golden shower (yellow, hanging)

const Gen = preload("res://scripts/tree_gen.gd")

const COUNT := 100
const MIN_DIST := 12.0
const SPOT_MARGIN := 4.0
const WORLD_SEED := 31337
const DESERT_MAX := 0.01
const SWAMP_MAX := 0.6
const TRUNK_HIT := 0.85

const LEAF := [
	[Color(0.28, 0.42, 0.10), Color(0.70, 0.80, 0.25)],   # 0 birch: light yellow-green
	[Color(0.78, 0.38, 0.52), Color(1.00, 0.82, 0.88)],   # 1 cherry pink
	[Color(0.70, 0.30, 0.48), Color(0.98, 0.70, 0.82)],   # 2 cherry deep pink
	[Color(0.85, 0.60, 0.70), Color(1.00, 0.95, 0.95)],   # 3 cherry white-pink
	[Color(0.42, 0.07, 0.05), Color(0.88, 0.22, 0.08)],   # 4 maple red
	[Color(0.60, 0.25, 0.04), Color(0.98, 0.60, 0.10)],   # 5 maple orange
	[Color(0.62, 0.42, 0.05), Color(1.00, 0.85, 0.20)],   # 6 maple yellow
	[Color(0.30, 0.44, 0.10), Color(0.68, 0.80, 0.30)],   # 7 willow
	[Color(0.06, 0.20, 0.08), Color(0.22, 0.46, 0.16)],   # 8 cypress dark
	[Color(0.10, 0.26, 0.08), Color(0.40, 0.58, 0.16)],   # 9 poplar
	[Color(0.22, 0.32, 0.08), Color(0.58, 0.66, 0.20)],   # 10 acacia olive
	[Color(0.24, 0.38, 0.12), Color(0.55, 0.72, 0.28)],   # 11 baobab light green
	[Color(0.33, 0.17, 0.48), Color(0.72, 0.55, 0.90)],   # 12 purple
	[Color(0.40, 0.20, 0.55), Color(0.82, 0.62, 0.95)],   # 13 violet
	[Color(0.12, 0.18, 0.06), Color(0.40, 0.46, 0.12)],   # 14 gnarled dark olive
	[Color(0.40, 0.30, 0.06), Color(0.80, 0.62, 0.15)],   # 15 gnarled gold
	[Color(0.07, 0.22, 0.09), Color(0.32, 0.52, 0.18)],   # 16 rain tree deep green
	[Color(0.48, 0.05, 0.04), Color(0.95, 0.25, 0.08)],   # 17 flame red
	[Color(0.60, 0.07, 0.03), Color(1.00, 0.36, 0.10)],   # 18 flame orange-red
	[Color(0.70, 0.50, 0.04), Color(1.00, 0.88, 0.22)],   # 19 golden yellow
]
const BARK := [
	[Color(0.30, 0.27, 0.22), Color(0.86, 0.84, 0.78)],   # 0 birch: dark foot, white trunk
	[Color(0.20, 0.13, 0.10), Color(0.34, 0.22, 0.17)],   # 1 dark cherry
	[Color(0.26, 0.18, 0.12), Color(0.40, 0.30, 0.20)],   # 2 brown
	[Color(0.40, 0.35, 0.30), Color(0.56, 0.50, 0.44)],   # 3 grey (baobab)
	[Color(0.13, 0.10, 0.08), Color(0.26, 0.20, 0.16)],   # 4 gnarled dark
	[Color(0.32, 0.18, 0.12), Color(0.48, 0.30, 0.20)],   # 5 reddish
]

const TYPES := [
	# 0 birch: tall, slender, white trunk, small light crown
	{"shape": "vase", "h": [11.0, 16.0], "r": [0.32, 0.50], "th": [0.50, 0.60], "limbs": [5, 7], "ll": [2.0, 3.2], "up": [1.2, 2.0],
		"tw": [0, 0], "br": [1.4, 2.0], "fl": [0.9, 1.2], "fr": [2.0, 2.8], "lean": 0.9, "leaf": [0], "bark": [0]},
	# 1 cherry blossom: short thick trunk, wide pink crown
	{"shape": "round", "h": [6.0, 9.0], "r": [0.45, 0.75], "th": [0.30, 0.40], "limbs": [5, 7], "ll": [2.5, 4.0], "up": [0.5, 0.9],
		"tw": [0, 1], "br": [2.0, 2.8], "fl": [0.70, 0.90], "fr": [3.5, 4.5], "lean": 0.6, "leaf": [1, 2, 3], "bark": [1, 4]},
	# 2 maple: autumn colours
	{"shape": "round", "h": [9.0, 14.0], "r": [0.55, 0.90], "th": [0.30, 0.38], "limbs": [4, 6], "ll": [3.0, 4.6], "up": [0.8, 1.4],
		"tw": [0, 1], "br": [2.4, 3.3], "fl": [0.75, 0.95], "fr": [3.8, 5.2], "lean": 0.7, "leaf": [4, 5, 6], "bark": [2, 5]},
	# 3 weeping willow: arching limbs, hanging curtains
	{"shape": "weeping", "h": [9.0, 13.0], "r": [0.80, 1.20], "th": [0.28, 0.34], "limbs": [4, 6], "ll": [3.5, 5.0], "up": [0.8, 1.0],
		"tw": [0, 1], "br": [2.2, 3.0], "fl": [0.80, 0.90], "fr": [3.5, 4.5], "lean": 0.8, "leaf": [7], "bark": [2, 4]},
	# 4 cypress / poplar: tall dark column
	{"shape": "column", "h": [14.0, 22.0], "r": [0.35, 0.60], "th": [0.25, 0.40], "limbs": [6, 9], "ll": [1.5, 2.6], "up": [0.5, 0.9],
		"tw": [0, 0], "br": [1.0, 1.6], "fl": [1.1, 1.5], "fr": [1.6, 2.4], "lean": 0.5, "leaf": [8, 9], "bark": [2, 4]},
	# 5 acacia: thin forked trunk, wide flat umbrella
	{"shape": "umbrella", "h": [8.0, 12.0], "r": [0.40, 0.65], "th": [0.55, 0.65], "limbs": [4, 5], "ll": [3.0, 4.5], "up": [0.4, 0.8],
		"tw": [0, 1], "br": [2.8, 3.8], "fl": [0.30, 0.42], "fr": [5.5, 8.0], "lean": 0.9, "leaf": [10, 11], "bark": [2, 4, 5]},
	# 6 baobab: huge fat bottle trunk, short thick limbs, small crown
	{"shape": "bottle", "h": [7.0, 11.0], "r": [1.5, 2.4], "th": [0.50, 0.60], "limbs": [5, 7], "ll": [2.2, 3.8], "up": [0.6, 1.2],
		"tw": [0, 0], "br": [1.4, 2.0], "fl": [0.70, 0.90], "fr": [2.4, 3.4], "lean": 0.3, "leaf": [11, 10], "bark": [3]},
	# 7 jarul: purple flowers, V-shaped limbs
	{"shape": "round", "h": [8.0, 12.0], "r": [0.50, 0.80], "th": [0.30, 0.40], "limbs": [4, 6], "ll": [3.0, 4.5], "up": [1.2, 2.0],
		"tw": [0, 1], "br": [2.2, 3.0], "fl": [0.70, 0.85], "fr": [3.5, 4.5], "lean": 0.7, "leaf": [12, 13], "bark": [1, 2]},
	# 8 old gnarled tree: thick leaning trunk, bare limbs, sparse leaves
	{"shape": "open", "h": [6.0, 10.0], "r": [0.60, 1.00], "th": [0.30, 0.40], "limbs": [6, 7], "ll": [3.0, 5.0], "up": [0.3, 1.2],
		"tw": [0, 1], "br": [1.2, 1.9], "fl": [0.70, 0.90], "fr": [0.0, 0.0], "lean": 1.6, "leaf": [14, 15], "bark": [4, 1]},
	# 9 rain tree: very tall, very thick trunk, dome crown
	{"shape": "vase", "h": [16.0, 24.0], "r": [1.0, 1.5], "th": [0.60, 0.70], "limbs": [5, 7], "ll": [3.5, 5.5], "up": [0.9, 1.5],
		"tw": [0, 0], "br": [2.8, 3.8], "fl": [0.80, 1.0], "fr": [4.5, 6.0], "lean": 0.6, "leaf": [16, 0], "bark": [2, 3]},
	# 10 krishnachura: red flame, wide flat umbrella
	{"shape": "umbrella", "h": [8.0, 11.0], "r": [0.60, 0.95], "th": [0.40, 0.50], "limbs": [5, 7], "ll": [3.5, 5.5], "up": [0.25, 0.50],
		"tw": [0, 1], "br": [2.6, 3.6], "fl": [0.40, 0.55], "fr": [5.0, 7.0], "lean": 0.7, "leaf": [17, 18], "bark": [2, 5]},
	# 11 golden shower: yellow, hanging tassels
	{"shape": "weeping", "h": [8.0, 11.0], "r": [0.50, 0.80], "th": [0.35, 0.45], "limbs": [4, 5], "ll": [3.0, 4.5], "up": [0.8, 1.0],
		"tw": [0, 1], "br": [2.0, 2.8], "fl": [0.75, 0.90], "fr": [3.0, 4.0], "lean": 0.7, "leaf": [19], "bark": [2, 5]},
]


static var wait_nodes: Array = []


static func make(rng: RandomNumberGenerator, i: int, _count: int) -> Dictionary:
	var T: Dictionary = TYPES[i % TYPES.size()]
	return Gen.params(rng, T, LEAF, BARK)


static func place_all(world: Node, report: Callable) -> void:
	Gen.start(world, report, {
		"name": "MixTrees", "report_key": "newtree", "count": COUNT, "min_dist": MIN_DIST, "margin": SPOT_MARGIN, "seed": WORLD_SEED,
		"desert_max": DESERT_MAX, "swamp_max": SWAMP_MAX, "wait_nodes": wait_nodes, "trunk_hit": TRUNK_HIT,
		"own_r": 5.0, "desert_ring": 22.0, "desert_ring_max": 0.03,
		"maker": func(r: RandomNumberGenerator, i: int, n: int) -> Dictionary: return make(r, i, n),
	})
