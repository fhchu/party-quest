extends RefCounted
## Networking constants shared by server and client.

const TICK_RATE := 60
## In ticks: 20 snapshots/s.
const SNAPSHOT_EVERY := 3
## Match connections to the game server. Keep it private: only the relay and
## local bots should reach it.
const GAME_PORT := 9081
## WebTransport on UDP; the local-testing certificate hash on TCP.
const RELAY_PORT := 9080
const MAX_PLAYERS := 4

## The client reconnects after this long without a snapshot, to catch sockets
## that died without closing.
const STALE_AFTER_SEC := 3.0

## The client starts over after this long connecting, or joining without a
## welcome. Above the relay's 5 s dial limit, so a down game server shows as a
## lost connection.
const JOIN_TIMEOUT_SEC := 6.0

## The server stops a player whose client sends no input for this long. Inputs
## come every tick, so this rides out a burst of lost or late ones.
const INPUT_SILENCE_SEC := 0.25

## PLACEHOLDER (design): how long a dropped player's character waits for them
## to reconnect.
const RECONNECT_GRACE_SEC := 30.0
