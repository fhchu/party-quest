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
## After a charge, how long the dummy walks at [member cooldown_walk_speed]
## instead of its own speed. It still turns, and can attack. Untuned.
@export var cooldown_sec := 0.5
## In px/s.
@export var cooldown_walk_speed := 24.0
