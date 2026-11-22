extends "res://tests/sim/world_fixture.gd"
## A room becoming cleared heals every player, and revives downed ones.

const DataRecords := preload("res://tests/data_records.gd")

const PINNED_HEAL := {
	"clear_heal": true,
	"clear_heal_amount": 1,
	"clear_heal_invulnerable": false,
}
const OTHER_ID := PLAYER_ID + 1


func before_test() -> void:
	super.before_test()
	_pin(PINNED_HEAL)
	world.add_player(OTHER_ID)


func test_a_clear_heals_every_player_up_to_their_max() -> void:
	_player().health = World.data.player_max_health - 1
	_other().health = World.data.player_max_health
	_clear_a_room()
	assert_int(_player().health).is_equal(World.data.player_max_health)
	assert_int(_other().health).is_equal(World.data.player_max_health)


func test_a_clear_revives_a_downed_player_where_they_are() -> void:
	_player().health = 0
	var pos := _player().pos
	_clear_a_room()
	assert_int(_player().health).is_equal(World.data.clear_heal_amount)
	assert_vector(_player().pos).is_equal(pos)
	assert_int(world.players_alive()).is_equal(2)


func test_an_invulnerable_heal_protects_every_player() -> void:
	World.data.clear_heal_invulnerable = true
	_clear_a_room()
	for p: World.Player in world.players.values():
		assert_int(p.invulnerable_ticks).is_equal(p.invulnerable_duration_ticks)


func test_a_heal_that_isnt_invulnerable_leaves_players_hurtable() -> void:
	_clear_a_room()
	assert_int(_player().invulnerable_ticks).is_zero()


func test_with_the_heal_off_a_clear_heals_nobody() -> void:
	World.data.clear_heal = false
	_player().health = 0
	_clear_a_room()
	assert_bool(_player().is_downed()).is_true()


func test_a_room_cleared_on_entry_heals_the_first_time_only() -> void:
	var hall := DataRecords.new_room(false)
	hall.clear_goals = [DataRecords.goal(DataRecords.Goal.Type.ENTERED)]
	_player().health = 1
	world.enter_room(hall)
	world.step()
	assert_int(_player().health).is_equal(2)
	world.enter_room(DataRecords.new_room(false))
	world.enter_room(hall)
	world.step()
	assert_int(_player().health).is_equal(2)


func test_a_clear_on_the_step_the_party_goes_down_saves_the_run() -> void:
	var lose: Array[World.Goal] = [DataRecords.goal(DataRecords.Goal.Type.PARTY_DOWNED)]
	world = World.new(DataRecords.run(DataRecords.new_room(true), [], lose))
	world.add_player(PLAYER_ID)
	world.dummies[0].health = 0
	var shot := World.Projectile.new()
	shot.pos = _player().pos
	shot.radius = 1.0
	shot.damage = World.data.player_max_health
	world.projectiles.append(shot)
	world.step()
	assert_bool(_player().is_downed()).is_false()
	assert_int(world.outcome).is_equal(World.Outcome.NONE)


func _other() -> World.Player:
	return world.players[OTHER_ID]


## Enters a room with an enemy, and clears it.
func _clear_a_room() -> void:
	world.enter_room(DataRecords.new_room(true))
	world.dummies.clear()
	world.step()
