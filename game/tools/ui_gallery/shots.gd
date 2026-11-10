extends RefCounted
## Every in-room screen in the states worth looking at, arena included, for
## the UI gallery ([code]ui-gallery.sh[/code]). Add a shot here with each new
## screen or state, so a UI change can be reviewed as pictures.

const Protocol := preload("res://net/protocol.gd")
const RoomState := preload("res://net/room_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Tuning := preload("res://sim/tuning.gd")
const World := preload("res://sim/world.gd")
const GameViewState := preload("res://client/ui/game_view_state.gd")

## A match timer partway through.
const MID_MATCH_SEC := 161
## How long the seat has been able to act without input: long enough that
## the prompts are back; none, as for a seat that can't act.
const IDLE_SEC := GameViewState.PROMPT_IDLE_SEC
const BUSY_SEC := 0.0
## Stands in for M2's room codes, so the corner can be reviewed.
const ROOM_CODE := "ABCD"
const LOBBY := RoomState.Phase.LOBBY
const MATCH := RoomState.Phase.MATCH
const RESULT := RoomState.Phase.RESULT
const HERE := RoomState.Presence.HERE
const DROPPED := RoomState.Presence.DROPPED
const NOT_READY := RoomState.Readiness.NOT_READY
const READY := RoomState.Readiness.READY
const SPECTATING := RoomState.Readiness.SPECTATING
# Where players stand in the shots, by seat number.
const TWO_SPOTS := { 1: Vector2(160, 230), 2: Vector2(470, 210) }
const THREE_SPOTS := { 1: Vector2(200, 230), 2: Vector2(450, 220), 3: Vector2(330, 280) }
const FOUR_SPOTS := {
	1: Vector2(205, 100),
	2: Vector2(300, 240),
	3: Vector2(120, 120),
	4: Vector2(500, 260),
}
## P1 touching the enemy.
const HURT_SPOTS := { 1: Vector2(305, 96), 2: Vector2(350, 140), 3: Vector2(120, 250) }


## In the order the gallery lays them out.
static func all() -> Array[Shot]:
	var shots: Array[Shot] = []
	shots.append_array(_lobby_shots())
	shots.append_array(_match_shots())
	shots.append(_shot("connecting", "Connecting, before you have a seat",
			GameViewState.build(null, 0, null, false, BUSY_SEC)))
	shots.append(_shot("rejected_full", "Turned away: room full",
			GameViewState.rejected(Protocol.RejectReason.FULL)))
	shots.append(_shot("rejected_duplicate_session", "Turned away: playing in another tab",
			GameViewState.rejected(Protocol.RejectReason.DUPLICATE_SESSION)))
	shots.append(_shot("rejected_version", "Turned away: old version",
			GameViewState.rejected(Protocol.RejectReason.VERSION)))
	shots.append(_shot("unsupported_browser", "Browser can't run the game",
			GameViewState.unsupported_browser()))
	return shots


static func _lobby_shots() -> Array[Shot]:
	var two := [_seat(1), _seat(2)]
	var mixed := [_seat(1, READY), _seat(2, READY), _seat(3, NOT_READY, DROPPED), _seat(4)]
	var everyone := [_seat(1, READY), _seat(2, READY), _seat(3, READY)]
	var four_view := _view(World.Layout.LOBBY, FOUR_SPOTS)
	var reconnecting := GameViewState.build(
			_room(LOBBY, mixed), 1, four_view, false, BUSY_SEC)
	reconnecting.room_code = ROOM_CODE
	return [
		_shot("lobby_joined", "Lobby, two players, nobody ready, prompts showing",
				_state(_room(LOBBY, two), 1, _view(World.Layout.LOBBY, TWO_SPOTS), IDLE_SEC)),
		_shot("lobby_dropped", "Lobby, P1 and P2 ready, P3 dropped (unreadied)",
				_state(_room(LOBBY, mixed), 1, four_view)),
		_shot("lobby_all_ready", "Lobby, everyone ready: START is live",
				_state(_room(LOBBY, everyone), 1, _view(World.Layout.LOBBY, THREE_SPOTS))),
		_shot("reconnecting", "Your connection dropped: frozen, your card d/c", reconnecting),
	]


static func _match_shots() -> Array[Shot]:
	var party := [_seat(1), _seat(2), _seat(3)]
	var late := [_seat(1), _seat(2), _seat(3, NOT_READY, DROPPED), _seat(4, SPECTATING)]
	var mid := MID_MATCH_SEC * Protocol.TICK_RATE
	var start_view := _view(World.Layout.MATCH, THREE_SPOTS, Tuning.match_ticks)
	var hurt := _view(World.Layout.MATCH, HURT_SPOTS, mid)
	hurt.players[0].health = Tuning.player_max_health - 1
	hurt.players[0].invulnerable_ticks = Tuning.player_invulnerable_ticks
	hurt.players[1].health = 0
	hurt.players[2].connected = false
	var won := _view(World.Layout.MATCH, THREE_SPOTS, mid)
	won.dummies.clear()
	var lost := _view(World.Layout.MATCH, THREE_SPOTS, 0)
	return [
		_shot("match_start", "Match start: one enemy, timer, prompts showing",
				_state(_room(MATCH, party), 1, start_view, IDLE_SEC)),
		_shot("match_late_joiner", "Mid-match, seen by a late joiner (P4): P1 hurt, P2 downed",
				_state(_room(MATCH, late), 4, hurt)),
		_shot("result_won", "Result: won",
				_state(_result(party, RoomState.Outcome.WON), 1, won)),
		_shot("result_lost", "Result: lost (time ran out)",
				_state(_result(party, RoomState.Outcome.LOST), 1, lost)),
	]


static func _shot(shot_name: String, caption: String, state: GameViewState) -> Shot:
	return Shot.new(shot_name, caption, state)


## What a connected seat [param my_id] sees. [param idle_sec] decides whether
## the prompts show; leave it at BUSY_SEC for a seat that can't act.
static func _state(
		room: RoomState, my_id: int, view: Snapshot, idle_sec := BUSY_SEC) -> GameViewState:
	var s := GameViewState.build(room, my_id, view, true, idle_sec)
	s.room_code = ROOM_CODE
	return s


## A snapshot of a fresh world in [param layout] with players at
## [param spots] (seat number to position).
static func _view(layout: World.Layout, spots: Dictionary, ticks_left := 0) -> Snapshot:
	var w := World.new(layout)
	for id: int in spots:
		w.add_player(id)
		w.players[id].pos = spots[id]
	var snap := w.snapshot()
	snap.match_ticks_left = ticks_left
	return snap


static func _room(phase: RoomState.Phase, seats: Array) -> RoomState:
	var state := RoomState.new()
	state.phase = phase
	state.seats.assign(seats)
	return state


static func _result(seats: Array, outcome: RoomState.Outcome) -> RoomState:
	var state := _room(RESULT, seats)
	state.outcome = outcome
	return state


static func _seat(
		id: int, readiness := NOT_READY, presence := HERE) -> RoomState.Seat:
	var s := RoomState.Seat.new()
	s.id = id
	s.readiness = readiness
	s.presence = presence
	return s


class Shot:
	## File name without extension: lowercase, digits and underscores.
	var name: String
	## One line saying what state this is, shown on the contact sheet.
	var caption: String
	var state: GameViewState

	func _init(p_name: String, p_caption: String, p_state: GameViewState) -> void:
		name = p_name
		caption = p_caption
		state = p_state
