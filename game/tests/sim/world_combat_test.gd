extends "res://tests/sim/world_fixture.gd"
## Combat: health, swing damage, contact damage,
## invulnerability, pushes, and what swings touch.

const Snapshot := preload("res://net/snapshot.gd")
const WorldSnapshot := preload("res://sim/world_snapshot.gd")

## Any name: the world passes it on without reading it.
const ON_HIT := "any_effect"


func test_swing_contacts_list_who_touched_what() -> void:
	_add_dummy_in_reach().on_hit = ON_HIT
	_press()
	WorldSimulator.step(world)
	assert_int(world.swing_contacts.size()).is_equal(1)
	assert_int(world.swing_contacts[0].attacker_id).is_equal(PLAYER_ID)
	assert_str(world.swing_contacts[0].on_hit).is_equal(ON_HIT)
	WorldSimulator.step(world)
	assert_array(world.swing_contacts).is_empty()


func test_each_swing_deals_its_damage_to_an_enemy() -> void:
	var enemy := _add_dummy_in_reach(DummyKinds.turret_kind)
	_swing()
	# ENEMY_HEALTH 3, less swing_damage 1.
	assert_int(enemy.health).is_equal(2)


func test_swings_never_damage_a_dummy_that_isnt_damageable() -> void:
	var d := _add_dummy_in_reach(DummyKinds.ready_kind)
	_swing()
	assert_int(d.health).is_zero()
	assert_array(world.dummies).contains([d])


func test_an_enemy_out_of_health_is_removed() -> void:
	# One swing_damage left.
	_add_dummy_in_reach(DummyKinds.turret_kind).health = 1
	_swing()
	assert_array(world.dummies).is_empty()


func test_touching_an_enemy_hurts_the_player_and_makes_them_invulnerable() -> void:
	_add_dummy(_player().pos, DummyKinds.turret_kind)
	WorldSimulator.step(world)
	# MAX_HEALTH 3, less ENEMY_CONTACT_DAMAGE 1.
	assert_int(_player().health).is_equal(2)
	assert_bool(WorldSnapshot.of(world).players[0].invulnerable).is_true()
	# So nothing hurts them again.
	world.dummies.clear()
	# invulnerable_duration_ticks 10
	_advance(10)
	assert_bool(WorldSnapshot.of(world).players[0].invulnerable).is_false()


func test_no_damage_hurts_an_invulnerable_player() -> void:
	# Unpushed, so the player stays in contact with both.
	_add_dummy(_player().pos, DummyKinds.turret_kind).contact_push_px = 0.0
	_add_dummy(_player().pos, DummyKinds.turret_kind).contact_push_px = 0.0
	WorldSimulator.step(world)
	# MAX_HEALTH 3, less one ENEMY_CONTACT_DAMAGE 1.
	assert_int(_player().health).is_equal(2)
	# The rest of invulnerable_duration_ticks 10.
	_advance(9)
	assert_int(_player().health).is_equal(2)
	WorldSimulator.step(world)
	assert_int(_player().health).is_equal(1)


func test_health_stops_at_zero() -> void:
	# Unpushed, so the player stays in contact.
	_add_dummy(_player().pos, DummyKinds.turret_kind).contact_push_px = 0.0
	_advance(A_WHILE)
	assert_int(_player().health).is_equal(0)


func test_a_dummy_without_contact_damage_never_hurts() -> void:
	_add_dummy(_player().pos, DummyKinds.ready_kind)
	_advance(A_WHILE)
	assert_int(_player().health).is_equal(MAX_HEALTH)


func test_touching_an_enemy_pushes_the_player_away() -> void:
	var start := _player().pos
	var beside := start + Vector2(DUMMY_SIZE.x / 2, 0)
	var enemy := _add_dummy(beside, DummyKinds.turret_kind)
	_advance(ENEMY_CONTACT_PUSH_TICKS + 1)
	# ENEMY_CONTACT_PUSH_PX 20, away from the enemy.
	assert_vector(_player().pos).is_equal_approx(
			start + Vector2(-20, 0), Vector2.ONE * KNOCKBACK_TOLERANCE)
	assert_vector(enemy.pos).is_equal(beside)


func test_a_pushed_player_doesnt_steer() -> void:
	_add_dummy(_player().pos + Vector2(DUMMY_SIZE.x / 2, 0), DummyKinds.turret_kind)
	_steer(Vector2.RIGHT)
	var start := _player().pos
	_advance(ENEMY_CONTACT_PUSH_TICKS + 1)
	assert_float(_player().pos.x).is_less(start.x)


func test_being_hurt_cancels_the_swing() -> void:
	_press()
	WorldSimulator.step(world)
	assert_bool(_is_swinging()).is_true()
	_add_dummy(_player().pos, DummyKinds.turret_kind)
	WorldSimulator.step(world)
	assert_int(_player().health).is_less(MAX_HEALTH)
	assert_bool(_is_swinging()).is_false()


func test_a_push_without_harm_leaves_the_swing_going() -> void:
	_press()
	WorldSimulator.step(world)
	_player().push(Vector2(10, 0), 3)
	WorldSimulator.step(world)
	assert_bool(_player().is_pushed()).is_true()
	assert_bool(_is_swinging()).is_true()


func test_no_swing_starts_while_pushed() -> void:
	_add_dummy(_player().pos, DummyKinds.turret_kind)
	WorldSimulator.step(world)
	_press()
	WorldSimulator.step(world)
	assert_bool(_is_swinging()).is_false()


func test_a_dummy_not_pushed_by_swings_stays_put() -> void:
	var d := _add_dummy_in_reach(DummyKinds.ready_kind)
	var where := d.pos
	_swing()
	assert_vector(d.pos).is_equal(where)


func test_presses_while_frozen_never_swing() -> void:
	world.frozen = true
	_press()
	WorldSimulator.step(world)
	world.frozen = false
	WorldSimulator.step(world)
	assert_bool(_is_swinging()).is_false()
	_press()
	WorldSimulator.step(world)
	assert_bool(_is_swinging()).is_true()


func test_a_dummy_never_struck_reads_as_long_ago() -> void:
	_add_dummy(_player().pos + Vector2(SWING_RADIUS * 4, 0))
	var ticks_since_struck := WorldSnapshot.of(world).dummies[0].ticks_since_struck
	assert_int(ticks_since_struck).is_equal(Snapshot.STRUCK_LONG_AGO)


func test_the_struck_age_counts_up_and_stops_at_long_ago() -> void:
	_add_dummy(_player().pos + Vector2(SWING_RADIUS / 2, 0))
	_press()
	WorldSimulator.step(world)
	_advance(3)
	assert_int(WorldSnapshot.of(world).dummies[0].ticks_since_struck).is_equal(3)
	_advance(Snapshot.STRUCK_LONG_AGO)
	var ticks_since_struck := WorldSnapshot.of(world).dummies[0].ticks_since_struck
	assert_int(ticks_since_struck).is_equal(Snapshot.STRUCK_LONG_AGO)
