extends RefCounted
## Packs snapshots small enough for one datagram, as few bytes as the values
## allow: Godot's own encoding wouldn't fit.
## [codeblock]
## tick u32, world_number u8, run_ticks_left u16, player count u8,
## dummy count u8, projectile count u8
## player: id u8, pos 2×u16 (POS_SCALE), facing u8 (FACING_STEP),
##         swing_ticks u8, health u8, bits u8 (PLAYER_CONNECTED,
##         PLAYER_INVULNERABLE)
## dummy:  id u16, pos 2×u16 (POS_SCALE), facing u8 (FACING_STEP),
##         kind u8, ticks_since_struck u8
## projectile: id u16, pos 2×u16 (POS_SCALE), radius u8 (RADIUS_SCALE)
## [/codeblock]
## tests/net/snapshot_codec_test.gd checks every value the game can produce
## fits its field.

const Frames := preload("res://net/frames.gd")
const Snapshot := preload("res://net/snapshot.gd")

# Sizes in bytes, field by field as above.
const HEADER_SIZE := 4 + 1 + 2 + 1 + 1 + 1
const PLAYER_SIZE := 1 + 2 * 2 + 1 + 1 + 1 + 1
const DUMMY_SIZE := 2 + 2 * 2 + 1 + 1 + 1
const PROJECTILE_SIZE := 2 + 2 * 2 + 1

## Positions are sent in 1/POS_SCALE px, as unsigned 16-bit numbers: far
## finer than a pixel, for an arena up to 0xffff / POS_SCALE px across.
const POS_SCALE := 32.0
## A projectile's radius is sent in 1/RADIUS_SCALE px, up to 0xff /
## RADIUS_SCALE px.
const RADIUS_SCALE := 4.0
const PLAYER_CONNECTED := 1
const PLAYER_INVULNERABLE := 2
## Facing is sent as a byte: steps of about 1.4 degrees.
const FACING_STEP := TAU / 0x100
## Godot's RPC header in front of a lone PackedByteArray argument, at most:
## flags u8, node ID u32 (u8 once cached), method ID u8.
const RPC_HEADER_MAX := 6
## The largest packed snapshot that still fits the datagram budget.
const MAX_SIZE := Frames.DATAGRAM_BUDGET - Frames.HEADER_MAX - RPC_HEADER_MAX


## Little-endian like Frames.
static func pack(snap: Snapshot) -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_u32(snap.tick)
	# Clients only compare it with the last one, so wrapping is harmless.
	out.put_u8(snap.world_number & 0xff)
	out.put_u16(snap.run_ticks_left)
	out.put_u8(snap.players.size())
	out.put_u8(snap.dummies.size())
	out.put_u8(snap.projectiles.size())
	for p in snap.players:
		out.put_u8(p.id)
		_put_pos(out, p.pos)
		_put_facing(out, p.facing)
		out.put_u8(p.swing_ticks)
		out.put_u8(p.health)
		out.put_u8((PLAYER_CONNECTED if p.connected else 0)
				| (PLAYER_INVULNERABLE if p.invulnerable else 0))
	for d in snap.dummies:
		out.put_u16(d.id)
		_put_pos(out, d.pos)
		_put_facing(out, d.facing)
		out.put_u8(d.kind)
		out.put_u8(d.ticks_since_struck)
	for s in snap.projectiles:
		out.put_u16(s.id)
		_put_pos(out, s.pos)
		out.put_u8(roundi(s.radius * RADIUS_SCALE))
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
	snap.run_ticks_left = buf.get_u16()
	var player_count := buf.get_u8()
	var dummy_count := buf.get_u8()
	var projectile_count := buf.get_u8()
	if bytes.size() != (HEADER_SIZE + player_count * PLAYER_SIZE + dummy_count * DUMMY_SIZE
			+ projectile_count * PROJECTILE_SIZE):
		return null
	# One field per line: the reads must happen in layout order.
	for i in player_count:
		var p := Snapshot.Player.new()
		p.id = buf.get_u8()
		p.pos = _get_pos(buf)
		p.facing = _get_facing(buf)
		p.swing_ticks = buf.get_u8()
		p.health = buf.get_u8()
		var bits := buf.get_u8()
		p.connected = bits & PLAYER_CONNECTED != 0
		p.invulnerable = bits & PLAYER_INVULNERABLE != 0
		snap.players.append(p)
	for i in dummy_count:
		var d := Snapshot.Dummy.new()
		d.id = buf.get_u16()
		d.pos = _get_pos(buf)
		d.facing = _get_facing(buf)
		d.kind = buf.get_u8()
		d.ticks_since_struck = buf.get_u8()
		snap.dummies.append(d)
	for i in projectile_count:
		var s := Snapshot.Projectile.new()
		s.id = buf.get_u16()
		s.pos = _get_pos(buf)
		s.radius = buf.get_u8() / RADIUS_SCALE
		snap.projectiles.append(s)
	return snap


static func _put_pos(out: StreamPeerBuffer, pos: Vector2) -> void:
	out.put_u16(roundi(pos.x * POS_SCALE))
	out.put_u16(roundi(pos.y * POS_SCALE))


static func _get_pos(buf: StreamPeerBuffer) -> Vector2:
	var x := buf.get_u16() / POS_SCALE
	return Vector2(x, buf.get_u16() / POS_SCALE)


static func _put_facing(out: StreamPeerBuffer, facing: Vector2) -> void:
	out.put_u8(posmod(roundi(facing.angle() / FACING_STEP), 0x100))


static func _get_facing(buf: StreamPeerBuffer) -> Vector2:
	return Vector2.from_angle(buf.get_u8() * FACING_STEP)
