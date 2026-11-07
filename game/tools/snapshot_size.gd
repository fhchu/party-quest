extends SceneTree
## Prints how big a full room's snapshot is next to the datagram budget, so
## its growth shows in every ../check.sh run. tests/net/snapshot_codec_test.gd
## fails if it stops fitting.
##
## [code]godot --headless --path game -s res://tools/snapshot_size.gd[/code]

const SnapshotCodec := preload("res://net/snapshot_codec.gd")
const World := preload("res://sim/world.gd")
const Tuning := preload("res://sim/tuning.gd")
const Protocol := preload("res://net/protocol.gd")


## A full room in [param layout], each player facing its own way and
## mid-swing, so every field carries something.
static func full_room(layout: World.Layout) -> World:
	var w := World.new(layout)
	for id in range(1, Protocol.MAX_PLAYERS + 1):
		w.add_player(id)
		w.set_input(id, Vector2.from_angle(id * World.DIRECTION_STEP), 1)
	for i in ceili(Tuning.swing_ticks / 2.0):
		w.step()
	return w


static func packed_size(w: World) -> int:
	return SnapshotCodec.pack(w.snapshot()).size()


func _initialize() -> void:
	var lobby := packed_size(full_room(World.Layout.LOBBY))
	var in_match := packed_size(full_room(World.Layout.MATCH))
	var worst := maxi(lobby, in_match)
	print("full room %d B (lobby %d, match %d) of %d B, %d%%" % [
		worst, lobby, in_match, SnapshotCodec.MAX_SIZE,
		roundi(100.0 * worst / SnapshotCodec.MAX_SIZE)])
	quit()
