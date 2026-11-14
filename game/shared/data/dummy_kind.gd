extends Resource
## One kind of dummy's attributes, in px and seconds. A map places dummies
## by pointing at a kind's file. The defaults are an enemy's.
##
## Every value is PLACEHOLDER (design).

const FireAttack := preload("res://shared/data/attacks/fire_attack.gd")
const ChargeAttack := preload("res://shared/data/attacks/charge_attack.gd")

## The default hurtbox's radius, in px.
const DEFAULT_HURTBOX_RADIUS := 16.0

## Centered on it and turned with its facing, in px: what swings and
## players touch, and what walls stop.
@export var hurtbox: Shape2D = _default_hurtbox()
## 0: swings can't damage it.
@export var health := 2
@export var pushed_by_swings := true
## Health a player loses touching it; 0 for none.
@export var contact_damage := 1
## How far touching it pushes a player away, in px, and over how long; 0
## moves the player at once.
@export var contact_push_px := 24.0
@export var contact_push_sec := 0.1
## From the start of one aim lock to the next, whichever attack each is
## for.
@export var attack_interval_sec := 2.5
## When its aim would lock, it charges if it has a charge that would reach
## its target, else fires if it has a shot, else waits. A kind with
## neither never turns or walks.
@export var fire: FireAttack
@export var charge: ChargeAttack
## How fast it turns.
@export var turn_deg_per_sec := 180.0
## How fast it walks toward its target between attacks, in px/s; 0 for
## not at all.
@export var walk_speed := 0.0


static func _default_hurtbox() -> CircleShape2D:
	var circle := CircleShape2D.new()
	circle.radius = DEFAULT_HURTBOX_RADIUS
	return circle


## [member turn_deg_per_sec] in radians per second.
func turn_rate() -> float:
	return deg_to_rad(turn_deg_per_sec)
