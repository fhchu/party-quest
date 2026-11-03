package main

import (
	"encoding/binary"
	"errors"
	"io"
)

// The match wire format, documented in client/net/frames.gd. Both must match.
const (
	kindReliable   = 0
	kindUnreliable = 1
	kindOrdered    = 2
	kindPeerID     = 3

	// A peer claiming a longer frame is dropped, so a bad length can't use up memory.
	maxFrame = 1 << 16
)

var errBadFrame = errors.New("bad frame length")

func readFrame(r io.Reader) ([]byte, error) {
	var size [4]byte
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
	buf := make([]byte, 4+len(frame))
	binary.LittleEndian.PutUint32(buf, uint32(len(frame)))
	copy(buf[4:], frame)
	_, err := w.Write(buf)
	return err
}

// unordered reports whether a frame may travel as a datagram.
func unordered(frame []byte) bool {
	return frame[0] == kindUnreliable || frame[0] == kindOrdered
}
