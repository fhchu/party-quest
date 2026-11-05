extends Control
## In-game UI while in the room: the party bar along the bottom, the key
## prompts above it, the room code top left and the match timer top right.
## Drawn from a HudState only.

const Protocol := preload("res://net/protocol.gd")
const RoomState := preload("res://net/room_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Tuning := preload("res://sim/tuning.gd")
const HudState := preload("res://client/ui/hud_state.gd")
const PlayerCard := preload("res://client/ui/player_card.gd")
const KeyPrompts := preload("res://client/ui/key_prompts.gd")

@onready var _room_code: Label = %RoomCode
@onready var _timer: Label = %Timer
@onready var _prompts: KeyPrompts = %Prompts
var _cards: Array[PlayerCard] = []


## Minutes and seconds, rounded up, so 0:00 shows only once time is up.
static func format_time(ticks_left: int) -> String:
	var sec := ceili(float(ticks_left) / Protocol.TICK_RATE)
	return "%d:%02d" % [floori(sec / 60.0), sec % 60]


## The bar's fill for seat [param seat] of [param state]: empty for a late
## joiner (no character), the snapshot's health, or full before the first
## snapshot.
static func health_of(seat: RoomState.Seat, state: HudState) -> int:
	if seat.spectating:
		return 0
	var p: Snapshot.Player = state.view.find_player(seat.id) if state.view else null
	return p.health if p else Tuning.player_max_health


func _ready() -> void:
	_cards.assign(%PartyBar.get_children())
	assert(_cards.size() == Protocol.MAX_PLAYERS, "one card per seat")


func show_state(state: HudState) -> void:
	visible = state.room != null
	if not visible:
		return
	var room := state.room
	_room_code.text = state.room_code
	var in_match := room.phase == RoomState.Phase.MATCH
	var ticks := state.view.match_ticks_left if state.view else 0
	# Blank for 0: the room state says MATCH a moment before the first match
	# snapshot is drawn, and the lobby's snapshots carry no time.
	_timer.text = format_time(ticks) if in_match and ticks > 0 else ""
	_prompts.show_prompts(state.show_prompts)
	for i in _cards.size():
		var id := i + 1
		var seat := room.find_seat(id)
		var health := health_of(seat, state) if seat else 0
		var dropped := seat != null and (seat.presence == RoomState.Presence.DROPPED
				or id == state.my_id and not state.connected)
		_cards[i].show_seat(id, seat, room.phase, health, dropped)
