extends "res://shared/data/attacks/attack.gd"
## A shot toward where the target was when the aim locked, in px and
## seconds.
##
## Every value is PLACEHOLDER (design).

## In px.
@export var projectile_radius := 4.0
## In px/s.
@export var projectile_speed := 64.0
## Health a player loses to one shot.
@export var projectile_damage := 1
## How far a shot pushes the player it hits, in px, and over how long; 0
## moves the player at once.
@export var push_px := 24.0
@export var push_sec := 0.1
