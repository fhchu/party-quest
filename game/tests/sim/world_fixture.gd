extends GdUnitTestSuite
## Shared setup for the world's test suites: a world with one player and no
## dummies. Balance values that a test depends on are set here and restored
## afterwards, so tuning balance.json doesn't break the tests.

const World := preload("res://sim/world.gd")
const Player := preload("res://sim/player.gd")
const GameTime := preload("res://shared/game_time.gd")

## Round numbers that keep every phase a few ticks long, by the class that
## keeps each. The tests need the buffer shorter than the swing, so a press
## can come too early.
const PINNED_ON_PLAYER := {
	"swing_ticks": 10,
	"swing_cooldown_ticks": 0,
	"swing_buffer_ticks": 5,
	"speed": 100.0,
	"hurt_invulnerable_ticks": 10,
}
const PINNED_ON_WORLD := {
	"knockback_px": 24.0,
	"knockback_ticks": 6,
	"swing_radius": 30.0,
	"swing_arc": PI / 2,
	"player_max_health": 3,
	"swing_damage": 1,
}
# An enemy's attributes in these tests, set on each dummy rather than read
# from balance.json.
const ENEMY_HEALTH := 3
const ENEMY_CONTACT_DAMAGE := 1
const ENEMY_CONTACT_PUSH_PX := 20.0
const ENEMY_CONTACT_PUSH_TICKS := 4
## The one player most tests use.
const PLAYER_ID := 1
## Any size: the tests place dummies well inside the swing's reach.
const DUMMY_SIZE := Vector2(16, 16)
## Long enough for something that shouldn't happen to have had its chance.
const A_WHILE := 300
## Float rounding. Knockback adds up a step per tick, so it rounds more.
const TOLERANCE := 0.001
const KNOCKBACK_TOLERANCE := 0.01

var world: World
var _saved := {}


func before_test() -> void:
	_pin(Player, PINNED_ON_PLAYER)
	_pin(World, PINNED_ON_WORLD)
	world = World.new()
	# Tests place their own.
	world.dummies.clear()
	world.add_player(PLAYER_ID)


func after_test() -> void:
	for keeper: Object in _saved:
		for key: String in _saved[keeper]:
			keeper.set(key, _saved[keeper][key])
	_saved.clear()


## Sets [param values] on [param keeper]'s static variables, saving the old
## ones for after_test. A script, as an object, has its static variables as
## properties.
func _pin(keeper: Object, values: Dictionary) -> void:
	var saved := {}
	for key: String in values:
		assert(key in keeper, "%s has no %s" % [keeper.resource_path, key])
		saved[key] = keeper.get(key)
		keeper.set(key, values[key])
	_saved[keeper] = saved


func _player() -> World.Player:
	return world.players[PLAYER_ID]


## Places a dummy of [param kind]. An ENEMY gets the test's enemy attributes
## (damageable, pushed by swings, hurts on contact); READY and START are
## inert.
func _add_dummy(pos: Vector2, kind := World.start_kind) -> World.Dummy:
	var d := World.Dummy.new()
	d.id = world.dummies.size() + 1
	d.pos = pos
	d.size = DUMMY_SIZE
	d.kind = kind
	if kind == World.enemy_kind:
		d.damageable = true
		d.health = ENEMY_HEALTH
		d.pushed_by_swings = true
		d.contact_damage = ENEMY_CONTACT_DAMAGE
		d.contact_push_px = ENEMY_CONTACT_PUSH_PX
		d.contact_push_ticks = ENEMY_CONTACT_PUSH_TICKS
	world.dummies.append(d)
	return d


## Places a dummy where the player's next swing will touch it.
func _add_dummy_in_reach(kind := World.start_kind) -> World.Dummy:
	return _add_dummy(_player().pos + Vector2(World.swing_radius / 2, 0), kind)


## Presses attack once more, then steps until that swing is over.
func _swing() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, _player().attack_count + 1)
	_advance(Player.swing_ticks + 1)


## Everything the rules decide, as text, so two worlds compare exactly.
func _state_text(w: World) -> String:
	var parts := []
	for p: World.Player in w.players.values():
		parts.append([p.pos, p.facing, p.phase, p.phase_ticks, p.health])
	for d in w.dummies:
		parts.append([d.pos, d.struck_tick, d.knockback.ticks])
	return var_to_str(parts)


## Steps the world [param ticks] times.
func _advance(ticks: int) -> void:
	for i in ticks:
		world.step()
