extends "res://shared/data/item.gd"
## An item a player puts in an item slot and uses with that slot's key.

## What using it does.
enum Action {
	SWING,
	GUARD,
}

@export var action := Action.SWING
