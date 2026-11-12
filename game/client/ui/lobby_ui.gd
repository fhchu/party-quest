extends Control
## In-game UI while in the lobby: the party bar along the bottom, the key
## prompts above it, the lobby code top left and the run timer top right.
## Drawn from a GameViewState only.

const Protocol := preload("res://net/protocol.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Tuning := preload("res://sim/tuning.gd")
const GameViewState := preload("res://client/ui/game_view_state.gd")
const PlayerCard := preload("res://client/ui/player_card.gd")
const KeyPrompts := preload("res://client/ui/key_prompts.gd")

@onready var _lobby_code: Label = %LobbyCode
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
static func health_of(seat: LobbyState.Seat, state: GameViewState) -> int:
	if seat.readiness == LobbyState.Readiness.SPECTATING:
		return 0
	var p: Snapshot.Player = state.view.find_player(seat.id) if state.view else null
	return p.health if p else Tuning.player_max_health


func _ready() -> void:
	_cards.assign(%PartyBar.get_children())
	assert(_cards.size() == Protocol.MAX_PLAYERS, "one card per seat")


func show_state(state: GameViewState) -> void:
	visible = state.lobby != null
	if not visible:
		return
	var lobby := state.lobby
	_lobby_code.text = state.lobby_code
	var in_run := lobby.phase == LobbyState.Phase.RUN
	var ticks := state.view.run_ticks_left if state.view else 0
	# Blank for 0: the lobby state says RUN a moment before the first run
	# snapshot is drawn, and town's snapshots carry no time.
	_timer.text = format_time(ticks) if in_run and ticks > 0 else ""
	_prompts.show_prompts(state.show_prompts)
	for i in _cards.size():
		var id := i + 1
		var seat := lobby.find_seat(id)
		var health := health_of(seat, state) if seat else 0
		var dropped := seat != null and (seat.presence == LobbyState.Presence.DROPPED
				or id == state.my_id and not state.connected)
		_cards[i].show_seat(id, seat, lobby.phase, health, dropped)
