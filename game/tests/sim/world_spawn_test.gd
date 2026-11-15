extends "res://tests/sim/world_fixture.gd"
## Where the party starts: a square from the first room's spawn, kept on
## the floor, and the same square through a door.

const Room := preload("res://shared/data/room.gd")
const Passage := preload("res://shared/data/passage.gd")
const RoomGraph := preload("res://sim/room_graph.gd")


## A world starting in [param start], an empty room unless given, with its
## spawn at [param spawn] and players 1 to [param count].
func _world_spawning_at(spawn: Vector2, count: int, start := Room.new(),
		graph: RoomGraph = null) -> World:
	start.spawn = spawn
	var w := World.new(start, null, graph)
	for id in range(1, count + 1):
		w.add_player(id)
	w.place_party()
	return w


func test_the_party_forms_a_square_from_the_spawn_in_seat_order() -> void:
	var spawn := World.arena.get_center()
	var w := _world_spawning_at(spawn, 4)
	var size := PLAYER_SIZE
	assert_vector(w.players[1].pos).is_equal(spawn)
	assert_vector(w.players[2].pos).is_equal(spawn + Vector2(size.x, 0))
	assert_vector(w.players[3].pos).is_equal(spawn + Vector2(0, size.y))
	assert_vector(w.players[4].pos).is_equal(spawn + size)


func test_a_square_by_a_wall_shifts_onto_the_floor_and_keeps_its_shape() -> void:
	var corner := RoomShape.floor_area().end
	var w := _world_spawning_at(corner, 4)
	for p: World.Player in w.players.values():
		var hurtbox := Rect2(p.pos - PLAYER_SIZE / 2, PLAYER_SIZE)
		assert_bool(RoomShape.floor_area().encloses(hurtbox)).is_true()
	assert_vector(w.players[4].pos - w.players[1].pos).is_equal(PLAYER_SIZE)


func test_a_joiner_takes_its_spot_without_moving_the_others() -> void:
	var w := _world_spawning_at(World.arena.get_center(), 2)
	var first := w.players[1].pos
	w.add_player(3)
	assert_vector(w.players[1].pos).is_equal(first)
	assert_vector(w.players[3].pos).is_equal(first + Vector2(0, PLAYER_SIZE.y))


func test_through_a_door_the_party_arrives_in_its_square_centered_across_it() -> void:
	var south := Room.new()
	var north := Room.new()
	var passage := Passage.new()
	passage.from = south
	passage.side = RoomShape.Side.NORTH
	passage.to = north
	var passages: Array[Passage] = [passage]
	var w := _world_spawning_at(World.arena.get_center(), 4, south, RoomGraph.new(passages))
	w.players[1].pos = RoomShape.door(RoomShape.Side.NORTH).get_center()
	w.step()
	var arrival := RoomShape.door(RoomShape.Side.SOUTH)
	assert_vector(w.players[4].pos - w.players[1].pos).is_equal(PLAYER_SIZE)
	var middle := (w.players[1].pos + w.players[4].pos) / 2
	assert_float(middle.x).is_equal_approx(arrival.get_center().x, TOLERANCE)
	for p: World.Player in w.players.values():
		assert_bool(RoomShape.floor_area().has_point(p.pos)).is_true()
		assert_bool(arrival.grow(PLAYER_SIZE.x / 2).has_point(p.pos)).is_false()
