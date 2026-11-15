extends RefCounted
## Reads the game's data in shared/ and hands the sim plain values: the only
## sim script that touches shared/. Durations become ticks and speeds px per
## tick here, so nothing else converts. World saves what it needs once, when
## its script loads.

const GameTime := preload("res://shared/game_time.gd")
const Balance := preload("res://shared/data/balance.gd")
const DummyKind := preload("res://shared/data/dummy_kind.gd")
const DummyKinds := preload("res://shared/data/dummy_kinds.gd")
const FireAttack := preload("res://shared/data/attacks/fire_attack.gd")
const ChargeAttack := preload("res://shared/data/attacks/charge_attack.gd")
const Push := preload("res://shared/data/push.gd")
const SwingShape := preload("res://shared/swing_shape.gd")
const Room := preload("res://shared/data/room.gd")
const RunSetup := preload("res://shared/data/run_setup.gd")
const Passage := preload("res://shared/data/passage.gd")
const Condition := preload("res://shared/data/condition.gd")
const RoomShape := preload("res://shared/room_shape.gd")
const Player := preload("res://sim/player.gd")
const Dummy := preload("res://sim/dummy.gd")
const Fire := preload("res://sim/fire.gd")
const Charge := preload("res://sim/charge.gd")
const AttackChoice := preload("res://sim/attack_choice.gd")
const Goal := preload("res://sim/goal.gd")
const RoomPlan := preload("res://sim/room_plan.gd")
const RunPlan := preload("res://sim/run_plan.gd")
const WallPlan := preload("res://sim/wall_plan.gd")

const BALANCE: Balance = preload("res://shared/data/balance.tres")
const DUMMY_KINDS: DummyKinds = preload("res://shared/data/dummy_kinds.tres")
const TOWN: Room = preload("res://shared/data/rooms/town.tres")
# PLACEHOLDER (design): every run is the same one.
const RUN: RunSetup = preload("res://shared/data/runs/first.tres")
## The sim's goal type for each of the data's condition types.
const GOAL_TYPES: Dictionary[Condition.Type, Goal.Type] = {
	Condition.Type.DEFEAT_ALL: Goal.Type.DEFEAT_ALL,
	Condition.Type.PARTY_DOWNED: Goal.Type.PARTY_DOWNED,
	Condition.Type.TIME_UP: Goal.Type.TIME_UP,
	Condition.Type.CLEAR_ROOM: Goal.Type.CLEAR_ROOM,
	Condition.Type.ENTERED: Goal.Type.ENTERED,
}
## The sim's rule for each of a kind's attack choices.
const ATTACK_RULES: Dictionary[DummyKind.AttackChoice, AttackChoice.Rule] = {
	DummyKind.AttackChoice.WEIGHTED_VALID: AttackChoice.Rule.WEIGHTED_VALID,
	DummyKind.AttackChoice.WEIGHTED_RANDOM: AttackChoice.Rule.WEIGHTED_RANDOM,
	DummyKind.AttackChoice.CYCLE: AttackChoice.Rule.CYCLE,
}


## Each room's plan, made the first time it's asked for.
static var _plans: Dictionary[Room, RoomPlan] = {}
## The four walls by side, made once.
static var _walls: Dictionary[RoomShape.Side, WallPlan] = _make_walls()

# What World saves when it loads.
## The arena, from its top-left corner, in px.
static var arena: Rect2 = BALANCE.arena()
## The side of one square tile, in px.
static var tile_size: float = BALANCE.tile_size
static var player_hurtbox: Shape2D = BALANCE.player_hurtbox
static var player_max_health: int = BALANCE.player_max_health
## [member Player.walk_speed] as px a tick.
static var walk_step := Player.walk_speed * GameTime.TICK_SEC
static var swing_ticks := GameTime.ticks(BALANCE.swing_active_sec)
static var swing_cooldown_ticks := GameTime.ticks(Player.swing_cooldown_sec)
static var swing_buffer_ticks := GameTime.ticks(Player.swing_buffer_sec)
static var invulnerable_duration_ticks := GameTime.ticks(Player.invulnerable_sec)
static var swing_offset: float = BALANCE.swing_offset
static var swing_radius: float = BALANCE.swing_radius
## In radians.
static var swing_arc: float = BALANCE.swing_arc()
static var swing_slices: int = BALANCE.swing_slices
## Inside the walls, in px.
static var floor_area := RoomShape.floor_area()
## The four walls every room has.
static var walls: Array[WallPlan] = _walls.values()
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


## Town: a world with no passages and nothing that ends it.
static func town() -> RunPlan:
	return run_plan(TOWN)


static func first_run() -> RunPlan:
	var out := run_plan(RUN.start, RUN.passages, RUN.win, RUN.lose)
	out.rng_seed = RUN.rng_seed
	return out


## A run starting in [param start], its rooms joined by [param passages],
## ending on [param win] or [param lose].
static func run_plan(start: Room, passages: Array[Passage] = [],
		win: Array[Condition] = [], lose: Array[Condition] = []) -> RunPlan:
	var out := RunPlan.new()
	out.start = room_plan(start)
	for passage in passages:
		room_plan(passage.from).doors.clear()
		room_plan(passage.to).doors.clear()
	for passage in passages:
		join(room_plan(passage.from), passage.side, room_plan(passage.to))
	for condition in win:
		out.win.append(goal(condition))
	for condition in lose:
		out.lose.append(goal(condition))
	return out


## [param room]'s plan, the same object every time. Its doors are joined
## by [method run_plan].
static func room_plan(room: Room) -> RoomPlan:
	if _plans.has(room):
		return _plans[room]
	var out := RoomPlan.new()
	_plans[room] = out
	out.spawn = room.spawn
	out.spawn_facing = room.spawn_facing
	for dummy in room.dummies:
		var spot := RoomPlan.Spot.new()
		spot.kind = DUMMY_KINDS.index_of(dummy.kind)
		spot.offset = dummy.offset
		spot.on_hit = dummy.on_hit
		out.spots.append(spot)
	for condition in room.clear_when:
		out.clear_goals.append(goal(condition))
	return out


static func goal(condition: Condition) -> Goal:
	var out := Goal.new()
	out.type = GOAL_TYPES[condition.type]
	if condition.kind:
		out.kind = DUMMY_KINDS.index_of(condition.kind)
	out.ticks = GameTime.ticks(condition.sec)
	if condition.room:
		out.room = room_plan(condition.room)
	return out


## A door in [param from]'s [param side] wall into [param to], and one
## back in the opposite wall.
static func join(from: RoomPlan, side: RoomShape.Side, to: RoomPlan) -> void:
	from.doors.append(_door(side, to))
	to.doors.append(_door(RoomShape.opposite(side), from))


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


## A door in [param side]'s wall leading to [param to].
static func _door(side: RoomShape.Side, to: RoomPlan) -> RoomPlan.DoorPlan:
	var out := RoomPlan.DoorPlan.new()
	out.wall = _walls[side]
	out.leads_to = to
	out.arrive_by = _walls[RoomShape.opposite(side)]
	return out


static func _make_walls() -> Dictionary[RoomShape.Side, WallPlan]:
	var out: Dictionary[RoomShape.Side, WallPlan] = {}
	for side: RoomShape.Side in RoomShape.Side.values():
		var wall := WallPlan.new()
		wall.inward = RoomShape.inward(side)
		wall.gap = RoomShape.door(side)
		wall.pieces_beside_gap = RoomShape.wall(side, true)
		var sides: Array[RoomShape.Side] = [side]
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
