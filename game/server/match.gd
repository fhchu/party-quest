extends "res://server/lobby_phase.gd"
## The timer runs. Killing every enemy wins; everyone downed, or running
## out of time, loses.

const Result := preload("res://server/result.gd")
const Tuning := preload("res://sim/tuning.gd")

var ticks_left := Tuning.match_ticks


func fill_state(out: LobbyState) -> void:
	out.phase = LobbyState.Phase.MATCH


## A fresh world puts everyone at their spawn spot with full health.
func enter(lobby: Lobby, _now_msec: int) -> void:
	lobby.replace_world(World.Layout.MATCH)


func step(lobby: Lobby, now_msec: int) -> void:
	ticks_left -= 1
	# Checked before the timer, so a kill on the last tick still wins.
	if lobby.world.enemies_left() == 0:
		end_match(lobby, LobbyState.Outcome.WON, now_msec)
	elif lobby.world.players_alive() == 0 or ticks_left <= 0:
		end_match(lobby, LobbyState.Outcome.LOST, now_msec)


func fill_snapshot(snap: Snapshot) -> void:
	snap.match_ticks_left = ticks_left


func end_match(lobby: Lobby, outcome: LobbyState.Outcome, now_msec: int) -> void:
	lobby.change_phase(Result.new(outcome), now_msec)
