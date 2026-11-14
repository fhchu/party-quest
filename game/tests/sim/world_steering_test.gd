extends "res://tests/sim/world_fixture.gd"
## Walking dummies keep their distance: each steers away from any other
## inside its personal space, edge to edge.

const Dummy := preload("res://sim/dummy.gd")

const RADIUS := 8.0
const PERSONAL_SPACE := 8.0
const WALK_STEP := 1.0


## A walking circle [param offset] from the player that doesn't attack
## within the test.
func _add_walker(offset: Vector2) -> World.Dummy:
	var d := _add_dummy(_player().pos + offset, DummyKinds.charger_kind)
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	d.collider = circle
	d.attack_interval_ticks = A_WHILE * 2
	d.attack_ticks_left = A_WHILE * 2
	d.walk_step = WALK_STEP
	d.personal_space = PERSONAL_SPACE
	return d


func test_it_heads_straight_for_its_target_when_nobody_is_close() -> void:
	var d := _add_walker(Vector2(0, -100))
	_add_walker(Vector2(2 * RADIUS + PERSONAL_SPACE + 1, -100))
	world.step()
	assert_vector(d.move).is_equal_approx(Vector2.DOWN, Vector2.ONE * TOLERANCE)


func test_it_steers_away_from_a_dummy_inside_its_personal_space() -> void:
	var d := _add_walker(Vector2(0, -100))
	_add_walker(Vector2(2 * RADIUS + PERSONAL_SPACE / 2, -100))
	world.step()
	assert_float(d.move.x).is_less(0.0)
	assert_float(d.move.y).is_greater(0.0)


func test_the_closer_the_other_the_harder_it_steers() -> void:
	var near := _add_walker(Vector2(0, -100))
	_add_walker(Vector2(2 * RADIUS + PERSONAL_SPACE / 4, -100))
	var far := _add_walker(Vector2(0, -200))
	_add_walker(Vector2(2 * RADIUS + PERSONAL_SPACE * 3 / 4, -200))
	world.step()
	assert_float(absf(near.move.x)).is_greater(absf(far.move.x))


func test_two_on_top_of_each_other_go_opposite_ways() -> void:
	var one := _add_walker(Vector2(0, -100))
	var two := _add_walker(Vector2(0, -100))
	world.step()
	assert_float(one.move.x * two.move.x).is_less(0.0)


func test_a_dummy_that_doesnt_walk_isnt_moved_by_crowding() -> void:
	var still := _add_walker(Vector2(0, -100))
	still.walk_step = 0.0
	_add_walker(Vector2(RADIUS, -100))
	var pos := still.pos
	_advance(10)
	assert_vector(still.pos).is_equal(pos)


func test_a_charge_goes_straight_through_a_dummy_in_its_way() -> void:
	var charger := _add_walker(Vector2(0, -100))
	charger.attack_choice = World.DummyKind.AttackChoice.CHARGE
	charger.charge_step = 4.0
	charger.charge_length = 200.0
	charger.attack_ticks_left = 0
	charger.walk_step = 0.0
	_add_walker(Vector2(RADIUS, -60)).walk_step = 0.0
	for i in A_WHILE:
		world.step()
		if charger.state == Dummy.State.CHARGING:
			break
	var x := charger.pos.x
	_advance(10)
	assert_float(charger.pos.x).is_equal_approx(x, TOLERANCE)


func test_a_box_reaches_out_to_its_corners() -> void:
	var box := _add_dummy(_player().pos)
	var half := DUMMY_SIZE / 2
	assert_float(box.footprint_radius()).is_equal_approx(half.length(), TOLERANCE)
