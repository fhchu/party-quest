extends Resource
## One unit a room places.

const UnitType := preload("res://shared/data/unit_type.gd")

@export var unit_type: UnitType
## From the arena's center, in px.
@export var offset := Vector2.ZERO
## What a swing touching it asks the lobby to do; empty for nothing.
@export var on_hit := ""
