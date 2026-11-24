extends RefCounted
## Reads the game's data in shared/ and hands the sim plain values: the only
## sim script that touches shared/. Durations become ticks and speeds px per
## tick here, so nothing else converts. Each WorldData copies what it needs
## when it's made.

const GameTime := preload("res://shared/game_time.gd")
const Balance := preload("res://shared/data/balance.gd")
const ItemSword := preload("res://shared/data/items/item_sword.gd")
const DummyKind := preload("res://shared/data/dummy_kind.gd")
const DummyKinds := preload("res://shared/data/dummy_kinds.gd")
const FireAttack := preload("res://shared/data/attacks/fire_attack.gd")
const ChargeAttack := preload("res://shared/data/attacks/charge_attack.gd")
const Push := preload("res://shared/data/push.gd")
const SwingShape := preload("res://shared/swing_shape.gd")
const EquipItem := preload("res://shared/data/items/equip_item.gd")
const Room := preload("res://shared/data/room.gd")
const RunSetup := preload("res://shared/data/run_setup.gd")
const Passage := preload("res://shared/data/passage.gd")
const Condition := preload("res://shared/data/condition.gd")
const RoomShape := preload("res://shared/room_shape.gd")
const Player := preload("res://sim/player.gd")
const Dummy := preload("res://sim/dummy.gd")
const Action := preload("res://sim/action.gd")
const ActionSwing := preload("res://sim/action_swing.gd")
const ActionGuard := preload("res://sim/action_guard.gd")
const Fire := preload("res://sim/fire.gd")
const Charge := preload("res://sim/charge.gd")
const AttackChoice := preload("res://sim/attack_choice.gd")
const Goal := preload("res://sim/goal.gd")
const RoomPlan := preload("res://sim/room_plan.gd")
const RunPlan := preload("res://sim/run_plan.gd")
const WallPlan := preload("res://sim/wall_plan.gd")

const BALANCE: Balance = preload("res://shared/data/balance.tres")
const SWORD: ItemSword = preload("res://shared/data/items/sword.tres")
const DUMMY_KINDS: DummyKinds = preload("res://shared/data/dummy_kinds.tres")
const TOWN: RunSetup = preload("res://shared/data/runs/town.tres")
# Every run is the same one.
const RUN: RunSetup = preload("res://shared/data/runs/first.tres")
## The sim's goal type for each of the data's condition types.
const GOAL_TYPES: Dictionary[Condition.Type, Goal.Type] = {
	Condition.Type.DEFEAT_ALL: Goal.Type.DEFEAT_ALL,
	Condition.Type.PARTY_DOWNED: Goal.Type.PARTY_DOWNED,
	Condition.Type.TIME_UP: Goal.Type.TIME_UP,
	Condition.Type.CLEAR_ROOM: Goal.Type.CLEAR_ROOM,
	Condition.Type.ENTERED: Goal.Type.ENTERED,
}
## The sim's action for each thing an item can do.
const ACTIONS: Dictionary[EquipItem.Action, GDScript] = {
	EquipItem.Action.SWING: ActionSwing,
	EquipItem.Action.GUARD: ActionGuard,
}
## The sim's rule for each of a kind's attack choices.
const ATTACK_RULES: Dictionary[DummyKind.AttackChoice, AttackChoice.Rule] = {
	DummyKind.AttackChoice.WEIGHTED_VALID: AttackChoice.Rule.WEIGHTED_VALID,
	DummyKind.AttackChoice.WEIGHTED_RANDOM: AttackChoice.Rule.WEIGHTED_RANDOM,
	DummyKind.AttackChoice.CYCLE: AttackChoice.Rule.CYCLE,
}


## The four walls by side, made once.
static var _walls: Dictionary[Direction.Cardinal, WallPlan] = _make_walls()

# What WorldData copies.
## The arena, from its top-left corner, in px.
static var arena: Rect2 = BALANCE.arena()
## The side of one square tile, in px.
static var tile_size: float = BALANCE.tile_size
static var player_hurtbox: Shape2D = BALANCE.player_hurtbox
static var player_max_health: int = BALANCE.player_max_health
## [member Player.walk_speed] as px a tick.
static var walk_step := Player.walk_speed * GameTime.TICK_SEC
static var swing_ticks := GameTime.ticks(SWORD.swing_active_sec)
static var swing_buffer_ticks := GameTime.ticks(Player.swing_buffer_sec)
static var invulnerable_duration_ticks := GameTime.ticks(Player.invulnerable_sec)
static var swing_offset: float = SWORD.swing_offset
static var swing_radius: float = SWORD.swing_radius
## In radians.
static var swing_arc: float = SWORD.swing_arc()
static var swing_slices: int = SWORD.swing_slices
## Inside the walls, in px.
static var floor_area := RoomShape.floor_area()
## The four walls every room has.
static var walls: Array[WallPlan] = _walls.values()
## How long a run's result shows over its frozen world.
static var result_ticks := GameTime.ticks(BALANCE.result_sec)
## How far a swing pushes what it hits, in px, and over how many ticks.
static var knockback_px := Push.px(Push.DEFAULT_SPEED, Push.DEFAULT_SEC)
static var knockback_ticks := GameTime.ticks(Push.DEFAULT_SEC)


## One active slice of a swing [param radius] long and [param arc] wide in
## [param slices], pointing along +x, as convex pieces.
static func swing_pieces(radius: float, arc: float, slices: int) -> Array[ConvexPolygonShape2D]:
	var out: Array[ConvexPolygonShape2D] = []
	for points in SwingShape.pieces(radius, arc / slices):
		var piece := ConvexPolygonShape2D.new()
		piece.points = points
		out.append(piece)
	return out


## How far the active slice is turned from the facing on each tick of a
## swing [param ticks] long, from its first.
static func swing_turns(arc: float, slices: int, ticks: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for elapsed in ticks:
		out.append(SwingShape.slice_turn(arc, slices, elapsed, ticks))
	return out


## Town: walking through its door wins it, which the lobby takes as
## starting the run (see "Tech debt" in the wiki).
static func town() -> RunPlan:
	return _run_plan_of(TOWN)


static func first_run() -> RunPlan:
	return _run_plan_of(RUN)


## A run starting in [param start], its rooms joined by [param passages],
## ending on [param win] or [param lose]. Its plans are its own: nothing
## else holds them, so they're freed with it.
static func run_plan(start: Room, passages: Array[Passage] = [],
		win: Array[Condition] = [], lose: Array[Condition] = []) -> RunPlan:
	var out := RunPlan.new()
	var plans: Dictionary[Room, RoomPlan] = {}
	out.start = _room_plan(start, out, plans)
	for passage in passages:
		var from := _room_plan(passage.from, out, plans)
		join(out, from, passage.side, _room_plan(passage.to, out, plans))
	for condition in win:
		out.win.append(_goal(condition, out, plans))
	for condition in lose:
		out.lose.append(_goal(condition, out, plans))
	return out


## A door in [param from]'s [param side] wall into [param to], and one
## back in the opposite wall. Each room joins [param run]'s rooms if it
## isn't one yet.
static func join(run: RunPlan, from: RoomPlan, side: Direction.Cardinal, to: RoomPlan) -> void:
	for room in [from, to]:
		if room not in run.rooms:
			run.rooms.append(room)
	from.doors.append(_door(side, run.rooms.find(to)))
	to.doors.append(_door(Direction.opposite(side), run.rooms.find(from)))


## A new dummy of kind number [param kind_number] with that kind's
## attributes, at the origin.
static func new_dummy(kind_number: int) -> Dummy:
	var kind := DUMMY_KINDS.kinds[kind_number]
	var d := Dummy.new()
	d.kind = kind_number
	# Shared by every dummy of the kind: nothing changes a hurtbox.
	d.collider = kind.hurtbox_or_default()
	d.damageable = kind.health > 0
	d.health = kind.health
	d.pushed_by_swings = kind.pushed_by_swings
	d.contact_damage = kind.contact_damage
	d.contact_push_px = Push.px(kind.contact_push_speed, kind.contact_push_sec)
	d.contact_push_ticks = GameTime.ticks(kind.contact_push_sec)
	d.attack_interval_ticks = GameTime.ticks(kind.attack_interval_sec)
	d.attack_ticks_left = GameTime.ticks(kind.first_attack_delay_sec)
	var charge := kind.charge()
	if charge:
		d.charge = _charge(charge)
	for attack in kind.attacks:
		# A kind has one charge; anything else is a shot.
		if attack == charge:
			d.attacks.append(d.charge)
		else:
			d.attacks.append(_fire(attack))
		d.weights.append(attack.weight)
	d.attack_rule = ATTACK_RULES[kind.attack_choice]
	d.turn_step = kind.turn_rate() * GameTime.TICK_SEC
	d.walk_step = kind.walk_speed * GameTime.TICK_SEC
	return d


## What using [param item] does; null for no item.
static func new_action(item: EquipItem) -> Action:
	if not item:
		return null
	return ACTIONS[item.action].new()


static func _run_plan_of(setup: RunSetup) -> RunPlan:
	var out := run_plan(setup.start, setup.passages, setup.win, setup.lose)
	out.rng_seed = setup.rng_seed
	out.win_gold = setup.win_gold
	return out


## [param room]'s plan in [param run], made once per run: [param plans]
## holds the ones made so far.
static func _room_plan(room: Room, run: RunPlan, plans: Dictionary[Room, RoomPlan]) -> RoomPlan:
	if plans.has(room):
		return plans[room]
	var out := RoomPlan.new()
	plans[room] = out
	run.rooms.append(out)
	out.spawn = room.spawn
	out.spawn_facing = room.spawn_facing
	for dummy in room.dummies:
		var spot := RoomPlan.Spot.new()
		spot.kind = DUMMY_KINDS.index_of(dummy.kind)
		spot.offset = dummy.offset
		spot.on_hit = dummy.on_hit
		out.spots.append(spot)
	for condition in room.clear_when:
		out.clear_goals.append(_goal(condition, run, plans))
	return out


static func _goal(condition: Condition, run: RunPlan, plans: Dictionary[Room, RoomPlan]) -> Goal:
	var out := Goal.new()
	out.type = GOAL_TYPES[condition.type]
	if condition.kind:
		out.kind = DUMMY_KINDS.index_of(condition.kind)
	out.ticks = GameTime.ticks(condition.sec)
	if condition.room:
		out.room = _room_plan(condition.room, run, plans)
	return out


## A door in [param side]'s wall leading to room [param to] of its run.
static func _door(side: Direction.Cardinal, to: int) -> RoomPlan.DoorPlan:
	var out := RoomPlan.DoorPlan.new()
	out.wall = _walls[side]
	out.leads_to = to
	out.arrive_by = _walls[Direction.opposite(side)]
	return out


static func _make_walls() -> Dictionary[Direction.Cardinal, WallPlan]:
	var out: Dictionary[Direction.Cardinal, WallPlan] = {}
	for side: Direction.Cardinal in Direction.Cardinal.values():
		var wall := WallPlan.new()
		wall.inward = Direction.opposite(side)
		wall.gap = RoomShape.door(side)
		wall.pieces_beside_gap = RoomShape.wall(side, true)
		var sides: Array[Direction.Cardinal] = [side]
		wall.door_bit = RoomShape.door_bits(sides)
		out[side] = wall
	return out


static func _fire(attack: FireAttack) -> Fire:
	var fire := Fire.new()
	fire.aim_lock_ticks = GameTime.ticks(attack.aim_lock_sec)
	fire.radius = attack.projectile_radius
	fire.step = attack.projectile_speed * GameTime.TICK_SEC
	fire.damage = attack.projectile_damage
	fire.push_px = Push.px(attack.push_speed, attack.push_sec)
	fire.push_ticks = GameTime.ticks(attack.push_sec)
	return fire


static func _charge(attack: ChargeAttack) -> Charge:
	var charge := Charge.new()
	charge.aim_lock_ticks = GameTime.ticks(attack.aim_lock_sec)
	charge.step = attack.speed * GameTime.TICK_SEC
	charge.length = attack.length
	var brake_ticks := GameTime.ticks(attack.brake_sec)
	charge.brake_end_step = attack.brake_end_speed * GameTime.TICK_SEC
	if brake_ticks > 0:
		charge.brake_slowdown = (charge.step - charge.brake_end_step) / brake_ticks
		# What a steady slowdown from step to brake_end_step covers.
		charge.brake_px = (charge.step + charge.brake_end_step) / 2 * brake_ticks
	charge.cooldown_ticks = GameTime.ticks(attack.cooldown_sec)
	charge.cooldown_walk_step = attack.cooldown_walk_speed * GameTime.TICK_SEC
	return charge
