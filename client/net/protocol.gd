extends RefCounted
## Networking constants shared by server and client.

const TICK_RATE := 60
const SNAPSHOT_EVERY := 3  # ticks, so 20 snapshots/s
const DEFAULT_PORT := 9080
const MAX_PLAYERS := 4

## Client declares the connection dead after this long without a snapshot.
## Catches sockets that died without closing, e.g. when a laptop sleeps.
const STALE_AFTER_SEC := 3.0

## PLACEHOLDER (design): how long a dropped player's character stays in the
## match waiting for them to reconnect.
const RECONNECT_GRACE_SEC := 30.0
