extends "res://shared/data/attacks/attack.gd"
## A shot aimed when the aim locks, in px and seconds.

const Push := preload("res://shared/data/push.gd")

## Which ways it can go.
enum Directions {
	## Toward where the target was when the aim locked.
	ANY,
	## Up, down, left or right: whichever is nearest the target's direction
	## when the aim locks, even if the unit is pushed after. It locks only
	## when the shot would touch the target if the target stayed put.
	CARDINAL,
}

@export var directions := Directions.ANY

## In px.
@export var projectile_radius := 6.0
## In px/s.
@export var projectile_speed := 128.0
## Health a player loses to one shot.
@export var projectile_damage := 1
## How fast a shot pushes the player it hits, in px/s, and for how long.
@export var push_speed := Push.DEFAULT_SPEED
@export var push_sec := Push.DEFAULT_SEC
