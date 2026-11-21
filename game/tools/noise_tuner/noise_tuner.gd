@tool
extends Node2D
## Draws a floor the way the game does and redraws it whenever
## [member floor_noise] or [member graphics_seed] changes, so a floor's noise
## can be tuned by eye. Open noise_tuner.tscn in the editor, select this node
## and edit [member floor_noise] in the Inspector; changes save to its .tres.
## Needs the floor's tiles in client/assets/textures/.

const WorldRenderer := preload("res://client/world_renderer.gd")
const FloorNoise := preload("res://client/floor_noise.gd")

@export var graphics_seed := 0:
	set(value):
		graphics_seed = value
		_redraw()
@export var floor_noise: FloorNoise = preload("res://client/grass_noise.tres"):
	set(value):
		if floor_noise:
			floor_noise.changed.disconnect(_redraw)
		floor_noise = value
		if floor_noise:
			floor_noise.changed.connect(_redraw)
		_redraw()
## Picks a new random [member graphics_seed].
@export_tool_button("New seed") var pick_new_seed := func() -> void: graphics_seed = randi()

var _layer: TileMapLayer


func _ready() -> void:
	# The setter didn't run for the default value.
	if not floor_noise.changed.is_connected(_redraw):
		floor_noise.changed.connect(_redraw)
	_layer = WorldRenderer.make_floor_layer()
	if _layer:
		add_child(_layer)
	_redraw()


func _redraw() -> void:
	if not _layer or not floor_noise:
		return
	# The game's viewport, not the editor's.
	var viewport_size := Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	WorldRenderer.fill_floor(_layer, graphics_seed,
			WorldRenderer.floor_cells(_layer.tile_set, viewport_size), floor_noise)
