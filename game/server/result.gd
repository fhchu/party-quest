extends "res://server/room_phase.gd"
## The outcome shows while everyone stands, then the lobby comes back.

const Lobby := preload("res://server/lobby.gd")
const Tuning := preload("res://sim/tuning.gd")

var outcome: RoomState.Outcome

var _ticks_left := Tuning.result_ticks


func _init(match_outcome: RoomState.Outcome) -> void:
	outcome = match_outcome


func fill_state(out: RoomState) -> void:
	out.phase = RoomState.Phase.RESULT
	out.outcome = outcome


func enter(room: Room, _now_msec: int) -> void:
	for seat in room.seats():
		room.world.set_input(seat.player_id, Vector2.ZERO, 0)


func step(room: Room, now_msec: int) -> void:
	_ticks_left -= 1
	if _ticks_left <= 0:
		room.change_phase(Lobby.new(), now_msec)


## Presses now are spent, so none swings once the lobby comes back.
func on_input(room: Room, seat: Room.Seat, _move: Vector2, attack_count: int) -> void:
	room.world.discard_attacks(seat.player_id, attack_count)
