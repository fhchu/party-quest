// Command relay exists because Godot can't serve WebTransport. It accepts
// browsers and opens one framed TCP connection per player to the game server.
//
// Without -cert and -key it makes a self-signed certificate, which browsers
// accept only by hash, and serves the hash at http://<addr>/cert-hash.
package main

import (
	"crypto/tls"
	"flag"
	"log"
	"net"
	"net/http"
	"time"

	"github.com/quic-go/quic-go"
	"github.com/quic-go/quic-go/http3"
	"github.com/quic-go/webtransport-go"
)

func main() {
	// The defaults are GAME_PORT and RELAY_PORT in game/net/protocol.gd.
	addr := flag.String("addr", ":9080", "listen address: WebTransport on UDP, the certificate hash on TCP")
	game := flag.String("game", "127.0.0.1:9081", "the game server's match address (TCP)")
	certFile := flag.String("cert", "", "TLS certificate file; empty makes a self-signed one")
	keyFile := flag.String("key", "", "TLS key file")
	flag.Parse()

	var cert tls.Certificate
	var err error
	if *certFile != "" {
		cert, err = tls.LoadX509KeyPair(*certFile, *keyFile)
	} else {
		var hash string
		cert, hash, err = selfSignedCert()
		if err == nil {
			go serveCertHash(*addr, hash)
		}
	}
	if err != nil {
		log.Fatal(err)
	}

	conn, err := net.ListenPacket("udp", *addr)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("relaying https://%s/match to %s", *addr, *game)
	log.Fatal(newServer(cert, *game).Serve(conn))
}

const (
	// idleTimeout is how long a silent browser is kept before it counts as
	// gone. Untuned.
	idleTimeout = 15 * time.Second
	// keepAlivePeriod holds a hidden tab's connection open, since the tab
	// sends nothing. Three per idle timeout, so losing one or two doesn't drop
	// it; quic-go also caps it at half the idle timeout both ends agree on.
	keepAlivePeriod = idleTimeout / 3
)

func newServer(cert tls.Certificate, gameAddr string) *webtransport.Server {
	h3 := &http3.Server{
		TLSConfig: http3.ConfigureTLSConfig(&tls.Config{Certificates: []tls.Certificate{cert}}),
		QUICConfig: &quic.Config{
			EnableDatagrams: true,
			// Required by WebTransport.
			EnableStreamResetPartialDelivery: true,
			KeepAlivePeriod:                  keepAlivePeriod,
			MaxIdleTimeout:                   idleTimeout,
		},
	}
	webtransport.ConfigureHTTP3Server(h3)
	s := &webtransport.Server{
		H3: h3,
		// PLACEHOLDER (hosting): any page may connect. Restrict to the game's
		// own origin once it has one.
		CheckOrigin: func(*http.Request) bool { return true },
	}
	mux := http.NewServeMux()
	// game/client/client.gd builds this URL.
	mux.HandleFunc("/match", func(w http.ResponseWriter, r *http.Request) {
		sess, err := s.Upgrade(w, r)
		if err != nil {
			log.Printf("upgrade failed: %v", err)
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		log.Printf("%s connected", r.RemoteAddr)
		err = pipe(sess, gameAddr)
		log.Printf("%s closed: %v", r.RemoteAddr, err)
	})
	h3.Handler = mux
	return s
}

// serveCertHash lets any origin read the hash: the editor serves the game
// from another port.
func serveCertHash(addr, hash string) {
	mux := http.NewServeMux()
	mux.HandleFunc("/cert-hash", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Content-Type", "text/plain")
		w.Write([]byte(hash))
	})
	log.Printf("certificate hash at http://%s/cert-hash", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}
