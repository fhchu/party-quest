extends Resource
## A run: the room it starts in, the passages between its rooms, and what
## ends it. Wins are checked before losses.

const Map := preload("res://shared/data/map.gd")
const Passage := preload("res://shared/data/passage.gd")
const Condition := preload("res://shared/data/condition.gd")

@export var start: Map
@export var passages: Array[Passage] = []
@export var win: Array[Condition] = []
@export var lose: Array[Condition] = []
