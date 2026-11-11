@abstract
extends RefCounted
## One of the room's phases: [code]town.gd[/code], [code]match.gd[/code]
## or [code]result.gd[/code]. The room holds one at a time and calls these
## hooks; what only one phase can do (start a match, end one) is a method on
## that phase alone.

const Room := preload("res://server/room.gd")
const World := preload("res://sim/world.gd")
const RoomState := preload("res://net/room_state.gd")
const Snapshot := preload("res://net/snapshot.gd")


## Sets the phase's part of what clients see, including which phase it is.
@abstract func fill_state(out: RoomState) -> void


## Called once, when the room changes to this phase.
func enter(_room: Room, _now_msec: int) -> void:
	pass


## Whether the world steps this tick. When it doesn't, only its tick counts
## on, so it looks frozen.
func runs_world() -> bool:
	return true


## One tick, after the world's.
func step(_room: Room, _now_msec: int) -> void:
	pass


func on_swing_contact(_room: Room, _contact: World.SwingContact, _now_msec: int) -> void:
	pass


func on_input(room: Room, seat: Room.Seat, move: Vector2, attack_count: int) -> void:
	# Longer than 1 would move faster than the player's speed. A spectator
	# has no character, so the world ignores it.
	room.world.set_input(seat.player_id, move.limit_length(1.0), attack_count)


func newcomer_readiness() -> RoomState.Readiness:
	return RoomState.Readiness.SPECTATING


func fill_snapshot(_snap: Snapshot) -> void:
	pass
