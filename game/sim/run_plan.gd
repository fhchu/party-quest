extends RefCounted
## What a world plays, made by WorldLoader: the room it starts in, with
## every room's doors already joined, and what ends it.

const Goal := preload("res://sim/goal.gd")
const RoomPlan := preload("res://sim/room_plan.gd")

var start: RoomPlan
## Wins are checked before losses. With neither, it never ends.
var win: Array[Goal] = []
var lose: Array[Goal] = []
## Seeds the run's random choices; -1 for a new random seed each run.
var rng_seed := -1
