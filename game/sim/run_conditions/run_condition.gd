@abstract
extends RefCounted
## Something that ends a run once it's met. Whether that's a win or a loss
## depends on which of the run's lists holds it.

const World := preload("res://sim/world.gd")


## One tick, after the world's. Returns whether it's met.
@abstract func step(world: World) -> bool
