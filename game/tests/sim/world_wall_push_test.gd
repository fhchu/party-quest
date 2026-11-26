extends "res://tests/sim/world_fixture.gd"
## A push into a wall slides along it for the push's whole length.

const PUSH_PX := 24.0
const PUSH_TICKS := 6


## Against the floor's right edge, halfway down.
func _at_right_wall() -> Vector2:
	return Vector2(
			RoomShape.floor_area().end.x - PLAYER_SIZE.x / 2, WorldState.data.arena.get_center().y)


## Against the floor's bottom edge, halfway across.
func _at_bottom_wall(size: Vector2) -> Vector2:
	return Vector2(WorldState.data.arena.get_center().x, RoomShape.floor_area().end.y - size.y / 2)


func test_a_push_into_a_wall_at_an_angle_slides_its_whole_length() -> void:
	var start := _at_right_wall()
	_player().pos = start
	_player().push(Vector2(1, 1).normalized() * PUSH_PX, PUSH_TICKS)
	_advance(PUSH_TICKS + 1)
	assert_vector(_player().pos).is_equal_approx(start + Vector2(0, PUSH_PX), Vector2.ONE * 0.001)


func test_a_push_straight_into_a_wall_slides_counterclockwise_around_the_room() -> void:
	var start := _at_bottom_wall(PLAYER_SIZE)
	_player().pos = start
	_player().push(Vector2.DOWN * PUSH_PX, PUSH_TICKS)
	_advance(PUSH_TICKS + 1)
	assert_vector(_player().pos).is_equal_approx(start + Vector2(PUSH_PX, 0), Vector2.ONE * 0.001)


func test_walking_into_a_wall_doesnt_slide() -> void:
	var start := _at_bottom_wall(PLAYER_SIZE)
	_player().pos = start
	_steer(Vector2.DOWN)
	_advance(PUSH_TICKS)
	assert_vector(_player().pos).is_equal_approx(start, Vector2.ONE * 0.001)


func test_a_dummy_pushed_into_a_wall_slides_too() -> void:
	var d := _add_dummy(_at_bottom_wall(DUMMY_SIZE), DummyKinds.turret_kind)
	var start := d.pos
	d.push(Vector2.DOWN * PUSH_PX, PUSH_TICKS)
	_advance(PUSH_TICKS + 1)
	assert_vector(d.pos).is_equal_approx(start + Vector2(PUSH_PX, 0), Vector2.ONE * 0.001)
