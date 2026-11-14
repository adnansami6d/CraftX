extends RefCounted
# How hard trees, bushes and rocks are to break. 1.0 = pistol 6 shots, rifle 20 shots (see shooter.gd WEAPONS hits).
# One shot does  (1 / hits) / hardness  damage; a thing breaks when its damage reaches 1.
#   stone = 3  (pistol 18 shots, rifle 60 shots)
#   wood  = 2  (a tree: pistol 12 shots, rifle 40 shots)
#   plants (bushes) = the lightest: ONE shot with any gun

const STONE := 3.0
const WOOD := 2.0
const PLANT := 0.05

const TREE_WOOD_PER_SIZE := 10.0    # a tree gives  size * this  wood (size is 0.8 .. 1.5)
const ROCK_STONE_PER_SIZE := 3.0    # a big rock gives  size * this  stone


static func for_kind(kind: String) -> float:
	match kind:
		"tree":
			return WOOD
		"bush":
			return PLANT
		"rock":
			return STONE
	return 0.0   # not breakable
