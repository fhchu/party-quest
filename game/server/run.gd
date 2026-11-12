extends "res://server/lobby_phase.gd"
## The timer runs. Killing every enemy wins; everyone downed, or running
## out of time, loses.

const GameTime := preload("res://shared/game_time.gd")
const Result := preload("res://server/result.gd")
const DataLoader := preload("res://shared/data_loader.gd")

## The run timer. The party loses when it runs out.
static var duration_ticks := GameTime.ticks(DataLoader.run_duration_sec)

var ticks_left := duration_ticks


func fill_state(out: LobbyState) -> void:
	out.phase = LobbyState.Phase.RUN


## A fresh world puts everyone at their spawn spot with full health.
func enter(lobby: Lobby, _now_msec: int) -> void:
	lobby.replace_world(World.Layout.RUN)


func step(lobby: Lobby, now_msec: int) -> void:
	ticks_left -= 1
	# Checked before the timer, so a kill on the last tick still wins.
	if lobby.world.enemies_left() == 0:
		end_run(lobby, LobbyState.Outcome.WON, now_msec)
	elif lobby.world.players_alive() == 0 or ticks_left <= 0:
		end_run(lobby, LobbyState.Outcome.LOST, now_msec)


func fill_snapshot(snap: Snapshot) -> void:
	snap.run_ticks_left = ticks_left


func end_run(lobby: Lobby, outcome: LobbyState.Outcome, now_msec: int) -> void:
	lobby.change_phase(Result.new(outcome), now_msec)
