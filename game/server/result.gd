extends "res://server/lobby_phase.gd"
## The outcome shows over a frozen world for a while.

const GameTime := preload("res://shared/game_time.gd")
const DataLoader := preload("res://shared/data_loader.gd")

## How long the outcome shows.
static var duration_ticks := GameTime.ticks(DataLoader.result_sec)

var outcome: LobbyState.Outcome

var _ticks_left := duration_ticks


func _init(run_outcome: LobbyState.Outcome) -> void:
	outcome = run_outcome


func fill_state(out: LobbyState) -> void:
	out.outcome = outcome


func runs_world() -> bool:
	return false


## Returns whether the outcome has shown for [member duration_ticks].
func step(_world: World) -> bool:
	_ticks_left -= 1
	return _ticks_left <= 0
