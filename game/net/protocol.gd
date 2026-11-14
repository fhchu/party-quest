extends RefCounted
## Networking constants shared by server and client.

## Why the server turned a client away, sent in Net.reject. VERSION must stay
## first, at 0: it's the one reject an out-of-date client must still read.
enum RejectReason {
	VERSION,
	FULL,
	DUPLICATE_SESSION,
}

## Sent in hello; the server turns away any other, so a cached old web build
## can't join a newer server. Bump it whenever a message or the snapshot
## layout changes.
const PROTOCOL_VERSION := 11

# Any two free ports would do, for local runs. relay/main.go's flag defaults
# and the READMEs repeat them, so change them all together. Hosted, the relay
# is on 443 (deploy/entrypoint.sh, deploy/compose.yaml).

## Connections to the game server. Keep it private: only the relay and
## local bots should reach it.
const GAME_PORT := 9081
## WebTransport on UDP; on TCP, the web export and the local-testing
## certificate hash.
const RELAY_PORT := 9080
## Where on the relay game traffic goes. Must match gamePath in
## relay/main.go.
const GAME_PATH := "/game"
