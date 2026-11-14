extends RefCounted
# Numbers of the vehicles (tractor, helicopter) that used to live in farm_data.gd (the farm economy is gone).
# The demo keeps the tanks full (main.gd), these numbers are only needed so the vehicle scripts work unchanged.

const FUEL_TANK_TRACTOR := 150.0   # liters
const FUEL_TANK_HELI := 150.0      # liters
const TRACTOR_KM_PER_L := 50.0     # km on 1 liter (normal driving)
const HELI_KM_PER_L := 500.0       # km on 1 liter
const WORK_FUEL_MULT := 2.0        # (old plow work, not used in My Plant)
const FUEL_SCALE := 1.0
