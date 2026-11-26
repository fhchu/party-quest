extends RefCounted
## What using an item in a slot does: one per item in a player's slots,
## built by [method WorldLoader.new_action] from the item's data. Its holder
## steps it every tick and starts it from its slot's press; the world asks
## every action the same questions, whatever it does.


## One tick, before any action starts. [param held] is whether its slot's
## input action is held.
func step(_held: bool) -> void:
	pass


## Starts it from a press of its slot's input action. Returns what it hits
## with (a hit_area.gd), for the world to resolve, or null for nothing.
## Untyped here so each action that hits preloads hit_area.gd itself.
func start(_held: bool) -> RefCounted:
	return null


## While busy, its holder isn't idle and no other action starts unless this
## one gives way (see [method is_rooted]).
func is_busy() -> bool:
	return false


## No moving or turning while it's busy, and a press of another slot is
## ignored; a busy action that doesn't root gives way to that press.
func is_rooted() -> bool:
	return false


## Ticks since it became active, counting its first as 1; 0 while idle.
## Clients draw it from this.
func slot_ticks() -> int:
	return 0


## Stops it at once, idle.
func cancel() -> void:
	pass
