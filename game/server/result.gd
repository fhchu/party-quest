extends "res://server/room_phase.gd"
## The outcome shows over a frozen world, then town comes back.

const Town := preload("res://server/town.gd")
const Tuning := preload("res://sim/tuning.gd")

var outcome: RoomState.Outcome

var _ticks_left := Tuning.result_ticks


func _init(match_outcome: RoomState.Outcome) -> void:
	outcome = match_outcome


func fill_state(out: RoomState) -> void:
	out.phase = RoomState.Phase.RESULT
	out.outcome = outcome


func runs_world() -> bool:
	return false


func step(room: Room, now_msec: int) -> void:
	_ticks_left -= 1
	if _ticks_left <= 0:
		room.change_phase(Town.new(), now_msec)


## Presses now are spent, so none swings once town comes back.
func on_input(room: Room, seat: Room.Seat, _move: Vector2, attack_count: int) -> void:
	room.world.discard_attacks(seat.player_id, attack_count)
