extends RefCounted
## A world's state gathered for the wire: everything clients draw, from one
## tick.

const WorldState := preload("res://sim/world_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Player := preload("res://sim/player.gd")
const Dummy := preload("res://sim/dummy.gd")


## What [param world] sends this tick.
static func of(world: WorldState) -> Snapshot:
	var snap := Snapshot.new()
	snap.tick = world.tick
	snap.layout_number = world.layout_number
	snap.room_cleared = world.room.cleared
	snap.graphics_seed = world.room.graphics_seed
	for door in world.room.doors:
		snap.door_bits |= door.wall.door_bit
	if world.time_up_tick != WorldState.NO_TIME_LIMIT:
		snap.run_ticks_left = maxi(world.time_up_tick - world.tick, 0)
	for p: Player in world.players.values():
		var sp := Snapshot.Player.new()
		sp.id = p.id
		sp.pos = p.pos
		sp.facing = Direction.to_vector(p.facing)
		for action in p.slot_actions:
			var ticks := action.slot_ticks() if action else 0
			sp.slot_ticks.append(mini(ticks, Snapshot.SLOT_TICKS_MAX))
		sp.connected = p.connected
		sp.health = p.health
		sp.invulnerable = p.invulnerable_ticks > 0
		snap.players.append(sp)
	for d in world.dummies:
		var sd := Snapshot.Dummy.new()
		sd.id = d.id
		sd.pos = d.pos
		sd.facing = d.facing
		sd.ticks_since_struck = mini(world.tick - d.struck_tick, Snapshot.STRUCK_LONG_AGO)
		sd.kind = d.kind
		if d.is_aim_locked() and d.locked_attack == Dummy.Attack.CHARGE:
			sd.charge_windup_ticks_left = d.lock_ticks_left
		snap.dummies.append(sd)
	for s in world.projectiles:
		var ss := Snapshot.Projectile.new()
		ss.id = s.id
		ss.pos = s.pos
		ss.radius = s.radius
		snap.projectiles.append(ss)
	return snap
