extends RefCounted
## Godot's own encoding of the snapshot arrays is too big for one datagram
## (about 1,200 bytes).
## [codeblock]
## tick u32, player count u8, dummy count u16
## player: id u32, pos 2×f32, facing u8 (eighths of a turn), swing_ticks u16,
##         connected u8
## dummy:  pos 2×f32, flags u8 (1 hit, 2 target)
## [/codeblock]
## Unpacking gives back the layout in net.gd.

const Frames := preload("res://net/frames.gd")

const PLAYER_SIZE := 16
const DUMMY_SIZE := 9
## Godot's RPC header in front of a lone PackedByteArray argument, at most:
## flags u8, node ID u32 (u8 once cached), method ID u8.
const RPC_HEADER_MAX := 6
## The largest packed snapshot that still fits the datagram budget.
const MAX_SIZE := Frames.DATAGRAM_BUDGET - Frames.HEADER_MAX - RPC_HEADER_MAX


static func pack(snap: Array) -> PackedByteArray:
	var players: Array = snap[1]
	var dummies: Array = snap[2]
	var out := PackedByteArray()
	out.resize(7 + players.size() * PLAYER_SIZE + dummies.size() * DUMMY_SIZE)
	out.encode_u32(0, snap[0])
	out.encode_u8(4, players.size())
	out.encode_u16(5, dummies.size())
	var at := 7
	for p: Array in players:
		out.encode_u32(at, p[0])
		out.encode_float(at + 4, p[1].x)
		out.encode_float(at + 8, p[1].y)
		out.encode_u8(at + 12, posmod(roundi(p[2].angle() / (PI / 4)), 8))
		out.encode_u16(at + 13, mini(p[3], 0xFFFF))
		out.encode_u8(at + 15, int(p[4]))
		at += PLAYER_SIZE
	for d: Array in dummies:
		out.encode_float(at, d[0].x)
		out.encode_float(at + 4, d[0].y)
		out.encode_u8(at + 8, int(d[1]) | int(d[2]) << 1)
		at += DUMMY_SIZE
	return out


## Returns an empty array for bytes that don't hold a whole snapshot.
static func unpack(bytes: PackedByteArray) -> Array:
	if bytes.size() < 7:
		return []
	var player_count := bytes.decode_u8(4)
	var dummy_count := bytes.decode_u16(5)
	if bytes.size() != 7 + player_count * PLAYER_SIZE + dummy_count * DUMMY_SIZE:
		return []
	var players := []
	var at := 7
	for i in player_count:
		players.append([
			bytes.decode_u32(at),
			Vector2(bytes.decode_float(at + 4), bytes.decode_float(at + 8)),
			Vector2.from_angle(bytes.decode_u8(at + 12) * PI / 4),
			bytes.decode_u16(at + 13),
			bytes.decode_u8(at + 15) == 1,
		])
		at += PLAYER_SIZE
	var dummies := []
	for i in dummy_count:
		var flags := bytes.decode_u8(at + 8)
		dummies.append([
			Vector2(bytes.decode_float(at), bytes.decode_float(at + 4)),
			flags & 1 != 0,
			flags & 2 != 0,
		])
		at += DUMMY_SIZE
	return [bytes.decode_u32(0), players, dummies]
