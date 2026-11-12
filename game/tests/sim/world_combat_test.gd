extends "res://tests/sim/world_fixture.gd"
## Combat: health, swing damage, contact damage,
## invulnerability, pushes, and what swings touch.

const Snapshot := preload("res://net/snapshot.gd")

## Any name: the world passes it on without reading it.
const ON_HIT := "any_effect"


func test_a_new_player_has_full_health() -> void:
	assert_int(_player().health).is_equal(World.player_max_health)


func test_swing_contacts_list_who_touched_what() -> void:
	_add_dummy_in_reach().on_hit = ON_HIT
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_int(world.swing_contacts.size()).is_equal(1)
	assert_int(world.swing_contacts[0].attacker_id).is_equal(PLAYER_ID)
	assert_str(world.swing_contacts[0].on_hit).is_equal(ON_HIT)
	world.step()
	assert_array(world.swing_contacts).is_empty()


func test_each_swing_deals_its_damage_to_an_enemy() -> void:
	var enemy := _add_dummy_in_reach(DummyKinds.enemy_kind)
	_swing()
	assert_int(enemy.health).is_equal(ENEMY_HEALTH - World.swing_damage)


func test_swings_never_damage_a_dummy_that_isnt_damageable() -> void:
	var d := _add_dummy_in_reach(DummyKinds.ready_kind)
	_swing()
	assert_int(d.health).is_zero()
	assert_array(world.dummies).contains([d])


func test_an_enemy_out_of_health_is_removed() -> void:
	_add_dummy_in_reach(DummyKinds.enemy_kind)
	for i in ceili(float(ENEMY_HEALTH) / World.swing_damage):
		# Knockback moves it; put it back in reach.
		world.dummies[0].pos = _player().pos + Vector2(World.swing_radius / 2, 0)
		_swing()
	assert_array(world.dummies).is_empty()


func test_touching_an_enemy_hurts_the_player_and_makes_them_invulnerable() -> void:
	_add_dummy(_player().pos, DummyKinds.enemy_kind)
	world.step()
	assert_int(_player().health).is_equal(World.player_max_health - ENEMY_CONTACT_DAMAGE)
	assert_bool(world.snapshot().players[0].invulnerable).is_true()
	_advance(Player.hurt_invulnerable_ticks)
	assert_bool(world.snapshot().players[0].invulnerable).is_false()


func test_no_damage_hurts_an_invulnerable_player() -> void:
	# Unpushed, so the player stays in contact with both.
	for i in 2:
		_add_dummy(_player().pos, DummyKinds.enemy_kind).contact_push_px = 0.0
	world.step()
	assert_int(_player().health).is_equal(World.player_max_health - ENEMY_CONTACT_DAMAGE)
	_advance(Player.hurt_invulnerable_ticks - 1)
	assert_int(_player().health).is_equal(World.player_max_health - ENEMY_CONTACT_DAMAGE)
	world.step()
	assert_int(_player().health).is_equal(World.player_max_health - 2 * ENEMY_CONTACT_DAMAGE)


func test_health_stops_at_zero() -> void:
	# Unpushed, so the player stays in contact.
	_add_dummy(_player().pos, DummyKinds.enemy_kind).contact_push_px = 0.0
	_advance(Player.hurt_invulnerable_ticks * (World.player_max_health + 2))
	assert_int(_player().health).is_equal(0)


func test_a_dummy_without_contact_damage_never_hurts() -> void:
	_add_dummy(_player().pos, DummyKinds.ready_kind)
	_add_dummy(_player().pos, DummyKinds.start_kind)
	_advance(A_WHILE)
	assert_int(_player().health).is_equal(World.player_max_health)


func test_touching_an_enemy_pushes_the_player_away() -> void:
	var enemy := _add_dummy(_player().pos + Vector2(DUMMY_SIZE.x / 2, 0), DummyKinds.enemy_kind)
	var start := _player().pos
	_advance(ENEMY_CONTACT_PUSH_TICKS + 1)
	assert_vector(_player().pos).is_equal_approx(
			start + Vector2.LEFT * ENEMY_CONTACT_PUSH_PX, Vector2.ONE * KNOCKBACK_TOLERANCE)
	assert_vector(enemy.pos).is_equal(start + Vector2(DUMMY_SIZE.x / 2, 0))


func test_a_pushed_player_doesnt_steer() -> void:
	_add_dummy(_player().pos + Vector2(DUMMY_SIZE.x / 2, 0), DummyKinds.enemy_kind)
	world.set_input(PLAYER_ID, Vector2.RIGHT, 0)
	var start := _player().pos
	_advance(ENEMY_CONTACT_PUSH_TICKS + 1)
	assert_float(_player().pos.x).is_less(start.x)


func test_a_push_cancels_the_swing() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_int(_player().state).is_equal(World.Player.State.SWINGING)
	_add_dummy(_player().pos, DummyKinds.enemy_kind)
	world.step()
	assert_int(_player().state).is_equal(World.Player.State.IDLE)


func test_no_swing_starts_while_pushed() -> void:
	_add_dummy(_player().pos, DummyKinds.enemy_kind)
	world.step()
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	assert_int(_player().state).is_equal(World.Player.State.IDLE)


func test_a_dummy_not_pushed_by_swings_stays_put() -> void:
	for kind in [DummyKinds.ready_kind, DummyKinds.start_kind]:
		world.dummies.clear()
		var d := _add_dummy_in_reach(kind)
		var where := d.pos
		_swing()
		assert_vector(d.pos).is_equal(where)


func test_presses_while_frozen_never_swing() -> void:
	world.frozen = true
	world.set_input(PLAYER_ID, Vector2.ZERO, 3)
	world.step()
	world.frozen = false
	world.set_input(PLAYER_ID, Vector2.ZERO, 3)
	world.step()
	assert_int(_player().state).is_equal(World.Player.State.IDLE)
	world.set_input(PLAYER_ID, Vector2.ZERO, 4)
	world.step()
	assert_int(_player().state).is_equal(World.Player.State.SWINGING)

func test_a_dummy_never_struck_reads_as_long_ago() -> void:
	_add_dummy(_player().pos + Vector2(World.swing_radius * 4, 0))
	assert_int(world.snapshot().dummies[0].ticks_since_struck).is_equal(Snapshot.STRUCK_LONG_AGO)


func test_the_struck_age_counts_up_and_stops_at_long_ago() -> void:
	_add_dummy(_player().pos + Vector2(World.swing_radius / 2, 0))
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	_advance(3)
	assert_int(world.snapshot().dummies[0].ticks_since_struck).is_equal(3)
	_advance(Snapshot.STRUCK_LONG_AGO)
	assert_int(world.snapshot().dummies[0].ticks_since_struck).is_equal(Snapshot.STRUCK_LONG_AGO)
