extends "res://sim/action.gd"
## Holding up a shield, while its input action is held: raised by a press
## while that input action is held, lowered by letting go. Its size comes
## from the item's data (WorldLoader.new_action). It doesn't root its
## holder, so another slot's press lowers it.

const Shield := preload("res://sim/shield.gd")

## In px: see [member ItemShield.thickness_px].
var thickness_px := 0.0
## In px: see [member ItemShield.length_px].
var length_px := 0.0

## Null while lowered.
var _shield: Shield
## See [method slot_ticks].
var _raised_ticks := 0


func step(held: bool) -> void:
	if not _shield:
		return
	if held:
		_raised_ticks += 1
	else:
		cancel()


func start(held: bool) -> RefCounted:
	if held:
		_shield = Shield.new(holder, Vector2(thickness_px, length_px))
		_raised_ticks = 1
	return null


func is_busy() -> bool:
	return _shield != null


func blocker() -> Shield:
	return _shield


func slot_ticks() -> int:
	return _raised_ticks


func cancel() -> void:
	_shield = null
	_raised_ticks = 0
