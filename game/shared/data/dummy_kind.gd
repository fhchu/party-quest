extends Resource
## One kind of dummy's attributes, in px and seconds. A room places dummies
## by pointing at a kind's file. The defaults are an enemy's.
##
## Every value is PLACEHOLDER (design).

const Attack := preload("res://shared/data/attacks/attack.gd")
const ChargeAttack := preload("res://shared/data/attacks/charge_attack.gd")
const Push := preload("res://shared/data/push.gd")

## How it picks an attack when its aim would lock.
enum AttackChoice {
	## At random by weight, among the attacks it can make now: a charge that
	## would reach its target, or any shot. With none, it waits.
	WEIGHTED_VALID,
	## At random by weight, among all its attacks, even a charge that won't
	## reach.
	WEIGHTED_RANDOM,
	## Each in list order, then back to the first, even a charge that won't
	## reach.
	CYCLE,
}

## The default hurtbox's radius, in px.
const DEFAULT_HURTBOX_RADIUS := 16.0

# Built here, not as hurtbox's default: the export saves an object default
# as null.
static var _default_hurtbox := _circle(DEFAULT_HURTBOX_RADIUS)

## Centered on it and turned with its facing, in px: what swings and
## players touch, and what walls stop. Empty for the default circle; read
## it with [method hurtbox_or_default].
@export var hurtbox: Shape2D
## 0: swings can't damage it.
@export var health := 2
@export var pushed_by_swings := true
## Health a player loses touching it; 0 for none.
@export var contact_damage := 1
## How fast touching it pushes a player away, in px/s, and for how long.
@export var contact_push_speed := Push.DEFAULT_SPEED
@export var contact_push_sec := Push.DEFAULT_SEC
## From the dummy's spawn to its first aim lock; every lock after that
## follows [member attack_interval_sec].
@export var first_attack_delay_sec := 0.5
## From the start of one aim lock to the next, whichever attack each is
## for.
@export var attack_interval_sec := 2.5
## Its fires and charges, in the order CYCLE goes through them. One may be
## listed more than once. Every charge listed is the same one, since the
## client draws a kind's charge cue from it. A kind with none never turns
## or walks.
@export var attacks: Array[Attack] = []
@export var attack_choice := AttackChoice.WEIGHTED_VALID
## The side of the triangle on its front edge that shows its facing, in
## px; 0 for none. PLACEHOLDER (art): until dummies have sprites.
@export var nose_size := 8.0
## How fast it turns.
@export var turn_deg_per_sec := 180.0
## How fast it walks toward its target between attacks, in px/s; 0 for
## not at all.
@export var walk_speed := 0.0


static func _circle(radius: float) -> CircleShape2D:
	var circle := CircleShape2D.new()
	circle.radius = radius
	return circle


## [member hurtbox], or the default circle when it's empty.
func hurtbox_or_default() -> Shape2D:
	return hurtbox if hurtbox else _default_hurtbox


## Its charge in [member attacks], or null.
func charge() -> ChargeAttack:
	for attack in attacks:
		if attack is ChargeAttack:
			return attack
	return null


## [member turn_deg_per_sec] in radians per second.
func turn_rate() -> float:
	return deg_to_rad(turn_deg_per_sec)
