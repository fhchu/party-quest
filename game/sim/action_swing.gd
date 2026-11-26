extends "res://sim/action.gd"
## A swing in an arc in front of the player, slice by slice, from the
## item's data (see [method WorldLoader.new_action]). It roots its holder.

const HitArea := preload("res://sim/hit_area.gd")

## How long the arc is active.
var active_ticks := 0
## From the holder's center to where the swing starts, along its facing, in
## px.
var offset := 0.0
## The active slice, pointing along +x, as convex pieces.
var pieces: Array[ConvexPolygonShape2D] = []
## How far the active slice is turned from the facing, on each tick of the
## swing from its first.
var turns := PackedFloat32Array()

## See [method slot_ticks].
var _elapsed := 0
var _area: HitArea


func step(_held: bool) -> void:
	if _elapsed == 0:
		return
	_elapsed += 1
	if _elapsed > active_ticks:
		cancel()
	else:
		_place()


func start(_held: bool) -> HitArea:
	_elapsed = 1
	_area = HitArea.new()
	_area.pieces = pieces
	_area.action = weakref(self)
	_place()
	return _area


func is_busy() -> bool:
	return _elapsed > 0


func is_rooted() -> bool:
	return true


func slot_ticks() -> int:
	return _elapsed


## Its area stops hitting even if the swing starts again at once.
func cancel() -> void:
	_elapsed = 0
	if _area:
		_area.action = null
	_area = null


## Turns the area to this tick's slice.
func _place() -> void:
	_area.local = Transform2D(turns[_elapsed - 1], Vector2(offset, 0))
