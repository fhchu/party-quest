package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"sync"
	"time"

	"github.com/quic-go/quic-go"
	"github.com/quic-go/webtransport-go"
)

// Setting up a session normally needs milliseconds: the game server is on the
// same machine or network, and the browser accepts the stream as soon as the
// session is up. Needing far longer means the other end is gone; 5 s is
// generous.
const (
	gameDialTimeout   = 5 * time.Second
	openStreamTimeout = 5 * time.Second
)

// pipe copies frames between one browser and its game server connection until
// either side closes. When the game server closes, see [finish].
//
// The relay opens the stream: one the browser opened wouldn't reach the relay
// until the browser wrote to it, and the browser writes nothing before the
// game server's first frame.
func pipe(sess *webtransport.Session, gameAddr string) error {
	ctx := sess.Context()
	defer sess.CloseWithError(0, "")
	game, err := net.DialTimeout("tcp", gameAddr, gameDialTimeout)
	if err != nil {
		return err
	}
	defer game.Close()
	openCtx, cancel := context.WithTimeout(ctx, openStreamTimeout)
	stream, err := sess.OpenStreamSync(openCtx)
	cancel()
	if err != nil {
		return fmt.Errorf("opening the stream: %w", err)
	}

	// The browser's stream and its datagrams both write to the game server.
	var gameMu sync.Mutex
	toGame := func(frame []byte) error {
		gameMu.Lock()
		defer gameMu.Unlock()
		return writeFrame(game, frame)
	}

	fromBrowser := []func() error{
		func() error {
			r := bufio.NewReader(stream)
			for {
				frame, err := readFrame(r)
				if err == nil {
					err = toGame(frame)
				}
				if err != nil {
					return fmt.Errorf("browser stream: %w", err)
				}
			}
		},
		func() error {
			for {
				frame, err := sess.ReceiveDatagram(ctx)
				if err != nil {
					return fmt.Errorf("browser datagrams: %w", err)
				}
				// Reliable frames must come on the stream, where they can't be lost.
				if len(frame) == 0 || len(frame) > maxFrame || !unordered(frame) {
					continue
				}
				if err := toGame(frame); err != nil {
					return fmt.Errorf("game server: %w", err)
				}
			}
		},
	}
	fromGame := func() error {
		r := bufio.NewReader(game)
		for {
			frame, err := readFrame(r)
			if err != nil {
				return fmt.Errorf("game server: %w", err)
			}
			if unordered(frame) {
				err := sess.SendDatagram(frame)
				// The game server keeps these frames under the datagram
				// budget (game/net/frames.gd), so a bigger one is its bug.
				var tooLarge *quic.DatagramTooLargeError
				if errors.As(err, &tooLarge) {
					log.Printf("error: dropped a %d-byte frame from the game server: "+
						"datagrams hold at most %d bytes", len(frame), tooLarge.MaxDatagramPayloadSize)
				} else if err != nil {
					return fmt.Errorf("browser datagrams: %w", err)
				}
				continue
			}
			if err := writeFrame(stream, frame); err != nil {
				return fmt.Errorf("browser stream: %w", err)
			}
		}
	}
	// The first to end decides the error. A slot each, so the rest never block.
	browserDone := make(chan error, len(fromBrowser))
	for _, pump := range fromBrowser {
		go func() { browserDone <- pump() }()
	}
	gameDone := make(chan error, 1)
	go func() { gameDone <- fromGame() }()
	select {
	case err := <-browserDone:
		return err
	case err := <-gameDone:
		return finish(ctx, stream, err)
	}
}

// finish ends the stream after the game server's last frame, then waits for
// the browser to close the session once it has read everything: closing the
// session here would reset the stream and drop frames not yet delivered, such
// as a reject. The game's browser client closes on reading the end of the
// stream (game/client/web_transport_peer.gd); one that doesn't is dropped
// after idleTimeout.
func finish(ctx context.Context, stream *webtransport.Stream, cause error) error {
	if err := stream.Close(); err != nil {
		return errors.Join(cause, err)
	}
	select {
	case <-ctx.Done():
	case <-time.After(idleTimeout):
	}
	return cause
}
