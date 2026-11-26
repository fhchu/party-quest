extends Resource
## The dungeon's levels, in the order the level select shows them. A
## level's number is its place here, from 0.

const RunSetup := preload("res://shared/data/run_setup.gd")

@export var runs: Array[RunSetup] = []
