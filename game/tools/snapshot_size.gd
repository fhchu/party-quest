extends SceneTree
## Prints how big a full lobby's snapshot is next to the datagram budget, so
## its growth shows in every ../scripts/check.sh run. tests/net/snapshot_codec_test.gd
## fails if it stops fitting.
##
## [code]godot --headless --path game -s res://tools/snapshot_size.gd[/code]

const SnapshotCodec := preload("res://net/snapshot_codec.gd")
const WorldState := preload("res://sim/world_state.gd")
const WorldLoader := preload("res://sim/world_loader.gd")
const Fire := preload("res://sim/fire.gd")
const WorldSimulator := preload("res://sim/world_simulator.gd")
const WorldSnapshot := preload("res://sim/world_snapshot.gd")
const Lobby := preload("res://server/lobby.gd")
const Room := preload("res://shared/data/room.gd")
const RunSetup := preload("res://shared/data/run_setup.gd")
const Unit := preload("res://sim/unit.gd")
const Player := preload("res://sim/player.gd")
const Projectile := preload("res://sim/projectile.gd")
const EquipItem := preload("res://shared/data/items/equip_item.gd")
const SWORD: EquipItem = preload("res://shared/data/items/item_sword.tres")
const ActionSwing := preload("res://sim/action_swing.gd")


## A full lobby in [param room], each player facing its own way and
## mid-swing, so every field carries something, and every shot that can be
## in the air at once.
static func full_lobby(room: Room) -> WorldState:
	var w := WorldSimulator.start(WorldLoader.run_plan(room))
	for id in range(1, Lobby.MAX_PLAYERS + 1):
		WorldSimulator.add_player(w, id)
		WorldSimulator.set_slot_item(w, id, 0, SWORD)
		var facing := Vector2.from_angle(id * Player.DIRECTION_STEP)
		WorldSimulator.set_input(w, id, facing, PackedByteArray([1]), 0)
	var swing: ActionSwing = w.players[1].slot_actions[0]
	for i in ceili(swing.active_ticks / 2.0):
		WorldSimulator.step(w)
	for d in w.units:
		for i in max_shots_in_flight(d):
			var s := Projectile.new()
			s.pos = WorldState.data.arena.get_center()
			s.radius = _slowest_shot(d).radius
			w.projectiles.append(s)
	return w


## The most shots of [param d]'s that can fly at once: one per interval, for
## as long as the slowest of its shots needs to cross the arena. 0 if it
## never fires.
static func max_shots_in_flight(d: Unit) -> int:
	var slowest := _slowest_shot(d)
	if not slowest:
		return 0
	var flight_ticks := WorldState.data.arena.size.length() / slowest.step
	return ceili(flight_ticks / d.attack_interval_ticks)


## Null if [param d] has no shot.
static func _slowest_shot(d: Unit) -> Fire:
	var out: Fire = null
	for attack in d.attacks:
		if attack is Fire and (not out or attack.step < out.step):
			out = attack
	return out


## Every room [param setup] can put the party in.
static func rooms_of(setup: RunSetup) -> Array[Room]:
	var out: Array[Room] = [setup.start]
	for passage in setup.passages:
		for room: Room in [passage.from, passage.to]:
			if room and room not in out:
				out.append(room)
	return out


## Every room any level can put the party in.
static func level_rooms() -> Array[Room]:
	var out: Array[Room] = []
	for setup in WorldLoader.LEVELS.runs:
		out.append_array(rooms_of(setup))
	return out


static func packed_size(w: WorldState) -> int:
	return SnapshotCodec.pack(WorldSnapshot.of(w)).size()


func _initialize() -> void:
	var town := 0
	for room in rooms_of(WorldLoader.TOWN):
		town = maxi(town, packed_size(full_lobby(room)))
	var in_run := 0
	for room in level_rooms():
		in_run = maxi(in_run, packed_size(full_lobby(room)))
	var worst := maxi(town, in_run)
	print("full lobby %d B (town %d, run %d) of %d B, %d%%" % [
		worst, town, in_run, SnapshotCodec.MAX_SIZE,
		roundi(100.0 * worst / SnapshotCodec.MAX_SIZE)])
	quit()
