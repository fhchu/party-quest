extends "res://server/lobby_phase.gd"
## The timer runs. Killing every enemy wins; everyone downed, or running
## out of time, loses.

const GameTime := preload("res://shared/game_time.gd")
const DataLoader := preload("res://shared/data_loader.gd")

## The run timer. The party loses when it runs out.
static var duration_ticks := GameTime.ticks(DataLoader.run_duration_sec)

var ticks_left := duration_ticks
## NONE until the run ends.
var outcome := LobbyState.Outcome.NONE


## Returns whether the run ended this tick, with its [member outcome].
func step(world: World) -> bool:
	ticks_left -= 1
	# Checked before the timer, so a kill on the last tick still wins.
	if world.enemies_left() == 0:
		outcome = LobbyState.Outcome.WON
	elif world.players_alive() == 0 or ticks_left <= 0:
		outcome = LobbyState.Outcome.LOST
	return outcome != LobbyState.Outcome.NONE


func fill_snapshot(snap: Snapshot) -> void:
	snap.run_ticks_left = ticks_left
