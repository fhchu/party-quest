package main

import (
	"encoding/binary"
	"errors"
	"io"
)

// The game wire format, documented in game/net/frames.gd. Both must match.
const (
	kindReliable   = 0
	kindUnreliable = 1
	kindOrdered    = 2
	kindPeerID     = 3

	// maxFrame is the longest frame accepted, so a bad length can't use up
	// memory.
	maxFrame = 1 << 16

	// lengthSize is a stream frame's length prefix, a little-endian uint32.
	lengthSize = 4
)

var errBadFrame = errors.New("bad frame length")

func readFrame(r io.Reader) ([]byte, error) {
	var size [lengthSize]byte
	if _, err := io.ReadFull(r, size[:]); err != nil {
		return nil, err
	}
	n := binary.LittleEndian.Uint32(size[:])
	if n == 0 || n > maxFrame {
		return nil, errBadFrame
	}
	frame := make([]byte, n)
	if _, err := io.ReadFull(r, frame); err != nil {
		return nil, err
	}
	return frame, nil
}

// writeFrame writes the length and the frame in one call, so writers that
// share a connection under a lock never interleave.
func writeFrame(w io.Writer, frame []byte) error {
	buf := make([]byte, lengthSize+len(frame))
	binary.LittleEndian.PutUint32(buf, uint32(len(frame)))
	copy(buf[lengthSize:], frame)
	_, err := w.Write(buf)
	return err
}

// unordered reports whether a frame may travel as a datagram.
func unordered(frame []byte) bool {
	return frame[0] == kindUnreliable || frame[0] == kindOrdered
}
