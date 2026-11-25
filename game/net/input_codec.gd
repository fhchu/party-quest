extends RefCounted
## Packs a client's input into as few bytes as the values allow. Godot sends
## a lone PackedByteArray argument as raw bytes after its RPC header, with no
## type or length of its own.
## [codeblock]
## move 2×s8 (MOVE_SCALE), held u8 (a bit per input action),
## press counters INPUT_ACTION_COUNT × PRESS_COUNTER_BITS, packed from the
## lowest bit up
## [/codeblock]

const PlayerInput := preload("res://net/player_input.gd")
const Protocol := preload("res://net/protocol.gd")

## Each move axis is sent in steps of 1/MOVE_SCALE: the most a signed byte
## holds either way.
const MOVE_SCALE := 127.0
const HELD_AT := 2
const COUNTERS_AT := HELD_AT + 1
const SIZE := COUNTERS_AT + (Protocol.INPUT_ACTION_COUNT * Protocol.PRESS_COUNTER_BITS >> 3)
const COUNTER_MASK := Protocol.PRESS_COUNTER_MODULUS - 1


## [param press_counts] has a running count per input action, at most
## Protocol.INPUT_ACTION_COUNT of them; only each count's low bits are sent,
## so it wraps. [param held_bits] has a bit per input action.
static func pack(move: Vector2, press_counts: PackedInt32Array, held_bits: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(SIZE)
	out.encode_s8(0, roundi(clampf(move.x, -1.0, 1.0) * MOVE_SCALE))
	out.encode_s8(1, roundi(clampf(move.y, -1.0, 1.0) * MOVE_SCALE))
	out[HELD_AT] = held_bits
	for i in press_counts.size():
		var bit := i * Protocol.PRESS_COUNTER_BITS
		out[COUNTERS_AT + (bit >> 3)] |= (press_counts[i] & COUNTER_MASK) << (bit & 7)
	return out


## Null for bytes of the wrong length.
static func unpack(bytes: PackedByteArray) -> PlayerInput:
	if bytes.size() != SIZE:
		return null
	var out := PlayerInput.new()
	out.move = Vector2(bytes.decode_s8(0), bytes.decode_s8(1)) / MOVE_SCALE
	out.held_bits = bytes[HELD_AT]
	out.press_counters.resize(Protocol.INPUT_ACTION_COUNT)
	for i in Protocol.INPUT_ACTION_COUNT:
		var bit := i * Protocol.PRESS_COUNTER_BITS
		out.press_counters[i] = bytes[COUNTERS_AT + (bit >> 3)] >> (bit & 7) & COUNTER_MASK
	return out
