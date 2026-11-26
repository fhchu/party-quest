extends Resource
## A way between two rooms, always both ways: [member from]'s [member side]
## wall leads to [member to]'s opposite wall. With
## [member opens_level_select], a way out of [member from] that leads to no
## room.

const Room := preload("res://shared/data/room.gd")

@export var from: Room
@export var side := Direction.Cardinal.NORTH
## Empty when [member opens_level_select] is set.
@export var to: Room
## Going through it opens the level select instead of moving the party.
@export var opens_level_select := false
