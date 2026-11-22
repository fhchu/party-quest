extends SceneTree
## Prints how big a full lobby's snapshot is next to the datagram budget, so
## its growth shows in every ../check.sh run. tests/net/snapshot_codec_test.gd
## fails if it stops fitting.
##
## [code]godot --headless --path game -s res://tools/snapshot_size.gd[/code]

const GameTime := preload("res://shared/game_time.gd")
const SnapshotCodec := preload("res://net/snapshot_codec.gd")
const World := preload("res://sim/world.gd")
const Lobby := preload("res://server/lobby.gd")
const Room := preload("res://shared/data/room.gd")
const RunSetup := preload("res://shared/data/run_setup.gd")


## A full lobby in [param room], each player facing its own way and
## mid-swing, so every field carries something, and every shot that can be
## in the air at once.
static func full_lobby(room: Room) -> World:
	var w := World.new(World.WorldLoader.run_plan(room))
	for id in range(1, Lobby.MAX_PLAYERS + 1):
		w.add_player(id)
		w.set_input(id, Vector2.from_angle(id * World.Player.DIRECTION_STEP), 1)
	for i in ceili(World.data.swing_ticks / 2.0):
		w.step()
	for d in w.dummies:
		for i in max_shots_in_flight(d):
			var s := World.Projectile.new()
			s.pos = World.data.arena.get_center()
			s.radius = _slowest_shot(d).radius
			w.projectiles.append(s)
	return w


## The most shots of [param d]'s that can fly at once: one per interval, for
## as long as the slowest of its shots takes to cross the arena. 0 if it
## never fires.
static func max_shots_in_flight(d: World.Dummy) -> int:
	var slowest := _slowest_shot(d)
	if not slowest:
		return 0
	var flight_ticks := World.data.arena.size.length() / slowest.step
	return ceili(flight_ticks / d.attack_interval_ticks)


## Null if [param d] has no shot.
static func _slowest_shot(d: World.Dummy) -> World.Fire:
	var out: World.Fire = null
	for attack in d.attacks:
		if attack is World.Fire and (not out or attack.step < out.step):
			out = attack
	return out


## Every room [param setup] can put the party in.
static func rooms_of(setup: RunSetup) -> Array[Room]:
	var out: Array[Room] = [setup.start]
	for passage in setup.passages:
		for room: Room in [passage.from, passage.to]:
			if room not in out:
				out.append(room)
	return out


static func packed_size(w: World) -> int:
	return SnapshotCodec.pack(w.snapshot()).size()


func _initialize() -> void:
	var town := 0
	for room in rooms_of(World.WorldLoader.TOWN):
		town = maxi(town, packed_size(full_lobby(room)))
	var in_run := 0
	for room in rooms_of(World.WorldLoader.RUN):
		in_run = maxi(in_run, packed_size(full_lobby(room)))
	var worst := maxi(town, in_run)
	print("full lobby %d B (town %d, run %d) of %d B, %d%%" % [
		worst, town, in_run, SnapshotCodec.MAX_SIZE,
		roundi(100.0 * worst / SnapshotCodec.MAX_SIZE)])
	quit()
