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
const PROTOCOL_VERSION := 8
## Simulation steps per second, on the server and in each client's input
## loop. Balance values are in seconds, so changing it changes no tuning.
## Must be a multiple of [constant SNAPSHOT_RATE].
const TICK_RATE := 30
## Snapshots sent per second, a first guess at bandwidth against smoothness.
## Independent of the tick rate: a faster simulation needn't cost bandwidth.
const SNAPSHOT_RATE := 30
## In ticks. tests/net/protocol_test.gd checks it divides evenly.
@warning_ignore("integer_division")
const SNAPSHOT_EVERY := TICK_RATE / SNAPSHOT_RATE
## What the server actually sends at, even if the rates don't divide.
const SNAPSHOT_INTERVAL_SEC := float(SNAPSHOT_EVERY) / TICK_RATE

# Any two free ports would do, for local runs. relay/main.go's flag defaults
# and the READMEs repeat them, so change them all together. Hosted, the relay
# is on 443 (deploy/entrypoint.sh, deploy/compose.yaml).

## Match connections to the game server. Keep it private: only the relay and
## local bots should reach it.
const GAME_PORT := 9081
## WebTransport on UDP; on TCP, the web export and the local-testing
## certificate hash.
const RELAY_PORT := 9080
## Where on the relay match traffic goes. Must match matchPath in
## relay/main.go.
const MATCH_PATH := "/match"
