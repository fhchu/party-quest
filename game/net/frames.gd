extends RefCounted
## The match wire format. relay/frames.go must match it.
## [codeblock]
## frame:     kind u8, payload
## stream:    length u32 (little-endian), frame; repeated
## datagram:  one frame, no length
## RELIABLE, UNRELIABLE  payload = a Godot packet
## ORDERED               payload = sequence u32, a Godot packet
## PEER_ID               payload = peer ID u32; the server's first frame
## [/codeblock]

## The values are on the wire, so they're spelled out.
enum Kind { RELIABLE = 0, UNRELIABLE = 1, ORDERED = 2, PEER_ID = 3 }

## A longer claimed length drops the peer, so a bad length can't use up
## memory. Real frames are far smaller.
const MAX_FRAME := 1 << 16

# Sizes in bytes, from the layout above.
const KIND_SIZE := 1
const U32_SIZE := 4
const LENGTH_SIZE := U32_SIZE
const ORDERED_HEADER := KIND_SIZE + U32_SIZE
const PEER_ID_SIZE := KIND_SIZE + U32_SIZE
## The most a frame adds in front of a packet.
const HEADER_MAX := ORDERED_HEADER
## The datagram size we design for. QUIC guarantees only 1,200-byte packets,
## its own overhead takes 30 to 40 of that, and quic-go and Chrome each set a
## limit per connection, so this leaves slack. A bigger frame still arrives,
## on the stream.
const DATAGRAM_BUDGET := 1100


static func make(kind: Kind, payload: PackedByteArray) -> PackedByteArray:
	var frame := PackedByteArray([kind])
	frame.append_array(payload)
	return frame


static func prefixed(frame: PackedByteArray) -> PackedByteArray:
	var out := u32(frame.size())
	out.append_array(frame)
	return out


static func u32(value: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(U32_SIZE)
	out.encode_u32(0, value)
	return out


## Streams deliver bytes in arbitrary pieces; this holds them until a whole
## frame is in.
class Reader:
	## Set by a bad length. Nothing after it can be trusted.
	var failed := false
	var _buf := PackedByteArray()

	func feed(bytes: PackedByteArray) -> void:
		_buf.append_array(bytes)

	## The next whole frame, or an empty array if it hasn't all arrived.
	func next() -> PackedByteArray:
		if failed or _buf.size() < LENGTH_SIZE:
			return PackedByteArray()
		var size := _buf.decode_u32(0)
		if size == 0 or size > MAX_FRAME:
			failed = true
			return PackedByteArray()
		var end := LENGTH_SIZE + size
		if _buf.size() < end:
			return PackedByteArray()
		var frame := _buf.slice(LENGTH_SIZE, end)
		_buf = _buf.slice(end)
		return frame
