extends RefCounted
## Random movement and attacks, for load tests. May grow into the Phase 4
## simulator bots.

const World := preload("res://sim/world.gd")

# Arbitrary: enough to keep a load test busy.
const TURN_SEC := 1.0
const ATTACK_SEC := 0.5

var move := Vector2.ZERO
var _next_turn := 0.0
var _next_attack := 0.0


## Returns whether to press attack now.
func tick(now: float) -> bool:
	if now >= _next_turn:
		_next_turn = now + TURN_SEC
		move = Vector2.from_angle(randi_range(0, World.DIRECTIONS - 1) * World.DIRECTION_STEP)
	if now < _next_attack:
		return false
	_next_attack = now + ATTACK_SEC
	return true
