extends RefCounted
## Packs snapshots small enough for one datagram, as few bytes as the values
## allow: Godot's own encoding wouldn't fit.
## [codeblock]
## tick u32, world_number u8, match_ticks_left u16, player count u8,
## dummy count u8
## player: id u8, pos 2×u16 (POS_SCALE), swing_ticks u8, health u8,
##         invulnerable_ticks u8, bits u8 (PLAYER_CONNECTED, facing from
##         FACING_SHIFT)
## dummy:  id u16, pos 2×u16 (POS_SCALE), kind u8, ticks_since_struck u8
## [/codeblock]
## tests/net/snapshot_codec_test.gd checks every value the game can produce
## fits its field.

const Frames := preload("res://net/frames.gd")
const Snapshot := preload("res://net/snapshot.gd")
const World := preload("res://sim/world.gd")

# Sizes in bytes, field by field as above.
const HEADER_SIZE := 4 + 1 + 2 + 1 + 1
const PLAYER_SIZE := 1 + 2 * 2 + 1 + 1 + 1 + 1
const DUMMY_SIZE := 2 + 2 * 2 + 1 + 1

## Positions are sent in 1/POS_SCALE px, as unsigned 16-bit numbers: far
## finer than a pixel, for an arena up to 0xffff / POS_SCALE px across.
const POS_SCALE := 32.0
const PLAYER_CONNECTED := 1
## Which of World.DIRECTIONS, above the player's flag bit.
const FACING_SHIFT := 1
## Godot's RPC header in front of a lone PackedByteArray argument, at most:
## flags u8, node ID u32 (u8 once cached), method ID u8.
const RPC_HEADER_MAX := 6
## The largest packed snapshot that still fits the datagram budget.
const MAX_SIZE := Frames.DATAGRAM_BUDGET - Frames.HEADER_MAX - RPC_HEADER_MAX


## Little-endian like Frames.
static func pack(snap: Snapshot) -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u32(snap.tick)
	out.put_u8(snap.world_number)
	out.put_u16(snap.match_ticks_left)
	out.put_u8(snap.players.size())
	out.put_u8(snap.dummies.size())
	for p in snap.players:
		out.put_u8(p.id)
		_put_pos(out, p.pos)
		out.put_u8(p.swing_ticks)
		out.put_u8(p.health)
		out.put_u8(p.invulnerable_ticks)
		var facing := posmod(roundi(p.facing.angle() / World.DIRECTION_STEP), World.DIRECTIONS)
		out.put_u8((PLAYER_CONNECTED if p.connected else 0) | facing << FACING_SHIFT)
	for d in snap.dummies:
		out.put_u16(d.id)
		_put_pos(out, d.pos)
		out.put_u8(d.kind)
		out.put_u8(d.ticks_since_struck)
	return out.data_array


## Null for bytes that don't hold a whole snapshot.
static func unpack(bytes: PackedByteArray) -> Snapshot:
	if bytes.size() < HEADER_SIZE:
		return null
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var snap := Snapshot.new()
	snap.packed_size = bytes.size()
	snap.tick = buf.get_u32()
	snap.world_number = buf.get_u8()
	snap.match_ticks_left = buf.get_u16()
	var player_count := buf.get_u8()
	var dummy_count := buf.get_u8()
	if bytes.size() != HEADER_SIZE + player_count * PLAYER_SIZE + dummy_count * DUMMY_SIZE:
		return null
	# One field per line: the reads must happen in layout order.
	for i in player_count:
		var p := Snapshot.Player.new()
		p.id = buf.get_u8()
		p.pos = _get_pos(buf)
		p.swing_ticks = buf.get_u8()
		p.health = buf.get_u8()
		p.invulnerable_ticks = buf.get_u8()
		var bits := buf.get_u8()
		p.connected = bits & PLAYER_CONNECTED != 0
		p.facing = Vector2.from_angle((bits >> FACING_SHIFT) * World.DIRECTION_STEP)
		snap.players.append(p)
	for i in dummy_count:
		var d := Snapshot.Dummy.new()
		d.id = buf.get_u16()
		d.pos = _get_pos(buf)
		d.kind = buf.get_u8()
		d.ticks_since_struck = buf.get_u8()
		snap.dummies.append(d)
	return snap


static func _put_pos(out: StreamPeerBuffer, pos: Vector2) -> void:
	out.put_u16(roundi(pos.x * POS_SCALE))
	out.put_u16(roundi(pos.y * POS_SCALE))


static func _get_pos(buf: StreamPeerBuffer) -> Vector2:
	var x := buf.get_u16() / POS_SCALE
	return Vector2(x, buf.get_u16() / POS_SCALE)
