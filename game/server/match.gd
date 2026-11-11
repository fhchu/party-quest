extends "res://server/room_phase.gd"
## The timer runs. Killing every enemy wins; everyone downed, or running
## out of time, loses.

const Result := preload("res://server/result.gd")
const Tuning := preload("res://sim/tuning.gd")

var ticks_left := Tuning.match_ticks


func fill_state(out: RoomState) -> void:
	out.phase = RoomState.Phase.MATCH


## A fresh world puts everyone at their spawn spot with full health.
func enter(room: Room, _now_msec: int) -> void:
	room.replace_world(World.Layout.MATCH)


func step(room: Room, now_msec: int) -> void:
	ticks_left -= 1
	# Checked before the timer, so a kill on the last tick still wins.
	if room.world.enemies_left() == 0:
		end_match(room, RoomState.Outcome.WON, now_msec)
	elif room.world.players_alive() == 0 or ticks_left <= 0:
		end_match(room, RoomState.Outcome.LOST, now_msec)


func fill_snapshot(snap: Snapshot) -> void:
	snap.match_ticks_left = ticks_left


func end_match(room: Room, outcome: RoomState.Outcome, now_msec: int) -> void:
	room.change_phase(Result.new(outcome), now_msec)
