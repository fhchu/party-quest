extends GdUnitTestSuite
## Shared setup for the world's test suites: a world with one player and no
## dummies. Each test gets fresh world data with the balance values it
## depends on set here, so tuning shared/data/ doesn't break the tests.

const World := preload("res://sim/world.gd")
const WorldSnapshot := preload("res://sim/world_snapshot.gd")
const DummyKinds := preload("res://tests/dummy_kinds.gd")
const GameTime := preload("res://shared/game_time.gd")
const RoomShape := preload("res://shared/room_shape.gd")

## Round numbers that keep every swing state a few ticks long. The tests
## need the buffer shorter than the swing, so a press can come too early.
const PINNED_DATA := {
	"swing_ticks": 10,
	"swing_buffer_ticks": 5,
	"walk_step": 100.0 * GameTime.TICK_SEC,
	"invulnerable_duration_ticks": 10,
	"knockback_px": 24.0,
	"knockback_ticks": 6,
	"swing_radius": 30.0,
	"swing_arc": PI / 2,
	"swing_slices": 1,
	"player_max_health": 3,
	"swing_offset": 0.0,
	"swing_damage": 1,
}
# An enemy's attributes in these tests, set on each dummy rather than read
# from its kind's file.
const ENEMY_HEALTH := 3
const ENEMY_CONTACT_DAMAGE := 1
const ENEMY_CONTACT_PUSH_PX := 20.0
const ENEMY_CONTACT_PUSH_TICKS := 4
## The one player most tests use.
const PLAYER_ID := 1
## Any size: the tests place dummies well inside the swing's reach.
const DUMMY_SIZE := Vector2(16, 16)
const PLAYER_SIZE := Vector2(16, 16)
## Long enough for something that shouldn't happen to have had its chance.
const A_WHILE := 300
## Float rounding. Knockback adds up a step per tick, so it rounds more.
const TOLERANCE := 0.001
const KNOCKBACK_TOLERANCE := 0.01

var world: World
var _dummy_hurtbox := RectangleShape2D.new()
var _player_hurtbox := RectangleShape2D.new()


func before_test() -> void:
	_dummy_hurtbox.size = DUMMY_SIZE
	_player_hurtbox.size = PLAYER_SIZE
	World.data = World.WorldData.new()
	_pin(PINNED_DATA)
	World.data.player_hurtbox = _player_hurtbox
	_set_swing(World.data.swing_arc, World.data.swing_slices, World.data.swing_ticks)
	# No room: tests place their own dummies.
	world = World.new()
	world.add_player(PLAYER_ID)


## Puts back data loaded from shared/, for the suites after this one.
func after_test() -> void:
	World.data = World.WorldData.new()


## Sets [param values] on the world data for this test.
func _pin(values: Dictionary) -> void:
	for key: String in values:
		assert(key in World.data, "world data has no %s" % key)
		World.data.set(key, values[key])


## Gives the swing [param arc] in [param slices] over [param ticks], with
## its pieces and turns to match.
func _set_swing(arc: float, slices: int, ticks: int) -> void:
	World.data.swing_arc = arc
	World.data.swing_slices = slices
	World.data.swing_ticks = ticks
	World.data.swing_pieces = World.WorldLoader.swing_pieces(World.data.swing_radius, arc, slices)
	World.data.swing_turns = World.WorldLoader.swing_turns(arc, slices, ticks)


func _player() -> World.Player:
	return world.players[PLAYER_ID]


## Places a dummy of [param kind]. A TURRET gets the test's enemy attributes
## (damageable, pushed by swings, hurts on contact); READY is inert.
## Gives [param d] [param fire] and [param charge], either of which may be
## null: the shot as a weight-0 backup, so it charges whenever a charge
## would reach.
func _arm(d: World.Dummy, fire: World.Fire, charge: World.Charge = null) -> void:
	d.attacks.clear()
	d.weights = PackedFloat32Array()
	d.charge = charge
	if fire:
		d.attacks.append(fire)
		d.weights.append(0.0)
	if charge:
		d.attacks.append(charge)
		d.weights.append(1.0)


func _add_dummy(pos: Vector2, kind := DummyKinds.ready_kind) -> World.Dummy:
	var d := World.Dummy.new()
	d.id = world.dummies.size() + 1
	d.pos = pos
	d.collider = _dummy_hurtbox
	d.kind = kind
	if kind == DummyKinds.turret_kind:
		d.damageable = true
		d.health = ENEMY_HEALTH
		d.pushed_by_swings = true
		d.contact_damage = ENEMY_CONTACT_DAMAGE
		d.contact_push_px = ENEMY_CONTACT_PUSH_PX
		d.contact_push_ticks = ENEMY_CONTACT_PUSH_TICKS
	world.dummies.append(d)
	return d


## Places a dummy where the player's next swing will touch it.
func _add_dummy_in_reach(kind := DummyKinds.ready_kind) -> World.Dummy:
	return _add_dummy(_player().pos + Vector2(World.data.swing_radius / 2, 0), kind)


## Presses attack once more, then steps until that swing is over.
func _swing() -> void:
	world.set_input(PLAYER_ID, Vector2.ZERO, _player().attack_count + 1)
	_advance(World.data.swing_ticks + 1)


## Everything the rules decide, as text, so two worlds compare exactly.
func _state_text(w: World) -> String:
	var parts := []
	for p: World.Player in w.players.values():
		parts.append([p.pos, p.facing, p.state, p.state_ticks, p.health])
	for d in w.dummies:
		parts.append([d.pos, d.struck_tick, d.knockback.ticks])
	return var_to_str(parts)


## Steps the world [param ticks] times.
func _advance(ticks: int) -> void:
	for i in ticks:
		world.step()
