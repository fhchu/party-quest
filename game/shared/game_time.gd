extends RefCounted
## The game's unit of time, the tick, and how it relates to seconds.
##
## The server steps the simulation once a tick, and every time a snapshot
## carries is in ticks. Balance values are in seconds, so changing the tick
## rate changes no tuning.

## Simulation steps per second, on the server and in each client's input
## loop. The server sends a snapshot every step.
const TICK_RATE := 30
## How long one tick lasts.
const TICK_SEC := 1.0 / TICK_RATE


## Seconds to whole ticks, rounded; never 0 for a positive time.
static func ticks(sec: float) -> int:
	return maxi(roundi(sec * TICK_RATE), 1 if sec > 0.0 else 0)


static func seconds(tick_count: float) -> float:
	return tick_count / TICK_RATE
