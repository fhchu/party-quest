extends RefCounted
## The push a hit gives unless its own data sets another: how fast it moves
## what it hits, and for how long. A swing always pushes this way.

## In px/s.
const DEFAULT_SPEED := 240.0
const DEFAULT_SEC := 1 / 6.0


## The distance a push of [param speed] px/s for [param sec] covers, in px.
static func px(speed: float, sec: float) -> float:
	return speed * sec
