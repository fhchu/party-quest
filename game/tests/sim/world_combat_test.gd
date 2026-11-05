extends "res://tests/sim/world_fixture.gd"
## The M1 combat stand-in: health, swing damage, contact damage and what
## swings hit.


func test_a_new_player_has_full_health() -> void:
	assert_int(_player().health).is_equal(Tuning.player_max_health)


func test_swings_are_listed_by_who_hit_what() -> void:
	_in_reach(World.Kind.READY)
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_int(world.hits.size()).is_equal(1)
	assert_int(world.hits[0].player_id).is_equal(PLAYER_ID)
	assert_int(world.hits[0].kind).is_equal(World.Kind.READY)
	world.step()
	assert_array(world.hits).is_empty()


func test_each_swing_takes_its_damage_from_an_enemy() -> void:
	var enemy := _in_reach(World.Kind.ENEMY)
	_swing()
	assert_int(enemy.health).is_equal(Tuning.enemy_health - Tuning.swing_damage)


func test_an_enemy_out_of_health_is_removed() -> void:
	_in_reach(World.Kind.ENEMY)
	for i in ceili(float(Tuning.enemy_health) / Tuning.swing_damage):
		# Knockback moves it; put it back in reach.
		world.dummies[0].pos = _player().pos + Vector2(Tuning.swing_radius / 2, 0)
		_swing()
	assert_int(world.enemies_left()).is_equal(0)
	assert_array(world.dummies).is_empty()


func test_touching_an_enemy_hurts_and_flashes_the_player() -> void:
	_add_dummy(_player().pos, World.Kind.ENEMY)
	world.step()
	assert_int(_player().health).is_equal(Tuning.player_max_health - Tuning.contact_damage)
	assert_bool(world.snapshot().players[0].hit).is_true()
	_steps(Tuning.hit_flash_ticks)
	assert_bool(world.snapshot().players[0].hit).is_false()


func test_touching_damage_waits_before_repeating() -> void:
	# Unpushed, so the player stays in contact.
	Tuning.contact_knockback_px = 0.0
	_add_dummy(_player().pos, World.Kind.ENEMY)
	world.step()
	_steps(Tuning.contact_repeat_ticks - 1)
	assert_int(_player().health).is_equal(Tuning.player_max_health - Tuning.contact_damage)
	world.step()
	assert_int(_player().health).is_equal(Tuning.player_max_health - 2 * Tuning.contact_damage)


func test_health_stops_at_zero() -> void:
	# Unpushed, so the player stays in contact.
	Tuning.contact_knockback_px = 0.0
	_add_dummy(_player().pos, World.Kind.ENEMY)
	_steps(Tuning.contact_repeat_ticks * (Tuning.player_max_health + 2))
	assert_int(_player().health).is_equal(0)


func test_lobby_dummies_never_hurt() -> void:
	_add_dummy(_player().pos, World.Kind.READY)
	_add_dummy(_player().pos, World.Kind.START)
	_steps(A_WHILE)
	assert_int(_player().health).is_equal(Tuning.player_max_health)


func test_touching_an_enemy_pushes_the_player_away() -> void:
	var enemy := _add_dummy(_player().pos + Vector2(DUMMY_SIZE.x / 2, 0), World.Kind.ENEMY)
	var start := _player().pos
	_steps(Tuning.contact_knockback_ticks + 1)
	assert_vector(_player().pos).is_equal_approx(
			start + Vector2.LEFT * Tuning.contact_knockback_px, Vector2.ONE * KNOCKBACK_TOLERANCE)
	assert_vector(enemy.pos).is_equal(start + Vector2(DUMMY_SIZE.x / 2, 0))


func test_a_pushed_player_doesnt_move_themselves() -> void:
	_add_dummy(_player().pos + Vector2(DUMMY_SIZE.x / 2, 0), World.Kind.ENEMY)
	world.set_input(PLAYER_ID, Vector2.RIGHT, 0)
	var start := _player().pos
	_steps(Tuning.contact_knockback_ticks + 1)
	assert_float(_player().pos.x).is_less(start.x)


func test_ready_and_start_stay_put_when_hit() -> void:
	for kind in [World.Kind.READY, World.Kind.START]:
		world.dummies.clear()
		var d := _in_reach(kind)
		var where := d.pos
		_swing()
		assert_vector(d.pos).is_equal(where)
