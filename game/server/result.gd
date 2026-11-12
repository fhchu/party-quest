extends "res://server/lobby_phase.gd"
## The outcome shows over a frozen world for a while.

const GameTime := preload("res://shared/game_time.gd")
const DataLoader := preload("res://shared/data_loader.gd")

## How long the outcome shows.
static var duration_ticks := GameTime.ticks(DataLoader.result_sec)

var outcome: LobbyState.Outcome

var _ends_at_tick: int


## [param start_tick] is the world's tick when it starts showing.
func _init(run_outcome: LobbyState.Outcome, start_tick: int) -> void:
	outcome = run_outcome
	_ends_at_tick = start_tick + duration_ticks


func fill_state(out: LobbyState) -> void:
	out.outcome = outcome


## Whether the outcome has shown for [member duration_ticks]. A frozen
## world's tick still counts.
func is_over(_outcome: LobbyState.Outcome, tick: int) -> bool:
	return tick >= _ends_at_tick
