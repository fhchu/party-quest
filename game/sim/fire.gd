extends RefCounted
## A dummy's shot, from its kind's fire attack with durations in ticks. The
## world fires it toward the dummy's locked aim.

const Fire := preload("res://sim/fire.gd")
const FireAttack := preload("res://shared/data/attacks/fire_attack.gd")
const GameTime := preload("res://shared/game_time.gd")

## From its aim lock to the shot.
var aim_lock_ticks := 0
## In px.
var radius := 0.0
## How far the shot moves each tick, in px.
var step := 0.0
## Health a player loses to the shot.
var damage := 0
## How far the shot pushes the player it hits, in px, and over how long.
var push_px := 0.0
var push_ticks := 0


static func from_attack(attack: FireAttack) -> Fire:
	var fire := Fire.new()
	fire.aim_lock_ticks = GameTime.ticks(attack.aim_lock_sec)
	fire.radius = attack.projectile_radius
	fire.step = attack.projectile_speed * GameTime.TICK_SEC
	fire.damage = attack.projectile_damage
	fire.push_px = attack.push_px
	fire.push_ticks = GameTime.ticks(attack.push_sec)
	return fire
