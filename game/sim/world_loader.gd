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
const Player := preload("res://sim/player.gd")
const Dummy := preload("res://sim/dummy.gd")
const Fire := preload("res://sim/fire.gd")
const Charge := preload("res://sim/charge.gd")
const AttackChoice := preload("res://sim/attack_choice.gd")

const BALANCE: Balance = preload("res://shared/data/balance.tres")
const DUMMY_KINDS: DummyKinds = preload("res://shared/data/dummy_kinds.tres")
## The sim's rule for each of a kind's attack choices.
const ATTACK_RULES: Dictionary[DummyKind.AttackChoice, AttackChoice.Rule] = {
	DummyKind.AttackChoice.WEIGHTED_VALID: AttackChoice.Rule.WEIGHTED_VALID,
	DummyKind.AttackChoice.WEIGHTED_RANDOM: AttackChoice.Rule.WEIGHTED_RANDOM,
	DummyKind.AttackChoice.CYCLE: AttackChoice.Rule.CYCLE,
}


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


## [param kind]'s number in snapshots, -1 for none.
static func kind_number(kind: DummyKind) -> int:
	return DUMMY_KINDS.index_of(kind) if kind else -1


## A new dummy of [param kind] with that kind's attributes, at the origin.
static func new_dummy(kind: DummyKind) -> Dummy:
	var d := Dummy.new()
	d.kind = kind_number(kind)
	# Shared by every dummy of the kind: nothing changes a hurtbox.
	d.collider = kind.hurtbox_or_default()
	d.damageable = kind.health > 0
	d.health = kind.health
	d.pushed_by_swings = kind.pushed_by_swings
	d.contact_damage = kind.contact_damage
	d.contact_push_px = Push.px(kind.contact_push_speed, kind.contact_push_sec)
	d.contact_push_ticks = GameTime.ticks(kind.contact_push_sec)
	d.attack_interval_ticks = GameTime.ticks(kind.attack_interval_sec)
	d.attack_ticks_left = d.attack_interval_ticks
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
