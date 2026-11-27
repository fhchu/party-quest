extends "res://tests/sim/world_fixture.gd"
## A unit that walks to line up with its target: diagonally until it's level
## with it, across or up and down, then along that line.


const WALK_STEP := 4.0


## An aligning walker [param offset] from the player that doesn't attack
## within the test.
func _add_aligner(offset: Vector2) -> Unit:
	var d := _add_unit(_player().pos + offset, Units.turret_type)
	_arm(d, Fire.new())
	d.attack_interval_ticks = A_WHILE * 2
	d.attack_ticks_left = A_WHILE * 2
	d.walk_step = WALK_STEP
	d.walk_style = Unit.WalkStyle.ALIGN
	return d


func test_off_both_lines_it_walks_diagonally() -> void:
	var d := _add_aligner(Vector2(-100, -40))
	WorldSimulator.step(world)
	assert_vector(d.move).is_equal_approx(Vector2(1, 1).normalized(), Vector2.ONE * 0.001)


func test_within_a_step_of_a_line_it_steps_onto_it() -> void:
	var d := _add_aligner(Vector2(-100, -3))
	WorldSimulator.step(world)
	# 3 of WALK_STEP 4 px down onto the row, 0.75; the rest ahead,
	# sqrt(4² - 3²) / 4.
	assert_vector(d.move).is_equal_approx(Vector2(0.6614, 0.75), Vector2.ONE * 0.001)


func test_it_lines_up_along_the_axis_its_target_is_farther_along() -> void:
	var d := _add_aligner(Vector2(-30, -100))
	_advance(12)
	# 30 px across: 10 diagonal steps of 4 / sqrt(2) leave 1.7 px, which
	# the 11th steps onto. A walk moves it the tick after it's chosen.
	assert_float(d.pos.x).is_equal_approx(_player().pos.x, 0.001)
	assert_float(d.pos.y).is_less(_player().pos.y)
