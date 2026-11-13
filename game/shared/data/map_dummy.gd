extends Resource
## One dummy a map places.

const DummyKind := preload("res://shared/data/dummy_kind.gd")

@export var kind: DummyKind
## From the arena's center, in px.
@export var offset := Vector2.ZERO
## What a swing touching it asks the lobby to do; empty for nothing.
@export var on_hit := ""
