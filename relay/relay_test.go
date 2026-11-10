package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/tls"
	"encoding/binary"
	"errors"
	"io"
	"net"
	"net/http"
	"testing"
	"time"

	"github.com/quic-go/quic-go"
	"github.com/quic-go/quic-go/http3"
	"github.com/quic-go/webtransport-go"
)

const (
	// testWait is how long a test waits for something that should happen at
	// once.
	testWait = 5 * time.Second
	// quicMaxPacket is quic-go's internal MaxPacketBufferSize. It never sends
	// a bigger UDP packet, so a frame this size can't be a datagram.
	quicMaxPacket = 1452
)

// peerIDFrame is the game server's first frame on a connection.
func peerIDFrame(id uint32) []byte {
	return binary.LittleEndian.AppendUint32([]byte{kindPeerID}, id)
}

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
				if err := writeFrame(conn, peerIDFrame(42)); err != nil {
					t.Errorf("fake game server: %v", err)
					return
				}
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
	sess, err := dialRelayFrom(t, gameAddr, "")
	if err != nil {
		t.Fatal(err)
	}
	return sess
}

// dialRelayFrom connects as a page from origin; empty sends no Origin, like a
// client that isn't a browser.
// startRelay serves the relay on a free local UDP port until the test ends.
func startRelay(t *testing.T, gameAddr string) net.Addr {
	t.Helper()
	cert, _, err := selfSignedCert()
	if err != nil {
		t.Fatal(err)
	}
	conn, err := net.ListenPacket("udp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := newServer(&tls.Config{Certificates: []tls.Certificate{cert}}, gameAddr, checkOrigin(nil))
	// Serve returns an error once the cleanup closes the server.
	go func() { _ = server.Serve(conn) }()
	t.Cleanup(func() { server.Close() })
	return conn.LocalAddr()
}

func dialRelayFrom(t *testing.T, gameAddr, origin string) (*webtransport.Session, error) {
	t.Helper()
	addr := startRelay(t, gameAddr)
	client := &webtransport.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		QUICConfig:      &quic.Config{EnableDatagrams: true, EnableStreamResetPartialDelivery: true},
	}
	t.Cleanup(func() { client.Close() })
	ctx, cancel := context.WithTimeout(context.Background(), testWait)
	defer cancel()
	header := http.Header{}
	if origin != "" {
		header.Set("Origin", origin)
	}
	_, sess, err := client.Dial(ctx, "https://"+addr.String()+"/match", header)
	return sess, err
}

func TestRelayCarriesFramesBothWays(t *testing.T) {
	gameAddr, closed := fakeGame(t)
	sess := dialRelay(t, gameAddr)
	ctx, cancel := context.WithTimeout(context.Background(), testWait)
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
	expect(peerIDFrame(42))

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

	// Too big for a datagram: the echo is dropped, and the next frame still
	// gets through.
	big := append([]byte{kindOrdered}, make([]byte, quicMaxPacket)...)
	if err := writeFrame(stream, big); err != nil {
		t.Fatal(err)
	}
	if err := writeFrame(stream, reliable); err != nil {
		t.Fatal(err)
	}
	expect(reliable)

	sess.CloseWithError(0, "")
	select {
	case <-closed:
	case <-time.After(testWait):
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
			if err := writeFrame(conn, peerIDFrame(7)); err != nil {
				t.Errorf("fake game server: %v", err)
			}
			conn.Close() // A kick.
		}
	}()
	sess := dialRelay(t, ln.Addr().String())
	select {
	case <-sess.Context().Done():
	case <-time.After(testWait):
		t.Fatal("session still open after the game server closed")
	}
}

// wtInitialMaxData is SETTINGS_WT_INITIAL_MAX_DATA from
// draft-ietf-webtrans-http3-14; webtransport-go doesn't export it.
const wtInitialMaxData = 0x2b61

// Safari opens no stream until the server advertises a stream-data limit
// (quic-go/webtransport-go#355).
func TestRelayAdvertisesStreamDataLimitForSafari(t *testing.T) {
	gameAddr, _ := fakeGame(t)
	addr := startRelay(t, gameAddr)
	ctx, cancel := context.WithTimeout(context.Background(), testWait)
	defer cancel()
	conn, err := quic.DialAddr(ctx, addr.String(),
		&tls.Config{InsecureSkipVerify: true, NextProtos: []string{http3.NextProtoH3}},
		&quic.Config{EnableDatagrams: true})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.CloseWithError(0, "") })
	cc := (&http3.Transport{}).NewClientConn(conn)
	select {
	case <-cc.ReceivedSettings():
	case <-ctx.Done():
		t.Fatal("no SETTINGS from the relay")
	}
	if cc.Settings().Other[wtInitialMaxData] == 0 {
		t.Error("relay doesn't advertise WT_INITIAL_MAX_DATA")
	}
}

func TestReadFrameRejectsBadLengths(t *testing.T) {
	for _, size := range []uint32{0, maxFrame + 1} {
		buf := bytes.NewReader(binary.LittleEndian.AppendUint32(nil, size))
		if _, err := readFrame(buf); !errors.Is(err, errBadFrame) {
			t.Errorf("size %d: err = %v, want errBadFrame", size, err)
		}
	}
	if _, err := readFrame(bytes.NewReader(nil)); !errors.Is(err, io.EOF) {
		t.Errorf("empty: err = %v, want EOF", err)
	}
}
