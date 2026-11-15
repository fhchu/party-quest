extends RefCounted
## A dummy's shot, from its kind's fire attack with durations in ticks
## (see [method WorldLoader.new_dummy]). The world fires it toward the
## dummy's locked aim.

## From its aim lock to the shot.
var aim_lock_ticks := 0
## In px.
var radius := 0.0
## How far the shot moves each tick, in px.
var step := 0.0
## Health a player loses to the shot.
var damage := 0
## How far the shot pushes the player it hits, in px, and over how long.
var push_px := 0.0
var push_ticks := 0
