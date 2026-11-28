extends RefCounted
## One room's state, kept while the party is elsewhere.

const Unit := preload("res://sim/unit.gd")
const RoomPlan := preload("res://sim/room_plan.gd")
const RoomPaths := preload("res://sim/room_paths.gd")

## How many values [member graphics_seed] can have: snapshots send it as a
## u16. tests/net/snapshot_codec_test.gd checks.
const GRAPHICS_SEED_VALUES := 1 << 16

var units: Array[Unit] = []
## Its ways out, each seen from this room.
var doors: Array[RoomPlan.DoorPlan] = []
## Whether its doors are open. Set the first time any of its clear checks
## is met, and then never unset, except by WorldSimulator.set_room_cleared.
var cleared := false
## Each is passed the world and returns whether the room is cleared.
var clear_checks: Array[Callable] = []
## For units walking around each other.
var paths: RoomPaths
## Seeds how clients draw its floor, so every player sees the same one.
## From the global RNG, not the world's: sending a value from that would let
## clients predict its choices.
var graphics_seed := randi() % GRAPHICS_SEED_VALUES


## Units find their way across [param floor_area] in tiles of
## [param tile_size] px.
func _init(floor_area: Rect2, tile_size: float) -> void:
	paths = RoomPaths.new(floor_area, tile_size)
