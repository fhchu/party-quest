package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"math/big"
	"net"
	"slices"
	"time"

	"golang.org/x/crypto/acme/autocert"
)

// certs is where the relay's TLS certificate comes from.
type certs struct {
	// tls serves both HTTPS on TCP and QUIC; http3 sets QUIC's protocol name.
	tls *tls.Config
	// hash is the base64 SHA-256 of a self-signed certificate, which a page
	// fetches to trust it. Empty for a real certificate.
	hash string
	// acme is set with -domain. Its HTTP handler answers Let's Encrypt's
	// checks on port 80.
	acme *autocert.Manager
}

// loadCerts picks the certificate source: a Let's Encrypt certificate for
// domain, kept in cacheDir; else the certFile and keyFile pair; else a
// self-signed certificate for local testing.
//
// With a domain, the relay asks Let's Encrypt for a certificate on the first
// HTTPS request, which agrees to its Subscriber Agreement on the operator's
// behalf, and renews it before it expires.
func loadCerts(domain, cacheDir, certFile, keyFile string) (certs, error) {
	switch {
	case domain != "":
		m := &autocert.Manager{
			Prompt:     autocert.AcceptTOS,
			HostPolicy: autocert.HostWhitelist(domain),
			Cache:      autocert.DirCache(cacheDir),
		}
		conf := m.TLSConfig()
		conf.GetCertificate = func(hello *tls.ClientHelloInfo) (*tls.Certificate, error) {
			return m.GetCertificate(withECDSASuite(hello))
		}
		return certs{tls: conf, acme: m}, nil
	case certFile != "":
		cert, err := tls.LoadX509KeyPair(certFile, keyFile)
		if err != nil {
			return certs{}, err
		}
		return certs{tls: &tls.Config{Certificates: []tls.Certificate{cert}}}, nil
	default:
		cert, hash, err := selfSignedCert()
		if err != nil {
			return certs{}, err
		}
		return certs{tls: &tls.Config{Certificates: []tls.Certificate{cert}}, hash: hash}, nil
	}
}

// withECDSASuite returns hello with a TLS 1.2 ECDSA cipher suite added when
// the client offers TLS 1.3. autocert serves its ECDSA certificate only to
// clients that list such a suite, and QUIC (WebTransport) offers TLS 1.3
// suites alone, so without this it would try to get an RSA certificate in
// the middle of the handshake and fail it. Every TLS 1.3 client supports
// ECDSA.
func withECDSASuite(hello *tls.ClientHelloInfo) *tls.ClientHelloInfo {
	if !slices.Contains(hello.SupportedVersions, tls.VersionTLS13) {
		return hello
	}
	h := *hello
	h.CipherSuites = append(slices.Clone(hello.CipherSuites),
		tls.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256)
	return &h
}

// certValidity stays under the 14-day limit below, with room for the hour
// NotBefore adds. game/README.md says to restart the relay this often.
const certValidity = 10 * 24 * time.Hour

// selfSignedCert makes a certificate browsers accept by hash
// (serverCertificateHashes), which requires ECDSA and a validity of at most 14
// days. It returns the base64 SHA-256 hash of the certificate.
func selfSignedCert() (tls.Certificate, string, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return tls.Certificate{}, "", err
	}
	now := time.Now()
	template := x509.Certificate{
		SerialNumber: big.NewInt(now.UnixNano()),
		Subject:      pkix.Name{CommonName: "localhost"},
		NotBefore:    now.Add(-time.Hour), // Allows for clock differences.
		NotAfter:     now.Add(certValidity),
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames:     []string{"localhost"},
		IPAddresses:  []net.IP{net.IPv4(127, 0, 0, 1), net.IPv6loopback},
	}
	der, err := x509.CreateCertificate(rand.Reader, &template, &template, &key.PublicKey, key)
	if err != nil {
		return tls.Certificate{}, "", err
	}
	sum := sha256.Sum256(der)
	cert := tls.Certificate{Certificate: [][]byte{der}, PrivateKey: key}
	return cert, base64.StdEncoding.EncodeToString(sum[:]), nil
}
