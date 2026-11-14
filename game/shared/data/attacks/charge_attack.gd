extends "res://shared/data/attacks/attack.gd"
## A straight run at the target, through every player in the way, in px
## and seconds. It hurts and pushes like touching the dummy.
##
## Every value is PLACEHOLDER (design).

## In px/s.
@export var speed := 160.0
## How far one charge moves the dummy, in px. It charges only at a target
## whose edge is this close to its own, along the line between them.
@export var length := 96.0
