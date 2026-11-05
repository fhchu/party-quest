extends RefCounted
## Godot's own encoding of a snapshot is too big for one datagram (about 1,200
## bytes).
## [codeblock]
## tick u32, world_number u8, match_ticks_left u16, player count u8,
## dummy count u16
## player: id u32, pos 2×f32, facing u8 (which of World.DIRECTIONS),
##         swing_ticks u16, health u8, flags u8 (PLAYER_CONNECTED, PLAYER_INVULNERABLE)
## dummy:  pos 2×f32, bits u8 (DUMMY_FLASHING, kind from KIND_SHIFT)
## [/codeblock]

const Frames := preload("res://net/frames.gd")
const Snapshot := preload("res://net/snapshot.gd")
const World := preload("res://sim/world.gd")

# Sizes in bytes, field by field as above.
const HEADER_SIZE := 4 + 1 + 2 + 1 + 2
const PLAYER_SIZE := 4 + 2 * 4 + 1 + 2 + 1 + 1
const DUMMY_SIZE := 2 * 4 + 1

const PLAYER_CONNECTED := 1
const PLAYER_INVULNERABLE := 2
const DUMMY_FLASHING := 1
## The dummy's World.Kind, above its flashing bit.
const KIND_SHIFT := 1
## Godot's RPC header in front of a lone PackedByteArray argument, at most:
## flags u8, node ID u32 (u8 once cached), method ID u8.
const RPC_HEADER_MAX := 6
## The largest packed snapshot that still fits the datagram budget.
const MAX_SIZE := Frames.DATAGRAM_BUDGET - Frames.HEADER_MAX - RPC_HEADER_MAX


## Little-endian like Frames, with 32-bit floats.
static func pack(snap: Snapshot) -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u32(snap.tick)
	out.put_u8(snap.world_number)
	out.put_u16(snap.match_ticks_left)
	out.put_u8(snap.players.size())
	out.put_u16(snap.dummies.size())
	for p in snap.players:
		out.put_u32(p.id)
		out.put_float(p.pos.x)
		out.put_float(p.pos.y)
		out.put_u8(posmod(roundi(p.facing.angle() / World.DIRECTION_STEP), World.DIRECTIONS))
		out.put_u16(mini(p.swing_ticks, 0xffff))
		out.put_u8(p.health)
		out.put_u8((PLAYER_CONNECTED if p.connected else 0)
				| (PLAYER_INVULNERABLE if p.invulnerable else 0))
	for d in snap.dummies:
		out.put_float(d.pos.x)
		out.put_float(d.pos.y)
		out.put_u8((DUMMY_FLASHING if d.flashing else 0) | d.kind << KIND_SHIFT)
	return out.data_array


## Null for bytes that don't hold a whole snapshot.
static func unpack(bytes: PackedByteArray) -> Snapshot:
	if bytes.size() < HEADER_SIZE:
		return null
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var snap := Snapshot.new()
	snap.tick = buf.get_u32()
	snap.world_number = buf.get_u8()
	snap.match_ticks_left = buf.get_u16()
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
		p.health = buf.get_u8()
		var flags := buf.get_u8()
		p.connected = flags & PLAYER_CONNECTED != 0
		p.invulnerable = flags & PLAYER_INVULNERABLE != 0
		snap.players.append(p)
	for i in dummy_count:
		var d := Snapshot.Dummy.new()
		d.pos.x = buf.get_float()
		d.pos.y = buf.get_float()
		var bits := buf.get_u8()
		d.flashing = bits & DUMMY_FLASHING != 0
		d.kind = bits >> KIND_SHIFT
		snap.dummies.append(d)
	return snap
