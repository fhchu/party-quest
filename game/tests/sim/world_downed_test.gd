extends "res://tests/sim/world_fixture.gd"
## A player at 0 health is downed: out of the fight until the run ends.


## Hurts the player down to 0 by touching an enemy, waiting out each
## invulnerability.
func _down_player() -> World.Dummy:
	var enemy := _add_dummy(_player().pos, World.enemy_kind)
	while not _player().is_downed():
		_player().invulnerable_ticks = 0
		world.step()
	return enemy


func test_the_last_hit_downs_the_player_without_a_push_or_blink() -> void:
	_player().health = 1
	_add_dummy(_player().pos + Vector2(4, 0), World.enemy_kind)
	var pos := _player().pos
	world.step()
	assert_bool(_player().is_downed()).is_true()
	assert_int(_player().invulnerable_ticks).is_zero()
	world.step()
	assert_vector(_player().pos).is_equal(pos)


func test_a_downed_player_doesnt_move_swing_or_get_hurt() -> void:
	var enemy := _down_player()
	enemy.pos = _player().pos + Vector2(World.swing_radius / 2, 0)
	var pos := _player().pos
	world.set_input(PLAYER_ID, Vector2.RIGHT, 1)
	_advance(Player.swing_ticks)
	assert_vector(_player().pos).is_equal(pos)
	assert_int(enemy.health).is_equal(ENEMY_HEALTH)
	assert_int(_player().health).is_zero()
	assert_bool(world.snapshot().players[0].invulnerable).is_false()


func test_being_downed_stops_a_swing_and_a_push() -> void:
	_player().health = 1
	world.set_input(PLAYER_ID, Vector2.ZERO, 1)
	world.step()
	_player().push(Vector2(World.knockback_px, 0), World.knockback_ticks)
	assert_bool(_player().take_damage(1)).is_true()
	assert_int(_player().phase).is_equal(World.Phase.READY)
	assert_bool(_player().is_pushed()).is_false()


func test_downed_players_dont_count_as_alive() -> void:
	world.add_player(PLAYER_ID + 1)
	assert_int(world.players_alive()).is_equal(2)
	_down_player()
	assert_int(world.players_alive()).is_equal(1)
	assert_bool(world.snapshot().players[0].is_downed()).is_true()
