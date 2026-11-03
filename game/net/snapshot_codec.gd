extends RefCounted
## Godot's own encoding of a snapshot is too big for one datagram (about 1,200
## bytes).
## [codeblock]
## tick u32, player count u8, dummy count u16
## player: id u32, pos 2×f32, facing u8 (which of World.DIRECTIONS),
##         swing_ticks u16, connected u8
## dummy:  pos 2×f32, flags u8 (FLAG_HIT, FLAG_TARGET)
## [/codeblock]

const Frames := preload("res://net/frames.gd")
const Snapshot := preload("res://net/snapshot.gd")
const World := preload("res://sim/world.gd")

# Sizes in bytes, field by field as above.
const HEADER_SIZE := 4 + 1 + 2
const PLAYER_SIZE := 4 + 2 * 4 + 1 + 2 + 1
const DUMMY_SIZE := 2 * 4 + 1

const FLAG_HIT := 1
const FLAG_TARGET := 2
## Godot's RPC header in front of a lone PackedByteArray argument, at most:
## flags u8, node ID u32 (u8 once cached), method ID u8.
const RPC_HEADER_MAX := 6
## The largest packed snapshot that still fits the datagram budget.
const MAX_SIZE := Frames.DATAGRAM_BUDGET - Frames.HEADER_MAX - RPC_HEADER_MAX


## Little-endian like Frames, with 32-bit floats.
static func pack(snap: Snapshot) -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u32(snap.tick)
	out.put_u8(snap.players.size())
	out.put_u16(snap.dummies.size())
	for p in snap.players:
		out.put_u32(p.id)
		out.put_float(p.pos.x)
		out.put_float(p.pos.y)
		out.put_u8(posmod(roundi(p.facing.angle() / World.DIRECTION_STEP), World.DIRECTIONS))
		out.put_u16(mini(p.swing_ticks, 0xFFFF))
		out.put_u8(int(p.connected))
	for d in snap.dummies:
		out.put_float(d.pos.x)
		out.put_float(d.pos.y)
		out.put_u8((FLAG_HIT if d.hit else 0) | (FLAG_TARGET if d.target else 0))
	return out.data_array


## Null for bytes that don't hold a whole snapshot.
static func unpack(bytes: PackedByteArray) -> Snapshot:
	if bytes.size() < HEADER_SIZE:
		return null
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var snap := Snapshot.new()
	snap.tick = buf.get_u32()
	var player_count := buf.get_u8()
	var dummy_count := buf.get_u16()
	if bytes.size() != HEADER_SIZE + player_count * PLAYER_SIZE + dummy_count * DUMMY_SIZE:
		return null
	# One field per line: the reads must happen in layout order.
	for i in player_count:
		var p := Snapshot.Player.new()
		p.id = buf.get_u32()
		p.pos.x = buf.get_float()
		p.pos.y = buf.get_float()
		p.facing = Vector2.from_angle(buf.get_u8() * World.DIRECTION_STEP)
		p.swing_ticks = buf.get_u16()
		p.connected = buf.get_u8() == 1
		snap.players.append(p)
	for i in dummy_count:
		var d := Snapshot.Dummy.new()
		d.pos.x = buf.get_float()
		d.pos.y = buf.get_float()
		var flags := buf.get_u8()
		d.hit = flags & FLAG_HIT != 0
		d.target = flags & FLAG_TARGET != 0
		snap.dummies.append(d)
	return snap
