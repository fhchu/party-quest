extends "res://tests/sim/world_fixture.gd"
## Shots: they fly straight, hurt and push the first living player they
## touch, and are gone on a player or a wall.

const Projectile := preload("res://sim/projectile.gd")

const SHOT_RADIUS := 2.0
const SHOT_DAMAGE := 1
const SHOT_PUSH_PX := 20.0
const SHOT_PUSH_TICKS := 4
## px/s: 2 px a tick, so a shot never skips past a hurtbox.
const SHOT_SPEED := 60.0


## A shot at [param pos] moving at [param velocity] px/s.
func _add_shot(pos: Vector2, velocity: Vector2) -> Projectile:
	var s := Projectile.new()
	s.pos = pos
	s.step = velocity * GameTime.TICK_SEC
	s.radius = SHOT_RADIUS
	s.damage = SHOT_DAMAGE
	s.push_px = SHOT_PUSH_PX
	s.push_ticks = SHOT_PUSH_TICKS
	world.projectiles.append(s)
	return s


## A shot to the left of the player, moving right, [param ticks] from
## touching their hurtbox.
func _add_shot_at_player(ticks: int) -> Projectile:
	var gap := DUMMY_SIZE.x / 2 + SHOT_RADIUS + SHOT_SPEED * GameTime.TICK_SEC * (ticks - 0.5)
	return _add_shot(_player().pos - Vector2(gap, 0), Vector2(SHOT_SPEED, 0))


func test_a_turret_fires_at_its_locked_spot_at_its_speed() -> void:
	var d := _add_dummy(_player().pos + Vector2(-100, -100), DummyKinds.turret_kind)
	d.attack_interval_ticks = 10
	d.attack_ticks_left = 10
	var fire := Fire.new()
	fire.aim_lock_ticks = 3
	fire.step = SHOT_SPEED * GameTime.TICK_SEC
	fire.radius = SHOT_RADIUS
	_arm(d, fire)
	# attack_interval_ticks 10, then aim_lock_ticks 3.
	_advance(13)
	assert_int(world.projectiles.size()).is_equal(1)
	var s := world.projectiles[0]
	# 2 px a tick down and to the right: 2 * cos(45°) each way.
	var step := Vector2(1.414, 1.414)
	assert_vector(s.step).is_equal_approx(step, Vector2.ONE * 0.001)
	assert_vector(s.pos).is_equal_approx(d.pos + step, Vector2.ONE * 0.001)


func test_a_shot_hurts_pushes_and_stops_a_swing() -> void:
	_press()
	WorldSimulator.step(world)
	var start := _player().pos
	_add_shot_at_player(1)
	WorldSimulator.step(world)
	assert_array(world.projectiles).is_empty()
	# MAX_HEALTH 3, less SHOT_DAMAGE 1.
	assert_int(_player().health).is_equal(2)
	assert_bool(_is_swinging()).is_false()
	_advance(SHOT_PUSH_TICKS)
	assert_float(_player().pos.x - start.x).is_equal_approx(SHOT_PUSH_PX, KNOCKBACK_TOLERANCE)


func test_a_shot_on_an_invulnerable_player_is_gone_without_hurting() -> void:
	_player().invulnerable_ticks = A_WHILE
	_add_shot_at_player(1)
	WorldSimulator.step(world)
	assert_array(world.projectiles).is_empty()
	assert_int(_player().health).is_equal(MAX_HEALTH)


func test_shots_pass_through_downed_players_and_dummies() -> void:
	_player().health = 0
	var s := _add_shot_at_player(1)
	_add_dummy(_player().pos + Vector2(DUMMY_SIZE.x, 0), DummyKinds.turret_kind)
	# Three DUMMY_SIZE widths at 2 px a tick.
	_advance(24)
	assert_array(world.projectiles).contains([s])


func test_a_shot_is_gone_at_a_wall() -> void:
	var edge := RoomShape.floor_area().end.x - SHOT_RADIUS
	var start := Vector2(edge - SHOT_SPEED * GameTime.TICK_SEC * 2.5, 50)
	var s := _add_shot(start, Vector2(SHOT_SPEED, 0))
	_advance(2)
	assert_array(world.projectiles).contains([s])
	WorldSimulator.step(world)
	assert_array(world.projectiles).is_empty()
