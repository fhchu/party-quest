extends GdUnitTestSuite
## Shared setup for the world's test suites: a world with one player and no
## dummies. Each test gets fresh world data with the balance values it
## depends on set here, so tuning shared/data/ doesn't break the tests.

const WorldState := preload("res://sim/world_state.gd")
const WorldLoader := preload("res://sim/world_loader.gd")
const Charge := preload("res://sim/charge.gd")
const Fire := preload("res://sim/fire.gd")
const WorldSimulator := preload("res://sim/world_simulator.gd")
const DummyKinds := preload("res://tests/dummy_kinds.gd")
const RoomShape := preload("res://shared/room_shape.gd")
const Dummy := preload("res://sim/dummy.gd")
const Player := preload("res://sim/player.gd")
const Action := preload("res://sim/action.gd")
const WorldData := preload("res://sim/world_data.gd")
const EquipItem := preload("res://shared/data/items/equip_item.gd")
const ItemShield := preload("res://shared/data/items/item_shield.gd")
const ItemSword := preload("res://shared/data/items/item_sword.gd")

## Round numbers that keep every state a few ticks long.
const PINNED_DATA := {
	"walk_step": 100.0 * GameTime.TICK_SEC,
	"invulnerable_duration_ticks": 10,
	"knockback_px": 24.0,
	"knockback_ticks": 6,
	"player_max_health": 3,
	"swing_damage": 1,
}
## The test sword's swing, unless a test sets its own (see [method _set_swing]).
const SWING_TICKS := 10
const SWING_RADIUS := 30.0
const SWING_ARC := PI / 2
# An enemy's attributes in these tests, set on each dummy rather than read
# from its kind's file.
const ENEMY_HEALTH := 3
const ENEMY_CONTACT_DAMAGE := 1
const ENEMY_CONTACT_PUSH_PX := 20.0
const ENEMY_CONTACT_PUSH_TICKS := 4
## The one player most tests use.
const PLAYER_ID := 1
## The input action whose item slot holds the player's sword.
const SWORD_INPUT := 0
## Any size: the tests place dummies well inside the swing's reach.
const DUMMY_SIZE := Vector2(16, 16)
const PLAYER_SIZE := Vector2(16, 16)
## Long enough for something that shouldn't happen to have had its chance.
const A_WHILE := 300
## Knockback adds up a step per tick, so its float rounding outgrows
## Godot's own is_equal_approx.
const KNOCKBACK_TOLERANCE := 0.01

var world: WorldState
var _dummy_hurtbox := RectangleShape2D.new()
var _player_hurtbox := RectangleShape2D.new()


func before_test() -> void:
	_dummy_hurtbox.size = DUMMY_SIZE
	_player_hurtbox.size = PLAYER_SIZE
	WorldState.data = WorldData.new()
	_pin(PINNED_DATA)
	WorldState.data.player_hurtbox = _player_hurtbox
	# No room: tests place their own dummies.
	world = WorldSimulator.start()
	_add_armed_player(world, PLAYER_ID)


## Puts back data loaded from shared/, for the suites after this one.
func after_test() -> void:
	WorldState.data = WorldData.new()


## Sets [param values] on the world data for this test.
func _pin(values: Dictionary) -> void:
	for key: String in values:
		assert(key in WorldState.data, "world data has no %s" % key)
		WorldState.data.set(key, values[key])


## Puts in the player's sword slot a sword whose swing is [param arc] wide
## in [param slices] over [param ticks], starting [param offset] px ahead.
func _set_swing(arc: float, slices: int, ticks: int, offset := 0.0) -> void:
	WorldSimulator.set_slot_item(
			world, PLAYER_ID, SWORD_INPUT, _sword(arc, slices, ticks, offset))


## A sword whose swing is [param arc] wide in [param slices] over
## [param ticks], starting [param offset] px ahead, [constant SWING_RADIUS]
## long.
static func _sword(arc := SWING_ARC, slices := 1, ticks := SWING_TICKS, offset := 0.0) -> ItemSword:
	var out := ItemSword.new()
	out.action = EquipItem.Action.SWING
	out.swing_active_sec = ticks * GameTime.TICK_SEC
	out.swing_radius = SWING_RADIUS
	out.swing_arc_deg = rad_to_deg(arc)
	out.swing_slices = slices
	out.swing_offset = offset
	return out


func _is_swinging() -> bool:
	return _player().slot_actions[SWORD_INPUT].is_busy()


func _player() -> Player:
	return world.players[PLAYER_ID]


## Places a dummy of [param kind]. A TURRET gets the test's enemy attributes
## (damageable, pushed by swings, hurts on contact); READY is inert.
## Gives [param d] [param fire] and [param charge], either of which may be
## null: the shot as a weight-0 backup, so it charges whenever a charge
## would reach.
func _arm(d: Dummy, fire: Fire, charge: Charge = null) -> void:
	d.attacks.clear()
	d.weights = PackedFloat32Array()
	d.charge = charge
	if fire:
		d.attacks.append(fire)
		d.weights.append(0.0)
	if charge:
		d.attacks.append(charge)
		d.weights.append(1.0)


func _add_dummy(pos: Vector2, kind := DummyKinds.ready_kind) -> Dummy:
	var d := Dummy.new()
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
func _add_dummy_in_reach(kind := DummyKinds.ready_kind) -> Dummy:
	return _add_dummy(_player().pos + Vector2(SWING_RADIUS / 2, 0), kind)


## Adds player [param id] to [param w] with a sword in its first item slot.
static func _add_armed_player(w: WorldState, id: int) -> void:
	WorldSimulator.add_player(w, id)
	WorldSimulator.set_slot_item(w, id, SWORD_INPUT, _sword())


## Presses input action [param index] once, moving along [param move].
func _press(move := Vector2.ZERO, index := SWORD_INPUT) -> void:
	var presses := PackedByteArray()
	presses.resize(index + 1)
	presses[index] = 1
	WorldSimulator.set_input(world, PLAYER_ID, move, presses, 0)


## Moves along [param move], pressing nothing.
func _steer(move: Vector2) -> void:
	WorldSimulator.set_input(world, PLAYER_ID, move, PackedByteArray(), 0)


## Presses attack once more, then steps until that swing is over.
func _swing() -> void:
	_press()
	_advance(SWING_TICKS + 1)


## Everything the rules decide, as text, so two worlds compare exactly.
func _state_text(w: WorldState) -> String:
	var parts := []
	for p: Player in w.players.values():
		var ticks := p.slot_actions.map(func(a: Action) -> int: return a.slot_ticks() if a else 0)
		parts.append([p.pos, p.facing, ticks, p.health])
	for d in w.dummies:
		parts.append([d.pos, d.struck_tick, d.knockback.ticks])
	return var_to_str(parts)


## Steps the world [param ticks] times.
func _advance(ticks: int) -> void:
	for i in ticks:
		WorldSimulator.step(world)
