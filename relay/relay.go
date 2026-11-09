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

// Setting up a session normally takes milliseconds: the game server is on the
// same machine or network, and the browser accepts the stream as soon as the
// session is up. Taking far longer means the other end is gone; 5 s is
// generous.
const (
	gameDialTimeout   = 5 * time.Second
	openStreamTimeout = 5 * time.Second
)

// pipe copies frames between one browser and its game server connection until
// either side closes.
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

	pumps := []func() error{
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
		func() error {
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
							"datagrams take at most %d bytes", len(frame), tooLarge.MaxDatagramPayloadSize)
					} else if err != nil {
						return fmt.Errorf("browser datagrams: %w", err)
					}
					continue
				}
				if err := writeFrame(stream, frame); err != nil {
					return fmt.Errorf("browser stream: %w", err)
				}
			}
		},
	}
	// The first to end decides the error. A slot each, so the rest never block.
	done := make(chan error, len(pumps))
	for _, pump := range pumps {
		go func() { done <- pump() }()
	}
	return <-done
}
