extends RefCounted
## The balance values a client draws with, the same for every client of a
## release. The server sends them once, in Net.welcome, so only the server
## reads balance.json.
## [codeblock]
## arena: x f32, y f32, width f32, height f32
## player hurtbox: width f32, height f32
## dummy hurtbox: width f32, height f32
## player max health u8, swing point count u8
## swing point: x f32, y f32; repeated
## [/codeblock]

# Sizes in bytes, field by field as above.
const F32_SIZE := 4
const HEADER_SIZE := 4 * F32_SIZE + 2 * F32_SIZE + 2 * F32_SIZE + 1 + 1
const POINT_SIZE := 2 * F32_SIZE

var arena := Rect2()
## Centered on a player's position.
var player_hurtbox := Vector2.ZERO
## Every dummy's, centered on its position.
var dummy_hurtbox := Vector2.ZERO
var player_max_health := 0
## The swing's pie slice around its attacker, pointing along +x. It's the
## shape that hits, so drawing it shows exactly what a swing reaches.
var swing_arc := PackedVector2Array()


func to_bytes() -> PackedByteArray:
	var out := StreamPeerBuffer.new()
	out.put_float(arena.position.x)
	out.put_float(arena.position.y)
	out.put_float(arena.size.x)
	out.put_float(arena.size.y)
	out.put_float(player_hurtbox.x)
	out.put_float(player_hurtbox.y)
	out.put_float(dummy_hurtbox.x)
	out.put_float(dummy_hurtbox.y)
	out.put_u8(player_max_health)
	out.put_u8(swing_arc.size())
	for point in swing_arc:
		out.put_float(point.x)
		out.put_float(point.y)
	return out.data_array


## Fills this from [param bytes]. Returns false, changing nothing, for bytes
## that don't hold a whole ClientTuning.
func read(bytes: PackedByteArray) -> bool:
	if bytes.size() < HEADER_SIZE:
		return false
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	# One field per line: the reads must happen in layout order.
	var new_arena := Rect2(buf.get_float(), buf.get_float(), buf.get_float(), buf.get_float())
	var new_player_hurtbox := Vector2(buf.get_float(), buf.get_float())
	var new_dummy_hurtbox := Vector2(buf.get_float(), buf.get_float())
	var new_max_health := buf.get_u8()
	var count := buf.get_u8()
	if bytes.size() != HEADER_SIZE + count * POINT_SIZE:
		return false
	var new_arc := PackedVector2Array()
	for i in count:
		new_arc.append(Vector2(buf.get_float(), buf.get_float()))
	arena = new_arena
	player_hurtbox = new_player_hurtbox
	dummy_hurtbox = new_dummy_hurtbox
	player_max_health = new_max_health
	swing_arc = new_arc
	return true
