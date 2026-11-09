extends RefCounted
## Everything the UI shows, worked out from the client's state in one place.
## The UI only reads it, so the gallery and tests can build one by hand
## without a network.

const Protocol := preload("res://net/protocol.gd")
const RoomState := preload("res://net/room_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const GameViewState := preload("res://client/ui/game_view_state.gd")

# PLACEHOLDER (design): the wording.
const CONNECTING_TEXT := "Connecting..."
const RECONNECTING_TEXT := "Attempting to reconnect..."
## One line per [enum Protocol.RejectReason].
const REJECTED_TEXTS := {
	Protocol.RejectReason.VERSION: "The game was updated. Reload the page.",
	Protocol.RejectReason.FULL: "Can't join: room is full",
	Protocol.RejectReason.DUPLICATE_SESSION: "You're playing in another tab.",
}
# Must match noBrotliText in relay/static.go, so players get one message
# whichever check fails.
const UNSUPPORTED_BROWSER_TEXT := (
		"Your browser is incompatible. Try using an updated version of Google Chrome.")
const WON_TEXT := "Victory"
const LOST_TEXT := "Defeat"
## PLACEHOLDER (design): how long without any input before the key prompts
## come back. Untuned.
const PROMPT_IDLE_SEC := 5.0

## Null while not in the room. Kept while reconnecting, so the last picture
## stays up.
var room: RoomState
## Your seat; 0 before the server names it.
var my_id := 0
## What the arena draws; null before the first snapshot.
var view: Snapshot
## False while your connection is down, which marks your own card "d/c".
var connected := true
## The line in the middle of the screen; empty for none.
var notice := ""
## Both groups of key prompts show and hide together.
var show_prompts := false
## Empty until rooms have codes.
var room_code := ""


## Builds the state from the client's. [param is_connected] is whether the
## client holds a live connection that the server has welcomed.
## [param idle_sec] is how long you've had a character you can move
## without pressing anything: 0 while you can't move one, INF right after
## you get one back. It decides the key prompts.
static func build(
		room_state: RoomState, my_seat: int, drawn: Snapshot, is_connected: bool,
		idle_sec: float) -> GameViewState:
	var s := GameViewState.new()
	s.my_id = my_seat
	s.connected = is_connected
	s.room = room_state
	s.view = drawn
	s.show_prompts = idle_sec >= PROMPT_IDLE_SEC
	if not room_state:
		s.notice = CONNECTING_TEXT
	elif not is_connected:
		s.notice = RECONNECTING_TEXT
	elif room_state.phase == RoomState.Phase.RESULT:
		s.notice = WON_TEXT if room_state.outcome == RoomState.Outcome.WON else LOST_TEXT
	return s


## The state once the server has turned the client away for good: only the
## notice.
static func rejected(reason: Protocol.RejectReason) -> GameViewState:
	var s := GameViewState.new()
	s.notice = REJECTED_TEXTS[reason]
	return s


## The state for a browser that can't run the game: only the notice.
static func unsupported_browser() -> GameViewState:
	var s := GameViewState.new()
	s.notice = UNSUPPORTED_BROWSER_TEXT
	return s
