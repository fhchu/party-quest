extends "res://shared/data/attacks/attack.gd"
## A straight run at the target, through every player in the way, in px
## and seconds. It hurts and pushes like touching the dummy.
##
## Every value is PLACEHOLDER (design).

## In px/s.
@export var speed := 320.0
## How far one charge moves the dummy, in px. It charges only at a target
## whose edge is this close to its own, along the line between them.
@export var length := 160.0
## How long it slows before the charge ends: steadily, from [member speed]
## to [member brake_end_speed], over the last of its length.
@export var brake_sec := 0.4
## In px/s.
@export var brake_end_speed := 0.0
## After a charge, how long the dummy takes to speed up steadily from
## [member cooldown_walk_speed] back to its own walk speed. It still turns,
## and can attack.
@export var cooldown_sec := 0.4
## Its walk speed as the cooldown starts, in px/s.
@export var cooldown_walk_speed := 24.0
