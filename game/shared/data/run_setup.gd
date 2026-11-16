extends Resource
## A run: the room it starts in, the passages between its rooms, and what
## ends it. Wins are checked before losses.

const Room := preload("res://shared/data/room.gd")
const Passage := preload("res://shared/data/passage.gd")
const Condition := preload("res://shared/data/condition.gd")

@export var start: Room
@export var passages: Array[Passage] = []
@export var win: Array[Condition] = []
@export var lose: Array[Condition] = []
## Gold each player earns when the run is won. Nothing is earned on a loss.
@export var win_gold := 0
## Seeds the run's random choices, so a run can be played again; -1 for a
## new random seed each run.
@export var rng_seed := -1
