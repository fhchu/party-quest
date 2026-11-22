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
	WorldSimulator.add_player(world, OTHER_ID)


func test_a_clear_heals_every_player_up_to_their_max() -> void:
	_player().health = WorldState.data.player_max_health - 1
	_other().health = WorldState.data.player_max_health
	_clear_a_room()
	assert_int(_player().health).is_equal(WorldState.data.player_max_health)
	assert_int(_other().health).is_equal(WorldState.data.player_max_health)


func test_a_clear_revives_a_downed_player_where_they_are() -> void:
	_player().health = 0
	var pos := _player().pos
	_clear_a_room()
	assert_int(_player().health).is_equal(WorldState.data.clear_heal_amount)
	assert_vector(_player().pos).is_equal(pos)
	assert_int(world.players_alive()).is_equal(2)


func test_an_invulnerable_heal_protects_every_player() -> void:
	WorldState.data.clear_heal_invulnerable = true
	_clear_a_room()
	for p: WorldState.Player in world.players.values():
		assert_int(p.invulnerable_ticks).is_equal(p.invulnerable_duration_ticks)


func test_a_heal_that_isnt_invulnerable_leaves_players_hurtable() -> void:
	_clear_a_room()
	assert_int(_player().invulnerable_ticks).is_zero()


func test_with_the_heal_off_a_clear_heals_nobody() -> void:
	WorldState.data.clear_heal = false
	_player().health = 0
	_clear_a_room()
	assert_bool(_player().is_downed()).is_true()


func test_a_room_cleared_on_entry_heals_the_first_time_only() -> void:
	var hall := DataRecords.new_room(false)
	hall.clear_goals = [DataRecords.goal(DataRecords.Goal.Type.ENTERED)]
	_player().health = 1
	WorldSimulator.enter_room(world, hall)
	WorldSimulator.step(world)
	assert_int(_player().health).is_equal(2)
	WorldSimulator.enter_room(world, DataRecords.new_room(false))
	WorldSimulator.enter_room(world, hall)
	WorldSimulator.step(world)
	assert_int(_player().health).is_equal(2)


func test_a_clear_on_the_step_the_party_goes_down_saves_the_run() -> void:
	var lose: Array[Goal] = [DataRecords.goal(DataRecords.Goal.Type.PARTY_DOWNED)]
	world = WorldSimulator.start(DataRecords.run(DataRecords.new_room(true), [], lose))
	WorldSimulator.add_player(world, PLAYER_ID)
	world.dummies[0].health = 0
	var shot := WorldState.Projectile.new()
	shot.pos = _player().pos
	shot.radius = 1.0
	shot.damage = WorldState.data.player_max_health
	world.projectiles.append(shot)
	WorldSimulator.step(world)
	assert_bool(_player().is_downed()).is_false()
	assert_int(world.outcome).is_equal(WorldState.Outcome.NONE)


func _other() -> WorldState.Player:
	return world.players[OTHER_ID]


## Enters a room with an enemy, and clears it.
func _clear_a_room() -> void:
	WorldSimulator.enter_room(world, DataRecords.new_room(true))
	world.dummies.clear()
	WorldSimulator.step(world)
