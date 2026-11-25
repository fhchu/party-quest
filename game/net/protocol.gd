extends RefCounted
## Networking constants shared by server and client.

## Why the server turned a client away, sent in Net.reject. VERSION must stay
## first, at 0: it's the one reject an out-of-date client must still read.
enum RejectReason {
	VERSION,
	FULL,
	DUPLICATE_SESSION,
}

## The project setting that holds the release's build ID.
## deploy/stamp-build.sh writes it for each release.
const BUILD_ID_SETTING := "application/config/version"

# Any two free ports would do, for local runs. Hosted, the relay is on 443
# (deploy/entrypoint.sh, deploy/compose.yaml).

## Connections to the game server. Keep it private: only the relay and
## local bots should reach it.
const GAME_PORT := 9081
## WebTransport on UDP; on TCP, the web export and the local-testing
## certificate hash.
const RELAY_PORT := 9080
## Where on the relay game traffic goes.
const GAME_PATH := "/game"

## How many input actions a client reports: one bit each in input_codec.gd's
## held byte.
const INPUT_ACTION_COUNT := 8
## The input actions a client reports, by index; the first ones use the item
## slots in order. Indexes from here up to [constant INPUT_ACTION_COUNT] are
## sent but mean nothing yet.
const INPUT_ACTIONS: Array[StringName] = [&"use_item_1", &"use_item_2"]
## Each input action's presses go out as a running count of this many bits,
## wrapping. More presses than it holds between two inputs the server gets
## would be lost, which no hand can do at the rate input is sent.
const PRESS_COUNTER_BITS := 4
const PRESS_COUNTER_MODULUS := 1 << PRESS_COUNTER_BITS


## The release tag this build came from, such as "v0.2.1", or "" when the
## build wasn't stamped. Sent in hello; the server turns away any other, so a
## tab left open on an old release can't join a newer server.
static func build_id() -> String:
	return ProjectSettings.get_setting(BUILD_ID_SETTING, "")
