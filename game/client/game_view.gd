extends RefCounted
## Everything the screen shows: the world to draw, and what the lobby UI and
## the center notice say. Worked out from the client's state in one place;
## GameRenderer only reads it, so the gallery and tests can build one by hand
## without a network.

const Protocol := preload("res://net/protocol.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const GameView := preload("res://client/game_view.gd")

# PLACEHOLDER (design): the wording.
const CONNECTING_TEXT := "Connecting..."
const RECONNECTING_TEXT := "Attempting to reconnect..."
## One line per [enum Protocol.RejectReason].
const REJECTED_TEXTS := {
	Protocol.RejectReason.VERSION: "The game was updated. Reload the page.",
	Protocol.RejectReason.FULL: "Can't join: lobby is full",
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

## Null while not in the lobby. Kept while reconnecting, so the last picture
## stays up.
var lobby: LobbyState
## Your seat; 0 before the server names it.
var my_id := 0
## The world to draw; null before the first snapshot.
var view: Snapshot
## False while your connection is down, which marks your own card "d/c".
var connected := true
## The line in the middle of the screen; empty for none.
var notice := ""
## Both groups of key prompts show and hide together.
var show_prompts := false
## Empty until lobbies have codes.
var lobby_code := ""
## In town with someone not ready, so its door is shut and says why.
var waiting_for_ready := false


## Builds it from the client's state. [param welcomed] is whether the
## client holds a live connection that the server has welcomed.
## [param idle_sec] is how long you've had a character you can move
## without pressing anything: 0 while you can't move one, INF right after
## you get one back. It decides the key prompts.
static func build(
		lobby_state: LobbyState, my_seat: int, drawn: Snapshot, welcomed: bool,
		idle_sec: float) -> GameView:
	var s := GameView.new()
	s.my_id = my_seat
	s.connected = welcomed
	s.lobby = lobby_state
	s.view = drawn
	s.show_prompts = idle_sec >= PROMPT_IDLE_SEC
	s.waiting_for_ready = (lobby_state != null
			and lobby_state.phase == LobbyState.Phase.TOWN and not lobby_state.all_ready)
	if not lobby_state:
		s.notice = CONNECTING_TEXT
	elif not welcomed:
		s.notice = RECONNECTING_TEXT
	elif lobby_state.phase == LobbyState.Phase.RESULT:
		s.notice = WON_TEXT if lobby_state.outcome == LobbyState.Outcome.WON else LOST_TEXT
	return s


## The screen once the server has turned the client away for good: only
## the notice.
static func rejected(reason: Protocol.RejectReason) -> GameView:
	var s := GameView.new()
	s.notice = REJECTED_TEXTS[reason]
	return s


## The screen for a browser that can't run the game: only the notice.
static func unsupported_browser() -> GameView:
	var s := GameView.new()
	s.notice = UNSUPPORTED_BROWSER_TEXT
	return s
