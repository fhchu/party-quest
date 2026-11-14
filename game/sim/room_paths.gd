extends RefCounted
## A grid over one room's floor for walking around what's in the way. The
## floor is the grid's whole region, so walls never need marking.

var _grid := AStarGrid2D.new()


## [param floor] must be a whole number of [param cell_size] cells each way.
func _init(floor: Rect2, cell_size: float) -> void:
	var cell := Vector2.ONE * cell_size
	_grid.region = Rect2i(Vector2i.ZERO, Vector2i(floor.size / cell_size))
	_grid.cell_size = cell
	# So each point is a cell's center.
	_grid.offset = floor.position + cell / 2
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()


## The next point on the way from [param from] to [param to] that keeps
## clear of every circle in [param blockers], or [param to] itself if no
## way exists. The cells of [param from] and [param to] always count as
## open.
func next_point(from: Vector2, to: Vector2, blockers: Array[Blocker]) -> Vector2:
	var start := _cell_of(from)
	var goal := _cell_of(to)
	var marked: Array[Vector2i] = []
	for blocker in blockers:
		marked.append_array(_cells_inside(blocker))
	for cell in marked:
		_grid.set_point_solid(cell, cell != start and cell != goal)
	var path := _grid.get_point_path(start, goal)
	for cell in marked:
		_grid.set_point_solid(cell, false)
	return path[1] if path.size() > 1 else to


## The cell holding [param pos], clamped to the floor.
func _cell_of(pos: Vector2) -> Vector2i:
	var cell := Vector2i(((pos - _grid.offset) / _grid.cell_size).round())
	return cell.clamp(_grid.region.position, _grid.region.end - Vector2i.ONE)


## Every cell whose center is inside [param blocker].
func _cells_inside(blocker: Blocker) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var reach := Vector2.ONE * blocker.radius
	var low := _cell_of(blocker.center - reach)
	var high := _cell_of(blocker.center + reach)
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			var cell := Vector2i(x, y)
			if _grid.get_point_position(cell).distance_to(blocker.center) < blocker.radius:
				out.append(cell)
	return out


## A circle no path may enter.
class Blocker:
	var center: Vector2
	## In px.
	var radius: float
