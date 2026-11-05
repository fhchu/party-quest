extends RefCounted
## Everything the UI shows, worked out from the client's state in one place.
## The UI only reads it, so the gallery and tests can build one by hand
## without a network.

const RoomState := preload("res://net/room_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const HudState := preload("res://client/ui/hud_state.gd")

# PLACEHOLDER (design): the wording.
const CONNECTING_TEXT := "Connecting..."
const RECONNECTING_TEXT := "Attempting to reconnect..."
const REJECTED_TEXT := "Can't join: %s"
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
## client holds a live connection that the server has welcomed;
## [param reject_reason] is empty unless the server turned it away for good.
## The key prompts start hidden; see [method set_prompts].
static func build(
		room_state: RoomState, my_seat: int, drawn: Snapshot, is_connected: bool,
		reject_reason: String) -> HudState:
	var s := HudState.new()
	s.my_id = my_seat
	s.connected = is_connected
	if reject_reason:
		s.notice = REJECTED_TEXT % reject_reason
		return s
	s.room = room_state
	s.view = drawn
	if not room_state:
		s.notice = CONNECTING_TEXT
	elif not is_connected:
		s.notice = RECONNECTING_TEXT
	elif room_state.phase == RoomState.Phase.RESULT:
		s.notice = WON_TEXT if room_state.outcome == RoomState.Outcome.WON else LOST_TEXT
	return s


## Shows the key prompts if you can act and have pressed nothing for
## [constant PROMPT_IDLE_SEC]. [param last_input_at] is on the same clock as
## [param now]; the client sets it to -INF whenever you get control back.
func set_prompts(now: float, last_input_at: float) -> void:
	show_prompts = can_act() and now - last_input_at >= PROMPT_IDLE_SEC


## Whether you have a character you can move right now: in the room,
## connected, not spectating, and not in the result. Death will join these.
func can_act() -> bool:
	if not room or not connected or room.phase == RoomState.Phase.RESULT:
		return false
	var mine := room.find_seat(my_id)
	return mine != null and not mine.spectating
