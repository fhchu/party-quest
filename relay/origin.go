package main

import (
	"fmt"
	"net"
	"net/http"
	"net/url"
	"slices"
	"strings"
)

// originList is the -origin flag: the page origins allowed to open a match,
// such as https://lelize.com. It may be given more than once.
type originList []string

func (o *originList) String() string { return strings.Join(*o, ",") }

// Set adds one origin. It must be a bare scheme://host[:port], since that is
// all a browser's Origin header holds.
func (o *originList) Set(v string) error {
	u, err := url.Parse(v)
	if err != nil || u.Scheme == "" || u.Host == "" || (u.Path != "" && u.Path != "/") {
		return fmt.Errorf("origin %q: want scheme://host[:port]", v)
	}
	*o = append(*o, u.Scheme+"://"+u.Host)
	return nil
}

// checkOrigin returns the WebTransport origin check. A browser always sends
// the page's origin, and only pages from allowed may connect. With none
// allowed, only pages served from this machine (localhost and loopback
// addresses, any port) may, which covers local testing. A request with no
// Origin isn't from a browser page; the check exists to stop other sites'
// pages, so it's let through.
func checkOrigin(allowed []string) func(*http.Request) bool {
	return func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		if origin == "" {
			return true
		}
		if len(allowed) > 0 {
			return slices.Contains(allowed, origin)
		}
		u, err := url.Parse(origin)
		if err != nil {
			return false
		}
		host := u.Hostname()
		if host == "localhost" {
			return true
		}
		ip := net.ParseIP(host)
		return ip != nil && ip.IsLoopback()
	}
}
