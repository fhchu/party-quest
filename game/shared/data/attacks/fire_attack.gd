extends "res://shared/data/attacks/attack.gd"
## A shot toward where the target was when the aim locked, in px and
## seconds.
##
## Every value is PLACEHOLDER (design).

const Push := preload("res://shared/data/push.gd")

## In px.
@export var projectile_radius := 6.0
## In px/s.
@export var projectile_speed := 128.0
## Health a player loses to one shot.
@export var projectile_damage := 1
## How fast a shot pushes the player it hits, in px/s, and for how long.
@export var push_speed := Push.DEFAULT_SPEED
@export var push_sec := Push.DEFAULT_SEC
