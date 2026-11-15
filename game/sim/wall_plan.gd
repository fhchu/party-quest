extends RefCounted
## One of a room's four walls, as WorldLoader works it out from
## shared/room_shape.gd. Every room has the same four.

## Into the room, square to the wall.
var inward := Vector2.ZERO
## Where its door is, when the room has one in this wall, in px.
var gap := Rect2()
## The wall either side of an open door's gap, in px.
var pieces_beside_gap: Array[Rect2] = []
## Its bit in a snapshot's door bits.
var door_bit := 0
