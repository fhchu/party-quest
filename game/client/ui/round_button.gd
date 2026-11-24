extends BaseButton
## A button pressed only inside the circle that fits its rectangle, not in
## the corners around it. It draws nothing: its children do.


func _has_point(point: Vector2) -> bool:
	return point.distance_to(size / 2.0) <= minf(size.x, size.y) / 2.0
