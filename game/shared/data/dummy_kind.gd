extends Resource
## One kind of dummy's attributes, in px and seconds. A map places dummies
## by pointing at a kind's file.
##
## Every value is PLACEHOLDER (design).

## Which attack a dummy makes when its aim locks.
enum AttackChoice {
	## A shot at its target.
	FIRE,
	## A charge, once one would reach its target; until then it waits.
	CHARGE,
	## A charge if one would reach its target, else a shot.
	BY_RANGE,
}

## Centered on it and turned with its facing, in px: what swings and
## players touch, and what walls stop.
@export var hurtbox: Shape2D
## 0: swings can't damage it.
@export var health := 0
@export var pushed_by_swings := false
## Health a player loses touching it; 0 for none.
@export var contact_damage := 0
## How far touching it pushes a player away, in px, and over how long; 0
## moves the player at once.
@export var contact_push_px := 0.0
@export var contact_push_sec := 0.0
## Between attacks, from the end of one to the next; 0 for a dummy that
## never attacks.
@export var attack_interval_sec := 0.0
@export var attack_choice := AttackChoice.FIRE
## How long before each attack it locks onto where its target is.
@export var aim_lock_sec := 0.0
## How fast it turns.
@export var turn_deg_per_sec := 0.0
## Its shots' radius, in px.
@export var projectile_radius := 0.0
## In px/s.
@export var projectile_speed := 0.0
## Health a player loses to one of its shots. The shot pushes like touching
## it does.
@export var projectile_damage := 0
## How fast it walks toward its target between attacks, in px/s; 0 for
## not at all.
@export var walk_speed := 0.0
## In px/s.
@export var charge_speed := 0.0
## How far one charge moves it, in px. It charges only at a target whose
## edge is this close to its own, along the line between them.
@export var charge_length := 0.0


## [member turn_deg_per_sec] in radians per second.
func turn_rate() -> float:
	return deg_to_rad(turn_deg_per_sec)
