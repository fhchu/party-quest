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
