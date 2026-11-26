extends "res://tests/sim/world_fixture.gd"
## Where the party starts: a square from the first room's spawn, kept on
## the floor, and the same square through a door.

const DataRecords := preload("res://tests/data_records.gd")
const RoomPlan := preload("res://sim/room_plan.gd")


## A world starting in [param start], an empty room unless given, with its
## spawn at [param spawn] and players 1 to [param count], and a door north
## into [param north] if given.
func _world_spawning_at(spawn: Vector2, count: int, start := RoomPlan.new(),
		north: RoomPlan = null) -> WorldState:
	start.spawn = spawn
	var run := DataRecords.run(start)
	if north:
		WorldLoader.join(run, start, Direction.Cardinal.NORTH, north)
	var w := WorldSimulator.start(run)
	for id in range(1, count + 1):
		WorldSimulator.add_player(w, id)
	WorldSimulator.place_party(w)
	return w


func test_the_party_forms_a_square_from_the_spawn_in_seat_order() -> void:
	var spawn := WorldState.data.arena.get_center()
	var w := _world_spawning_at(spawn, 4)
	var size := PLAYER_SIZE
	assert_vector(w.players[1].pos).is_equal(spawn)
	assert_vector(w.players[2].pos).is_equal(spawn + Vector2(size.x, 0))
	assert_vector(w.players[3].pos).is_equal(spawn + Vector2(0, size.y))
	assert_vector(w.players[4].pos).is_equal(spawn + size)


func test_a_square_by_a_wall_shifts_onto_the_floor_and_keeps_its_shape() -> void:
	var floor_area := RoomShape.floor_area()
	var w := _world_spawning_at(floor_area.end, 4)
	assert_bool(floor_area.encloses(_hurtbox(w.players[1]))).is_true()
	assert_bool(floor_area.encloses(_hurtbox(w.players[2]))).is_true()
	assert_bool(floor_area.encloses(_hurtbox(w.players[3]))).is_true()
	assert_bool(floor_area.encloses(_hurtbox(w.players[4]))).is_true()
	assert_vector(w.players[4].pos - w.players[1].pos).is_equal(PLAYER_SIZE)


func test_the_party_faces_the_spawn_rooms_way() -> void:
	var start := RoomPlan.new()
	start.spawn_facing = Direction.Cardinal.WEST
	var w := _world_spawning_at(WorldState.data.arena.get_center(), 2, start)
	WorldSimulator.add_player(w, 3)
	assert_int(w.players[1].facing).is_equal(Direction.Cardinal.WEST)
	assert_int(w.players[2].facing).is_equal(Direction.Cardinal.WEST)
	assert_int(w.players[3].facing).is_equal(Direction.Cardinal.WEST)


func test_a_joiner_fills_its_spot_without_moving_the_others() -> void:
	var w := _world_spawning_at(WorldState.data.arena.get_center(), 2)
	var first := w.players[1].pos
	WorldSimulator.add_player(w, 3)
	assert_vector(w.players[1].pos).is_equal(first)
	assert_vector(w.players[3].pos).is_equal(first + Vector2(0, PLAYER_SIZE.y))


func test_through_a_door_the_party_arrives_in_its_square_centered_across_it() -> void:
	var center := WorldState.data.arena.get_center()
	var w := _world_spawning_at(center, 4, RoomPlan.new(), RoomPlan.new())
	w.players[1].pos = RoomShape.door(Direction.Cardinal.NORTH).get_center()
	WorldSimulator.step(w)
	var arrival := RoomShape.door(Direction.Cardinal.SOUTH)
	assert_vector(w.players[4].pos - w.players[1].pos).is_equal(PLAYER_SIZE)
	# Players 1 and 4 are at opposite corners of the square.
	var middle := (w.players[1].pos + w.players[4].pos) / 2
	assert_float(middle.x).is_equal_approx(arrival.get_center().x, 0.001)
	assert_int(w.players[1].facing).is_equal(Direction.Cardinal.NORTH)
	assert_int(w.players[2].facing).is_equal(Direction.Cardinal.NORTH)
	assert_int(w.players[3].facing).is_equal(Direction.Cardinal.NORTH)
	assert_int(w.players[4].facing).is_equal(Direction.Cardinal.NORTH)


func _hurtbox(p: Player) -> Rect2:
	return Rect2(p.pos - PLAYER_SIZE / 2, PLAYER_SIZE)
