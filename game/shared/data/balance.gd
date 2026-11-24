extends Resource
## Gameplay values that hold everywhere, in px and seconds: the classes that
## use a value copy it when they load, converting durations to ticks.
## Values that stop being global move to the resource they belong to.

## The arena from its top-left corner at (0, 0). At most the viewport's size
## (project.godot): the whole arena is always on screen, so there's no camera.
@export var arena_size := Vector2.ZERO
## The side of one square tile, in px. The arena is a whole number of tiles
## each way.
@export var tile_size := 0.0
## How thick a room's walls and doors are, in px: a whole number of tiles.
@export var wall_thickness := 0.0

@export_group("Player")
## Centered on the player's position, unturned: what walls stop and what
## damage touches.
@export var player_hurtbox: Shape2D
## A player's health at the start of each world, and the most a heal gives
## back.
@export var player_max_health := 0

@export_group("Run")
## How long a run's result shows over its frozen world.
@export var result_sec := 0.0


func arena() -> Rect2:
	return Rect2(Vector2.ZERO, arena_size)
