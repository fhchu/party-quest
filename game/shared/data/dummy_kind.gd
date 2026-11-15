extends Resource
## One kind of dummy's attributes, in px and seconds. A room places dummies
## by pointing at a kind's file. The defaults are an enemy's.
##
## Every value is PLACEHOLDER (design).

const FireAttack := preload("res://shared/data/attacks/fire_attack.gd")
const ChargeAttack := preload("res://shared/data/attacks/charge_attack.gd")
const Push := preload("res://shared/data/push.gd")

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
## From the start of one aim lock to the next, whichever attack each is
## for.
@export var attack_interval_sec := 2.5
## When its aim would lock, it charges if it has a charge that would reach
## its target, else fires if it has a shot, else waits. A kind with
## neither never turns or walks.
@export var fire: FireAttack
@export var charge: ChargeAttack
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


## [member turn_deg_per_sec] in radians per second.
func turn_rate() -> float:
	return deg_to_rad(turn_deg_per_sec)
