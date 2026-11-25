extends RefCounted
## Builds worlds and turns a world and its players' input into the next tick:
## dummies think and move, players move and swing, shots fly, and contact
## hurts. Also adds, removes and steers players, moves the party from room to
## room, opens doors, shows results and hands out IDs.

const WorldState := preload("res://sim/world_state.gd")
const Body := preload("res://sim/body.gd")
const Actor := preload("res://sim/actor.gd")
const Player := preload("res://sim/player.gd")
const Action := preload("res://sim/action.gd")
const Dummy := preload("res://sim/dummy.gd")
const Projectile := preload("res://sim/projectile.gd")
const PartySquare := preload("res://sim/party_square.gd")
const RoomPlan := preload("res://sim/room_plan.gd")
const RunPlan := preload("res://sim/run_plan.gd")
const Goal := preload("res://sim/goal.gd")
const RoomState := preload("res://sim/room_state.gd")
const WorldLoader := preload("res://sim/world_loader.gd")
const EquipItem := preload("res://shared/data/items/equip_item.gd")


## A check for [param goal]: it is passed the world and returns whether the
## goal is met. A TIME_UP goal also limits [param world]'s time.
static func goal_check(goal: Goal, world: WorldState) -> Callable:
	var check := Callable()
	match goal.type:
		Goal.Type.DEFEAT_ALL:
			if goal.kind == Goal.EVERY_KIND:
				check = func(w: WorldState) -> bool: return w.dummies.is_empty()
			else:
				var kind := goal.kind
				check = func(w: WorldState) -> bool:
					return w.dummies.all(func(d: Dummy) -> bool: return d.kind != kind)
		Goal.Type.PARTY_DOWNED:
			check = func(w: WorldState) -> bool: return w.players_alive() == 0
		Goal.Type.CLEAR_ROOM:
			var to_clear: RoomPlan = goal.room
			check = func(w: WorldState) -> bool: return w.is_room_cleared(to_clear)
		Goal.Type.TIME_UP:
			world.time_up_tick = world.tick + goal.ticks
			check = func(w: WorldState) -> bool: return w.is_time_up()
		Goal.Type.ENTERED:
			# Only the current room's clear checks run.
			check = func(_w: WorldState) -> bool: return true
	return check


## Town, replacing [param previous] if any.
static func town(previous: WorldState = null) -> WorldState:
	return start(WorldLoader.town(), previous)


## The run, replacing [param previous], its random choices seeded.
static func run(previous: WorldState) -> WorldState:
	var plan := WorldLoader.first_run()
	var out := start(plan, previous)
	out.rng.seed = run_seed(plan.rng_seed)
	return out


## [param rng_seed] if it's set, else a new random seed.
static func run_seed(rng_seed: int) -> int:
	return rng_seed if rng_seed >= 0 else randi()


## Plays [param plan]; with none, an empty room with no doors that never ends.
## [param previous] is the world this one replaces: its tick carries over.
static func start(plan: RunPlan = null, previous: WorldState = null) -> WorldState:
	var world := WorldState.new()
	if previous:
		# Clients drop snapshots whose tick goes backwards.
		world.tick = previous.tick
		world.layout_number = previous.layout_number + 1
	world.run_plan = plan
	if plan and plan.start:
		_build_room(world, plan.start)
		world.spawn = plan.start.spawn
		world.spawn_facing = plan.start.spawn_facing
	_place_walls(world)
	if not plan:
		return world
	# After the tick carries over: a time limit counts from it.
	for goal in plan.win:
		world.win_checks.append(goal_check(goal, world))
	for goal in plan.lose:
		world.lose_checks.append(goal_check(goal, world))
	return world


## Moves the party into [param next]: as they left it if they've been
## there, else as its data lays it out. Shots in flight are gone.
static func enter_room(world: WorldState, next: RoomPlan) -> void:
	if world.rooms.has(next):
		world.room = world.rooms[next]
	else:
		_build_room(world, next)
	world.projectiles.clear()
	world.layout_number += 1
	_place_walls(world)


## Opens or shuts the current room's doors, with no heal: town's door opens
## only while everyone is ready.
static func set_room_cleared(world: WorldState, cleared: bool) -> void:
	if world.room.cleared == cleared:
		return
	world.room.cleared = cleared
	_place_walls(world)


static func _place_walls(world: WorldState) -> void:
	var data := WorldState.data
	world.walls.place(world.room, data.walls, data.floor_area, data.arena, _player_size())


## Freezes it with its outcome showing, until its time runs out
## [member WorldData.result_ticks] from now. A frozen world's tick still counts.
static func show_result(world: WorldState) -> void:
	world.frozen = true
	world.time_up_tick = world.tick + WorldState.data.result_ticks


## A new ID, unique within this world.
static func new_id(world: WorldState) -> int:
	world.last_id += 1
	return world.last_id


## Makes [param next] the current room, with its dummies placed.
static func _build_room(world: WorldState, next: RoomPlan) -> void:
	world.room = RoomState.new(WorldState.data.floor_area, WorldState.data.tile_size)
	world.rooms[next] = world.room
	world.room.doors = next.doors
	for goal in next.clear_goals:
		world.room.clear_checks.append(goal_check(goal, world))
	world.room.cleared = world.room.clear_checks.is_empty()
	for spot in next.spots:
		_add_dummy(world, spot.kind, spot.offset, spot.on_hit)


## A dummy of [param kind] at [param offset] from the arena's center, with
## that kind's attributes and [param on_hit] passed on.
static func _add_dummy(world: WorldState, kind: int, offset: Vector2, on_hit: String) -> Dummy:
	var d := WorldLoader.new_dummy(kind)
	d.id = new_id(world)
	d.on_hit = on_hit
	d.pos = WorldState.data.arena.get_center() + offset
	d.personal_space = WorldState.data.personal_space
	world.dummies.append(d)
	return d


## Advances [param world] one tick.
static func step(world: WorldState) -> void:
	world.tick += 1
	world.swing_contacts.clear()
	if world.frozen:
		return
	# Each offset is read before the step counts its push down, and applied
	# after, so a dummy's turn that swings a corner into a wall is caught too.
	# Every dummy steps before any moves, so each sees the others where they
	# were at the start of the tick, whatever their order.
	var offsets: Array[Vector2] = []
	var pushed: Array[bool] = []
	var firing: Array[bool] = []
	for d in world.dummies:
		offsets.append(d.offset_this_tick())
		pushed.append(d.is_pushed())
		var target := _nearest_living_player(world, d.pos)
		firing.append(d.step(target, world.dummies, world.room.paths, world.rng))
	for i in world.dummies.size():
		var d := world.dummies[i]
		if world.walls.move(d, offsets[i], pushed[i]) and d.state == Dummy.State.CHARGING:
			d.end_charge()
		if firing[i]:
			_fire(world, d)
	for p: Player in world.players.values():
		var offset := p.offset_this_tick()
		var player_pushed := p.is_pushed()
		p.step()
		world.walls.move(p, offset, player_pushed)
		if p.state == Player.State.SWINGING:
			_resolve_swing(world, p)
	_step_projectiles(world)
	world.dummies = world.dummies.filter(func(d: Dummy) -> bool: return not d.is_destroyed())
	_contact_damage(world)
	_check_cleared(world)
	_check_doorways(world)
	_check_outcome(world)


## Each tick of a swing, its active slice hits every dummy it touches that
## the swing hasn't hit yet (see [method Dummy.receive_hit]), and lists it in
## [member WorldState.swing_contacts].
static func _resolve_swing(world: WorldState, p: Player) -> void:
	var turn := WorldState.data.swing_turns[p.swing_ticks - p.state_ticks]
	var facing := Direction.to_vector(p.facing)
	var swing_start := p.pos + facing * WorldState.data.swing_offset
	var at := Transform2D(facing.angle() + turn, swing_start)
	for d in world.dummies:
		if d.id in p.swing_struck:
			continue
		var touched := func(piece: ConvexPolygonShape2D) -> bool: return d.touches(piece, at)
		if not WorldState.data.swing_pieces.any(touched):
			continue
		p.swing_struck.append(d.id)
		var contact := WorldState.SwingContact.new()
		contact.attacker_id = p.id
		contact.on_hit = d.on_hit
		world.swing_contacts.append(contact)
		d.receive_hit(WorldState.data.swing_damage, world.tick)
		if d.pushed_by_swings:
			var away := Body.direction_away(d.pos, p.pos, facing)
			_push(world, d, away * WorldState.data.knockback_px, WorldState.data.knockback_ticks)


## A shot from [param d] toward its locked aim.
static func _fire(world: WorldState, d: Dummy) -> void:
	var s := Projectile.new()
	s.id = new_id(world)
	s.pos = d.pos
	s.step = Body.direction_away(d.aim_spot, d.pos, d.facing) * d.fire.step
	s.radius = d.fire.radius
	s.damage = d.fire.damage
	s.push_px = d.fire.push_px
	s.push_ticks = d.fire.push_ticks
	world.projectiles.append(s)


## Moves every shot. One touching a raised shield is gone, harmlessly. One
## touching a living player hurts them (unless they're invulnerable) and
## pushes them straight away from it; it's gone either way, as is one
## touching a wall. Shots pass through dummies and downed players.
static func _step_projectiles(world: WorldState) -> void:
	var flying: Array[Projectile] = []
	for s in world.projectiles:
		var at_wall := world.walls.move(s, s.offset_this_tick())
		if _touches_a_shield(world, s):
			continue
		var struck := _living_player_touching(world, s)
		if struck:
			if struck.lose_health(s.damage):
				var dir := Body.direction_away(struck.pos, s.pos, Vector2.RIGHT)
				_push(world, struck, dir * s.push_px, s.push_ticks)
		elif not at_wall:
			flying.append(s)
	world.projectiles = flying


static func _touches_a_shield(world: WorldState, body: Body) -> bool:
	for p: Player in world.players.values():
		if p.shield and body.touches_body(p.shield):
			return true
	return false


## Null if no living player touches [param s].
static func _living_player_touching(world: WorldState, s: Projectile) -> Player:
	for p: Player in world.players.values():
		if not p.is_downed() and s.touches_body(p):
			return p
	return null


## Each dummy with contact damage hurts every player touching it who isn't
## invulnerable, and pushes them away (see [method Dummy.contact_push_direction]).
## One touching a player's raised shield pushes them without hurting them.
static func _contact_damage(world: WorldState) -> void:
	for d in world.dummies:
		if d.contact_damage == 0:
			continue
		for p: Player in world.players.values():
			var offset := d.contact_push_direction(p.pos) * d.contact_push_px
			if p.shield and d.touches_body(p.shield):
				if p.push_blocked(offset, d.contact_push_ticks):
					_move_if_instant(world, p, offset, d.contact_push_ticks)
			elif d.touches_body(p) and p.lose_health(d.contact_damage):
				_push(world, p, offset, d.contact_push_ticks)


## Starts a push on [param actor]; a 0-tick push moves it at once.
static func _push(world: WorldState, actor: Actor, offset: Vector2, ticks: int) -> void:
	if actor.push(offset, ticks):
		_move_if_instant(world, actor, offset, ticks)


## For a push [param actor] received: one of 0 ticks moves it at once, and
## any other moves it tick by tick as it steps.
static func _move_if_instant(world: WorldState, actor: Actor, offset: Vector2, ticks: int) -> void:
	if ticks == 0:
		world.walls.move(actor, offset, true)


## The living player nearest [param pos], by distance rounded down to
## [member WorldData.target_distance_step], ties going to the lower
## seat; null if nobody is alive. Dropped players count.
static func _nearest_living_player(world: WorldState, pos: Vector2) -> Player:
	var nearest: Player = null
	var nearest_steps := 0
	var ids := world.players.keys()
	ids.sort()
	for id: int in ids:
		var p := world.players[id]
		if p.is_downed():
			continue
		var steps := floori(pos.distance_to(p.pos) / WorldState.data.target_distance_step)
		if not nearest or steps < nearest_steps:
			nearest = p
			nearest_steps = steps
	return nearest


## Runs after this step's damage and before the outcome, so a clear that
## revives the party saves a run lost on the same step.
static func _check_cleared(world: WorldState) -> void:
	if world.room.cleared:
		return
	var met := func(check: Callable) -> bool: return check.call(world)
	if not world.room.clear_checks.any(met):
		return
	set_room_cleared(world, true)
	if WorldState.data.clear_heal:
		for p: Player in world.players.values():
			p.heal(WorldState.data.clear_heal_amount, WorldState.data.clear_heal_invulnerable)


## Wins are checked first, so a kill on the timer's last tick still wins.
static func _check_outcome(world: WorldState) -> void:
	var met := func(check: Callable) -> bool: return check.call(world)
	if world.win_checks.any(met):
		world.outcome = WorldState.Outcome.WON
	elif world.lose_checks.any(met):
		world.outcome = WorldState.Outcome.LOST


static func add_player(world: WorldState, id: int, connected := true) -> void:
	var p := Player.new()
	p.id = id
	# Its spot in the square the party would make now; the others stay where
	# they are. A new world's lobby places the whole party once it's in.
	var ids := world.players.keys()
	ids.append(id)
	p.pos = PartySquare.spots(ids, world.spawn, _player_size(), WorldState.data.floor_area)[id]
	p.facing = world.spawn_facing
	# Shared by every player: nothing changes a hurtbox.
	p.collider = WorldState.data.player_hurtbox
	p.max_health = WorldState.data.player_max_health
	p.health = WorldState.data.player_max_health
	p.walk_step = WorldState.data.walk_step
	p.swing_ticks = WorldState.data.swing_ticks
	p.swing_buffer_ticks = WorldState.data.swing_buffer_ticks
	p.invulnerable_duration_ticks = WorldState.data.invulnerable_duration_ticks
	p.connected = connected
	world.players[id] = p


static func remove_player(world: WorldState, id: int) -> void:
	world.players.erase(id)


## Gives player [param from] the ID [param to], which must be free. The
## character stays where it is.
static func renumber_player(world: WorldState, from: int, to: int) -> void:
	var p: Player = world.players.get(from)
	if p:
		world.players.erase(from)
		p.id = to
		world.players[to] = p


## A new connection starts with no move, nothing held and no press waiting.
static func set_connected(world: WorldState, id: int, connected: bool) -> void:
	var p: Player = world.players.get(id)
	if p:
		p.connected = connected
		p.reset_presses()


## Sets what using each of its item slots does, from [param items]: one per
## slot, null for an empty slot.
static func set_slot_items(world: WorldState, id: int, items: Array[EquipItem]) -> void:
	var p: Player = world.players.get(id)
	if p:
		var actions: Array[Action] = []
		actions.assign(items.map(WorldLoader.new_action))
		p.set_slot_actions(actions)


## It stops moving and lets go of every input action until its next input.
static func stop_player(world: WorldState, id: int) -> void:
	var p: Player = world.players.get(id)
	if p:
		p.move = Vector2.ZERO
		p.release_input_actions()


## [param presses] counts each input action's presses since the last input;
## [param held_bits] has a bit per input action held. A frozen world ignores
## it, so presses made while the result shows are dropped.
static func set_input(world: WorldState, id: int, move: Vector2, presses: PackedByteArray,
		held_bits: int) -> void:
	var p: Player = world.players.get(id)
	if p and not world.frozen:
		p.set_input(move, presses, held_bits)


## The first living player whose center is past the face of an open door's
## wall brings the party through it.
static func _check_doorways(world: WorldState) -> void:
	if not world.room.cleared:
		return
	for door in world.room.doors:
		var gap := door.wall.gap
		for p: Player in world.players.values():
			if not p.is_downed() and gap.has_point(p.pos):
				_go_through(world, door)
				return


## Puts the whole party in its square at the world's spawn, facing the
## spawn's way.
static func place_party(world: WorldState) -> void:
	var spots := PartySquare.spots(
			world.players.keys(), world.spawn, _player_size(), WorldState.data.floor_area)
	for id: int in spots:
		world.players[id].pos = spots[id]
		world.players[id].facing = world.spawn_facing


## Moves the party into the room [param door] leads to, in its square just
## inside the door they arrive by (see [method PartySquare.inside_door]),
## facing away from it.
static func _go_through(world: WorldState, door: RoomPlan.DoorPlan) -> void:
	enter_room(world, world.run_plan.rooms[door.leads_to])
	var spots := PartySquare.inside_door(
			world.players.keys(), door, _player_size(), WorldState.data.floor_area)
	for id: int in spots:
		world.players[id].pos = spots[id]
		world.players[id].facing = door.arrive_by.inward


## How big a player is, in px.
static func _player_size() -> Vector2:
	return WorldState.data.player_hurtbox.get_rect().size
