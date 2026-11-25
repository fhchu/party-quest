extends RefCounted
## One client's input, as input_codec.gd packs it.

## Where the move keys or the joystick point, each axis -1 to 1.
var move := Vector2.ZERO
## One per input action (Protocol.INPUT_ACTIONS and the unused ones after
## them): its presses since the welcome, wrapping at
## Protocol.PRESS_COUNTER_MODULUS.
var press_counters := PackedByteArray()
## Bit i is set while input action i is held.
var held_bits := 0
