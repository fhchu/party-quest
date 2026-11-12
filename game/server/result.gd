extends "res://server/lobby_phase.gd"
## The outcome shows over a frozen world, then town comes back.

const GameTime := preload("res://shared/game_time.gd")
const Town := preload("res://server/town.gd")
const Tuning := preload("res://sim/tuning.gd")

## How long the outcome shows before town comes back.
static var duration_ticks := GameTime.ticks(Tuning.result_sec)

var outcome: LobbyState.Outcome

var _ticks_left := duration_ticks


func _init(run_outcome: LobbyState.Outcome) -> void:
	outcome = run_outcome


func fill_state(out: LobbyState) -> void:
	out.phase = LobbyState.Phase.RESULT
	out.outcome = outcome


func runs_world() -> bool:
	return false


func step(lobby: Lobby, now_msec: int) -> void:
	_ticks_left -= 1
	if _ticks_left <= 0:
		lobby.change_phase(Town.new(), now_msec)


## Presses now are spent, so none swings once town comes back.
func on_input(lobby: Lobby, seat: Lobby.Seat, _move: Vector2, attack_count: int) -> void:
	lobby.world.discard_attacks(seat.player_id, attack_count)
