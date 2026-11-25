extends RefCounted
## One of a player's input actions, as the server last heard it.

## Presses the player hasn't acted on yet.
var unhandled_presses := 0
## Whether it was held at the last input.
var held := false
