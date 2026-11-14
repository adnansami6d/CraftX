extends RefCounted
# One place for switches and numbers of the whole game.
# Use:  const Cfg = preload("res://scripts/config.gd")   then   Cfg.VERSION


const VERSION := "CraftX v_012d"

# --- ground (F15)
const GROUND_BRIGHT := 0.9              # F17: ground brightness (1.0 = as F11c, 1.3 = brighter). Too dark -> raise, too bright -> lower
const MOUNTAIN_BRIGHT := 1.0          # F17: mountain brightness (same idea)
const REAL_GRASS := true               # F17: ground + mountain use the F11c grass / dirt pictures (false = noise fallback, no pictures)

# --- forest plan
const MOUNTAIN := true                # F6: one big real mountain in a free place of the map (false = none)
const CONIFERS := true                # 40 realistic spruce / fir / pine trees (6 draw calls in total, scripts/tree_conifer.gd)
const BIG_TREES := true               # v_006: 100 big shade trees, every one different (6 types, thick trunk, real branches), scripts/tree_blob.gd
const NEW_TREES := true               # v_006: 100 NEW trees (birch, cherry, maple, willow, cypress, acacia, baobab, jarul, old, rain, krishnachura, golden shower), scripts/tree_mix.gd
const COMBAT := true                  # v_007: bandits, player health, combat HUD, camp missions (from Fx99). false = the game runs as in v_006
const NIGHT_ELEV := 0.0               # v_007: night = sun lower than this many degrees (bandits / zombies attack)
const NIGHT_TOTAL := 20               # v_007c: most bandits in ONE night (then the rest of the night is calm)
const WAVE_SIZE := 10                 # v_007c: bandits per wave; next wave comes 30-60 s after the wave is dead
const NIGHT_MAX := 8                  # v_007: most bandits alive at the same time (cheap for phones)
const TORCH := true                   # v_008: torches stop NEW night spawns near them (false = no spawn protection, as v_007c). Torch block itself stays (id 10)
const TORCH_SAFE_RADIUS := 12.0       # v_008: no new bandit / zombie spawns within this many metres (flat distance) of a torch
const TORCH_REAL_LIGHTS := 4          # v_008: real lights only on the nearest N torches (phone); all others: flame + glow quad only
const COCONUTS := true                # F7: coconut palms on all four beaches (false = none)
const NEW_BANYANS := true             # F5: 30 banyan trees in the world (false = none)

# --- sun (F8)
const SUN := true                      # a real sun: visible disc in the sky + warm direct light (false = the old flat light)
const SHADOWS := false                  # sun shadows (cost FPS on phones: false = no shadows, or lower SHADOW_DISTANCE)
const SHADOW_DISTANCE := 45.0          # metres around the camera that get shadows (smaller = faster + sharper)
const SUN_ELEVATION := 28.0            # degrees above the horizon (day / night later: change this + the colours)
const SUN_COLOR := Color(1.0, 0.84, 0.62)      # F9: warm golden sunlight
const SUN_ENERGY := 1.0                        # F9: strong direct light
const AMBIENT_COLOR := Color(0.55, 0.66, 0.9)  # F9: shadows are cool blue (light from the sky), the lit places are warm
const AMBIENT_ENERGY := 0.4                    # F12: higher = lighter, softer shadows (was 0.32)
const SUN_FILMIC := true                       # F9: filmic tone mapping (bright places do not burn out) + a little contrast
const SUN_AZIMUTH := 130.0             # compass turn of the light (130 = sun in front on the right when you start)

# --- sky (F10)
const FOG := false                     # F10: no fog / haze at all (the old fog is deleted)
const CLOUDS := true                   # F10: drifting cumulus clouds in a blue sky (false = clear sky)
const CLOUD_COVER := 0.62              # 0 = almost no clouds, 1 = cloudy
const CLOUD_SPEED := 1.0               # wind speed of the clouds (0 = they stand still)

# --- day and night (F11)
const DAY_NIGHT := true                # F11: the sun moves, sunrise / sunset, moon + stars at night (false = fixed daytime)
const DAY_SECONDS := 1440.0            # v1.0: real seconds for one whole day (1440 = 24 minutes)
const START_HOUR := 6.0                # game clock at the start (6.0 = sunrise 06:00 AM, 12 = noon)
const LIGHT_STEP := 0.5                # F11b: seconds between shadow-direction updates (bigger = steadier shadows, jumps a little)
const MOON_ENERGY := 0.3               # strength of the moonlight

# --- picture quality (F11b)
const RENDER_SCALE := 0.65             # v1.0: 3D resolution (1.0 = full, lower = faster; UI stays sharp). 0.5 = very fast, 0.8 = sharper
const EXPOSURE := 0.92                 # v1.0: overall brightness (lower = darker, face not burnt)
const MSAA := false                    # F11b: smooth edges (poles, trees, shadows) - stops the flicker. false = faster on a weak phone

# --- vehicle lights (v_002)
const LIGHTS := true                   # tractor + helicopter headlights (false = none)
const LIGHT_ON_ELEV := 15.0             # lights switch on when the sun is lower than this many degrees (dusk, night, dawn)

# --- warm-up (step3b)
const WARMUP := true                   # draws everything once during loading (no freeze later). false = off, loading is a bit shorter

# --- debug
const DEBUG_OVERLAY := false           # small info text at the top of the screen (FPS, position, draw calls ...). false = hidden
const DEBUG_OVERLAY_INTERVAL := 0.25   # seconds between updates (keeps it cheap on phones)
