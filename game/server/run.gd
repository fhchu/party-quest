extends "res://server/lobby_phase.gd"
## Plays until one of its run conditions is met. Wins are checked before
## losses, so a kill on the timer's last tick still wins.

const DataLoader := preload("res://shared/data_loader.gd")
const RunConditions := preload("res://sim/run_conditions/run_conditions.gd")
const RunCondition := preload("res://sim/run_conditions/run_condition.gd")
const TimeUp := preload("res://sim/run_conditions/time_up.gd")

## The timer clients see: its first time_up condition. Null for none.
var timer: TimeUp
## NONE until the run ends.
var outcome := LobbyState.Outcome.NONE

var _win: Array[RunCondition]
var _lose: Array[RunCondition]


func _init(setup: DataLoader.RunSetup) -> void:
	_win = RunConditions.from_entries(setup.win)
	_lose = RunConditions.from_entries(setup.lose)
	for condition in _win + _lose:
		if condition is TimeUp:
			timer = condition
			break


## Returns whether the run ended this tick, with its [member outcome].
func step(world: World) -> bool:
	for condition in _win:
		if condition.step(world):
			outcome = LobbyState.Outcome.WON
			return true
	for condition in _lose:
		if condition.step(world):
			outcome = LobbyState.Outcome.LOST
			return true
	return false


func fill_snapshot(snap: Snapshot) -> void:
	snap.run_ticks_left = timer.ticks_left if timer else Snapshot.NO_TIMER
