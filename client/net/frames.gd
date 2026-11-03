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

enum Kind { RELIABLE, UNRELIABLE, ORDERED, PEER_ID }

## A peer claiming a longer frame is dropped, so a bad length can't use up memory.
const MAX_FRAME := 1 << 16
## The most a frame adds in front of a packet: kind u8, sequence u32.
const HEADER_MAX := 5
## The datagram size we design for. QUIC only guarantees 1,200-byte UDP
## packets; its own headers and encryption take 30 to 40 of that, and quic-go
## and Chrome each pick a limit per connection, so leave some slack below
## what's left. A frame over the real limit still arrives, on the stream.
const DATAGRAM_BUDGET := 1100


static func make(kind: Kind, payload: PackedByteArray) -> PackedByteArray:
	var frame := PackedByteArray([kind])
	frame.append_array(payload)
	return frame


static func prefixed(frame: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, frame.size())
	out.append_array(frame)
	return out


static func u32(value: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, value)
	return out


## Streams deliver bytes in arbitrary pieces; this holds them until a whole
## frame is in.
class Reader:
	var _buf := PackedByteArray()
	var failed := false

	func feed(bytes: PackedByteArray) -> void:
		_buf.append_array(bytes)

	## The next whole frame, or an empty array if it hasn't all arrived.
	func next() -> PackedByteArray:
		if failed or _buf.size() < 4:
			return PackedByteArray()
		var size := _buf.decode_u32(0)
		if size == 0 or size > MAX_FRAME:
			failed = true
			return PackedByteArray()
		if _buf.size() < 4 + size:
			return PackedByteArray()
		var frame := _buf.slice(4, 4 + size)
		_buf = _buf.slice(4 + size)
		return frame
