extends RefCounted
## Every gameplay number here is a PLACEHOLDER picked only so the spike runs.
## The real values are design decisions; in Phase 1 they move to a versioned
## balance file that feeds the backend's balance_version.

const BALANCE_VERSION := "spike-0"

const ARENA := Rect2(0, 0, 960, 540)
const PLAYER_SPEED := 120.0  # px/s
const SWING_TICKS := 12  # how long the arc is active
const SWING_COOLDOWN_TICKS := 18  # after the arc ends; presses during it are dropped
const SWING_RADIUS := 40.0
const SWING_ARC := PI * 0.75  # radians, centered on facing
const HIT_FLASH_TICKS := 9

# Not design: load for the "~30 sprites at 60 fps" kill criterion.
const DUMMY_COUNT := 30
const DUMMY_SPEED := 30.0
const DUMMY_TURN_TICKS := 90
