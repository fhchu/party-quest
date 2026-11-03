package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/tls"
	"io"
	"net"
	"testing"
	"time"

	"github.com/quic-go/quic-go"
	"github.com/quic-go/webtransport-go"
)

// fakeGame stands in for the Godot server: it sends a peer ID frame to each
// connection, then echoes every frame back. closed gets a value when a
// connection ends.
func fakeGame(t *testing.T) (addr string, closed chan struct{}) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	closed = make(chan struct{}, 1)
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				defer func() { conn.Close(); closed <- struct{}{} }()
				writeFrame(conn, []byte{kindPeerID, 42, 0, 0, 0})
				r := bufio.NewReader(conn)
				for {
					frame, err := readFrame(r)
					if err != nil || writeFrame(conn, frame) != nil {
						return
					}
				}
			}()
		}
	}()
	return ln.Addr().String(), closed
}

func dialRelay(t *testing.T, gameAddr string) *webtransport.Session {
	t.Helper()
	cert, _, err := selfSignedCert()
	if err != nil {
		t.Fatal(err)
	}
	conn, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := newServer(cert, gameAddr)
	go server.Serve(conn)
	t.Cleanup(func() { server.Close() })

	client := &webtransport.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		QUICConfig:      &quic.Config{EnableDatagrams: true, EnableStreamResetPartialDelivery: true},
	}
	t.Cleanup(func() { client.Close() })
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, sess, err := client.Dial(ctx, "https://"+conn.LocalAddr().String()+"/match", nil)
	if err != nil {
		t.Fatal(err)
	}
	return sess
}

func TestRelayCarriesFramesBothWays(t *testing.T) {
	gameAddr, closed := fakeGame(t)
	sess := dialRelay(t, gameAddr)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	stream, err := sess.AcceptStream(ctx)
	if err != nil {
		t.Fatal("relay didn't open the stream:", err)
	}
	r := bufio.NewReader(stream)
	expect := func(want []byte) {
		t.Helper()
		got, err := readFrame(r)
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(got, want) {
			t.Fatalf("stream frame = %v..., want %v...", got[:min(8, len(got))], want[:min(8, len(want))])
		}
	}
	expect([]byte{kindPeerID, 42, 0, 0, 0})

	reliable := []byte{kindReliable, 1, 2, 3}
	if err := writeFrame(stream, reliable); err != nil {
		t.Fatal(err)
	}
	expect(reliable)

	datagram := []byte{kindUnreliable, 9}
	if err := sess.SendDatagram(datagram); err != nil {
		t.Fatal(err)
	}
	got, err := sess.ReceiveDatagram(ctx)
	if err != nil || !bytes.Equal(got, datagram) {
		t.Fatalf("datagram = %v, %v; want %v", got, err, datagram)
	}

	// Too big for a datagram, so the echo comes back on the stream.
	big := append([]byte{kindOrdered}, make([]byte, 5000)...)
	if err := writeFrame(stream, big); err != nil {
		t.Fatal(err)
	}
	expect(big)

	sess.CloseWithError(0, "")
	select {
	case <-closed:
	case <-time.After(5 * time.Second):
		t.Fatal("game connection still open after the browser left")
	}
}

func TestRelayClosesTheSessionWhenTheGameServerCloses(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	go func() {
		conn, err := ln.Accept()
		if err == nil {
			writeFrame(conn, []byte{kindPeerID, 7, 0, 0, 0})
			conn.Close() // A kick.
		}
	}()
	sess := dialRelay(t, ln.Addr().String())
	select {
	case <-sess.Context().Done():
	case <-time.After(5 * time.Second):
		t.Fatal("session still open after the game server closed")
	}
}

func TestReadFrameRejectsBadLengths(t *testing.T) {
	for _, size := range []uint32{0, maxFrame + 1} {
		var buf bytes.Buffer
		buf.Write([]byte{byte(size), byte(size >> 8), byte(size >> 16), byte(size >> 24)})
		if _, err := readFrame(&buf); err != errBadFrame {
			t.Errorf("size %d: err = %v, want errBadFrame", size, err)
		}
	}
	if _, err := readFrame(bytes.NewReader(nil)); err != io.EOF {
		t.Errorf("empty: err = %v, want EOF", err)
	}
}
