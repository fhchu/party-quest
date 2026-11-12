extends SceneTree
## Prints how big a full lobby's snapshot is next to the datagram budget, so
## its growth shows in every ../check.sh run. tests/net/snapshot_codec_test.gd
## fails if it stops fitting.
##
## [code]godot --headless --path game -s res://tools/snapshot_size.gd[/code]

const Player := preload("res://sim/player.gd")
const GameTime := preload("res://shared/game_time.gd")
const SnapshotCodec := preload("res://net/snapshot_codec.gd")
const World := preload("res://sim/world.gd")
const Lobby := preload("res://server/lobby.gd")


## A full lobby in [param layout], each player facing its own way and
## mid-swing, so every field carries something, and every shot that can be
## in the air at once.
static func full_lobby(layout: World.Layout) -> World:
	var w := World.new(layout)
	for id in range(1, Lobby.MAX_PLAYERS + 1):
		w.add_player(id)
		w.set_input(id, Vector2.from_angle(id * World.DIRECTION_STEP), 1)
	for i in ceili(Player.swing_ticks / 2.0):
		w.step()
	for d in w.dummies:
		for i in max_shots_in_flight(d):
			var s := World.Projectile.new()
			s.pos = World.arena.get_center()
			s.radius = d.projectile_radius
			w.projectiles.append(s)
	return w


## The most shots of [param d]'s that can fly at once: one per interval, for
## as long as the longest flight across the arena takes. 0 if it never fires.
static func max_shots_in_flight(d: World.Dummy) -> int:
	if d.fire_interval_ticks == 0 or d.projectile_speed == 0:
		return 0
	var flight_ticks := World.arena.size.length() / (d.projectile_speed * GameTime.TICK_SEC)
	return ceili(flight_ticks / d.fire_interval_ticks)


static func packed_size(w: World) -> int:
	return SnapshotCodec.pack(w.snapshot()).size()


func _initialize() -> void:
	var town := packed_size(full_lobby(World.Layout.TOWN))
	var in_run := packed_size(full_lobby(World.Layout.RUN))
	var worst := maxi(town, in_run)
	print("full lobby %d B (town %d, run %d) of %d B, %d%%" % [
		worst, town, in_run, SnapshotCodec.MAX_SIZE,
		roundi(100.0 * worst / SnapshotCodec.MAX_SIZE)])
	quit()
