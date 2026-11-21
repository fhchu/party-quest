@tool
extends Resource
## How a floor's density levels spread over it: smooth noise gives each cell
## a density from 0 to 1, and thresholds turn density into a level. One per
## kind of floor; grass_noise.tres is the grass floor's. Emits changed when
## any of it changes, noise settings included, so tools/noise_tuner/ redraws.

## The patches' shape. Sampled once per floor cell, so its frequency is per
## cell: 0.125 makes patches about 8 cells across. Its seed is ignored; each
## room's graphics seed replaces it.
@export var noise: FastNoiseLite:
	set(value):
		if noise:
			noise.changed.disconnect(emit_changed)
		noise = value
		if noise:
			noise.changed.connect(emit_changed)
		emit_changed()
## The least density each level from 1 up needs, sparsest first; level 0
## needs none. The floor's tile set (client/assets/textures/grass.tres for grass)
## must have a tile at every level these give.
@export var level_thresholds: Array[float] = []:
	set(value):
		level_thresholds = value
		emit_changed()
## How far either side of a threshold the chance of reaching that level
## blends from none to certain, so a patch's edge thins out instead of
## following the grid. 0 is a hard edge.
@export_range(0.0, 0.5, 0.01) var edge_softness := 0.0:
	set(value):
		edge_softness = value
		emit_changed()
## Whether about half the cells, at random, are drawn mirrored left to right.
@export var mirrored := false:
	set(value):
		mirrored = value
		emit_changed()
