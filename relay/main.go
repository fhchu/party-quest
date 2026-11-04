// Command relay is the game's one public server. Godot can't serve
// WebTransport, so the relay accepts browsers on UDP and opens one framed TCP
// connection per player to the game server. On TCP, at the same address, it
// serves the web export.
//
// Certificates: -domain gets one from Let's Encrypt; -cert and -key load one;
// with neither it makes a self-signed one, which browsers accept only by
// hash, serves the hash at http://<addr>/cert-hash, and serves TCP as plain
// HTTP for local testing.
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
	addr := flag.String("addr", ":9080", "listen address: WebTransport on UDP, the web side on TCP")
	game := flag.String("game", "127.0.0.1:9081", "the game server's match address (TCP)")
	domain := flag.String("domain", "", "get a Let's Encrypt certificate for this name; needs TCP 80 and 443 reachable from the internet")
	acmeCache := flag.String("acme-cache", "acme-cache", "with -domain: directory that keeps the certificate across restarts")
	httpAddr := flag.String("http", ":80", "with -domain: plain HTTP address for redirects and Let's Encrypt's checks")
	certFile := flag.String("cert", "", "TLS certificate file")
	keyFile := flag.String("key", "", "TLS key file")
	static := flag.String("static", "", "serve this directory (the web export) on TCP")
	var origins originList
	flag.Var(&origins, "origin", "a page origin allowed to open a match, such as https://lelize.com; repeatable (default: pages on this machine only)")
	flag.Parse()

	c, err := loadCerts(*domain, *acmeCache, *certFile, *keyFile)
	if err != nil {
		log.Fatal(err)
	}

	web := webServer(*addr, webHandler(*static, c.hash))
	if c.hash == "" {
		web.TLSConfig = c.tls
		go func() { log.Fatal(web.ListenAndServeTLS("", "")) }()
		log.Printf("serving https://%s", *addr)
	} else {
		go func() { log.Fatal(web.ListenAndServe()) }()
		log.Printf("serving http://%s, certificate hash at /cert-hash", *addr)
	}
	if c.acme != nil {
		// With no fallback handler, autocert redirects everything else to
		// HTTPS.
		redirect := webServer(*httpAddr, c.acme.HTTPHandler(nil))
		go func() { log.Fatal(redirect.ListenAndServe()) }()
	}

	conn, err := net.ListenPacket("udp", *addr)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("relaying https://%s/match to %s", *addr, *game)
	log.Fatal(newServer(c.tls, *game, checkOrigin(origins)).Serve(conn))
}

const (
	// idleTimeout is how long a silent browser is kept before it counts as
	// gone. Untuned.
	idleTimeout = 15 * time.Second
	// keepAlivePeriod holds a hidden tab's connection open, since the tab
	// sends nothing. Three per idle timeout, so losing one or two doesn't drop
	// it; quic-go also caps it at half the idle timeout both ends agree on.
	keepAlivePeriod = idleTimeout / 3
	// readHeaderTimeout stops a client that sends its request headers slowly
	// from holding a TCP connection forever. Untuned.
	readHeaderTimeout = 5 * time.Second
)

func newServer(tlsConf *tls.Config, gameAddr string, originOK func(*http.Request) bool) *webtransport.Server {
	h3 := &http3.Server{
		TLSConfig: http3.ConfigureTLSConfig(tlsConf),
		QUICConfig: &quic.Config{
			EnableDatagrams: true,
			// Required by WebTransport.
			EnableStreamResetPartialDelivery: true,
			KeepAlivePeriod:                  keepAlivePeriod,
			MaxIdleTimeout:                   idleTimeout,
		},
	}
	webtransport.ConfigureHTTP3Server(h3)
	s := &webtransport.Server{H3: h3, CheckOrigin: originOK}
	mux := http.NewServeMux()
	// game/client/client.gd builds this URL.
	mux.HandleFunc("/match", func(w http.ResponseWriter, r *http.Request) {
		sess, err := s.Upgrade(w, r)
		if err != nil {
			log.Printf("upgrade failed (origin %q): %v", r.Header.Get("Origin"), err)
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

// webHandler is what the relay serves on TCP: the web export when staticDir
// is set, and a self-signed certificate's hash when hash is set.
func webHandler(staticDir, hash string) http.Handler {
	mux := http.NewServeMux()
	if staticDir != "" {
		mux.Handle("/", staticHandler(staticDir))
	}
	if hash != "" {
		mux.HandleFunc("/cert-hash", func(w http.ResponseWriter, _ *http.Request) {
			// Any origin may read it: the editor serves the game from another
			// port.
			w.Header().Set("Access-Control-Allow-Origin", "*")
			w.Header().Set("Content-Type", "text/plain")
			// A failed write means the page went away; there's no one to tell.
			_, _ = w.Write([]byte(hash))
		})
	}
	return mux
}

func webServer(addr string, h http.Handler) *http.Server {
	return &http.Server{Addr: addr, Handler: h, ReadHeaderTimeout: readHeaderTimeout}
}
