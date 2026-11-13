extends RefCounted
## Every in-lobby screen in the states worth looking at, arena included, for
## the UI gallery ([code]ui-gallery.sh[/code]). Add a shot here with each new
## screen or state, so a UI change can be reviewed as pictures.

const Run := preload("res://server/run.gd")
const GameTime := preload("res://shared/game_time.gd")
const Protocol := preload("res://net/protocol.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const DataLoader := preload("res://shared/data_loader.gd")
const World := preload("res://sim/world.gd")
const Lobby := preload("res://server/lobby.gd")
const GameViewState := preload("res://client/ui/game_view_state.gd")

## A run timer partway through.
const MID_RUN_SEC := 161
## How long the seat has been able to act without input: long enough that
## the prompts are back; none, as for a seat that can't act.
const IDLE_SEC := GameViewState.PROMPT_IDLE_SEC
const BUSY_SEC := 0.0
## PLACEHOLDER: M2's lobby codes, so the corner can be reviewed.
const LOBBY_CODE := "ABCD"
const TOWN := LobbyState.Phase.TOWN
const RUN := LobbyState.Phase.RUN
const RESULT := LobbyState.Phase.RESULT
const HERE := LobbyState.Presence.HERE
const DROPPED := LobbyState.Presence.DROPPED
const NOT_READY := LobbyState.Readiness.NOT_READY
const READY := LobbyState.Readiness.READY
const SPECTATING := LobbyState.Readiness.SPECTATING
# Where players are in the shots, by seat number.
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
	shots.append_array(_town_shots())
	shots.append_array(_run_shots())
	shots.append(_shot("connecting", "Connecting, before you have a seat",
			GameViewState.build(null, 0, null, false, BUSY_SEC)))
	shots.append(_shot("rejected_full", "Turned away: lobby full",
			GameViewState.rejected(Protocol.RejectReason.FULL)))
	shots.append(_shot("rejected_duplicate_session", "Turned away: playing in another tab",
			GameViewState.rejected(Protocol.RejectReason.DUPLICATE_SESSION)))
	shots.append(_shot("rejected_version", "Turned away: old version",
			GameViewState.rejected(Protocol.RejectReason.VERSION)))
	shots.append(_shot("unsupported_browser", "Browser can't run the game",
			GameViewState.unsupported_browser()))
	return shots


static func _town_shots() -> Array[Shot]:
	var two := [_seat(1), _seat(2)]
	var mixed := [_seat(1, READY), _seat(2, READY), _seat(3), _seat(4)]
	var everyone := [_seat(1, READY), _seat(2, READY), _seat(3, READY)]
	var four_view := _view(Lobby.TOWN_MAP, FOUR_SPOTS)
	var all_ready := _lobby(TOWN, everyone)
	all_ready.all_ready = true
	var reconnecting := GameViewState.build(
			_lobby(TOWN, mixed), 1, four_view, false, BUSY_SEC)
	reconnecting.lobby_code = LOBBY_CODE
	return [
		_shot("town_joined", "Town, two players, nobody ready, prompts showing",
				_state(_lobby(TOWN, two), 1, _view(Lobby.TOWN_MAP, TWO_SPOTS), IDLE_SEC)),
		_shot("town_all_ready", "Town, everyone ready: START is live",
				_state(all_ready, 1, _view(Lobby.TOWN_MAP, THREE_SPOTS))),
		_shot("reconnecting", "Your connection dropped: frozen, your card d/c", reconnecting),
	]


static func _run_shots() -> Array[Shot]:
	var party := [_seat(1), _seat(2), _seat(3)]
	var late := [_seat(1), _seat(2), _seat(3, NOT_READY, DROPPED), _seat(4, SPECTATING)]
	var mid := MID_RUN_SEC * GameTime.TICK_RATE
	var run_map := DataLoader.run(Lobby.RUN).start
	var start_view := _view(run_map, THREE_SPOTS, _run_start_ticks())
	var hurt := _view(run_map, HURT_SPOTS, mid)
	hurt.players[0].health = World.player_max_health - 1
	hurt.players[0].invulnerable = true
	hurt.players[1].health = 0
	# Turned toward P3.
	hurt.dummies[0].facing = hurt.dummies[0].pos.direction_to(HURT_SPOTS[3])
	var shot := Snapshot.Projectile.new()
	shot.pos = hurt.dummies[0].pos.lerp(HURT_SPOTS[3], 0.5)
	shot.radius = DataLoader.dummy_stats(DataLoader.dummy_kind("enemy")).projectile_radius
	hurt.projectiles.append(shot)
	hurt.players[2].connected = false
	var won := _view(run_map, THREE_SPOTS, mid)
	won.dummies.clear()
	var lost := _view(run_map, THREE_SPOTS, 0)
	return [
		_shot("run_start", "Run start: one enemy, timer, prompts showing",
				_state(_lobby(RUN, party), 1, start_view, IDLE_SEC)),
		_shot("run_late_joiner",
				"Mid-run, seen by a late joiner (P4): P1 hurt, P2 downed, enemy turned, a shot",
				_state(_lobby(RUN, late), 4, hurt)),
		_shot("result_won", "Result: won",
				_state(_result(party, LobbyState.Outcome.WON), 1, won)),
		_shot("result_lost", "Result: lost (time ran out)",
				_state(_result(party, LobbyState.Outcome.LOST), 1, lost)),
	]


static func _shot(shot_name: String, caption: String, state: GameViewState) -> Shot:
	return Shot.new(shot_name, caption, state)


## What a connected seat [param my_id] sees. [param idle_sec] decides whether
## the prompts show; leave it at BUSY_SEC for a seat that can't act.
static func _state(
		lobby: LobbyState, my_id: int, view: Snapshot, idle_sec := BUSY_SEC) -> GameViewState:
	var s := GameViewState.build(lobby, my_id, view, true, idle_sec)
	s.lobby_code = LOBBY_CODE
	return s


## The run's timer when it starts.
static func _run_start_ticks() -> int:
	var setup := DataLoader.run(Lobby.RUN)
	return World.new(DataLoader.map(setup.start), null, setup) \
			.snapshot().run_ticks_left


## A snapshot of a fresh world on [param map_name] with players at
## [param spots] (seat number to position).
static func _view(map_name: String, spots: Dictionary,
		ticks_left := Snapshot.NO_TIMER) -> Snapshot:
	var w := World.new(DataLoader.map(map_name))
	for id: int in spots:
		w.add_player(id)
		w.players[id].pos = spots[id]
	var snap := w.snapshot()
	snap.run_ticks_left = ticks_left
	return snap


static func _lobby(phase: LobbyState.Phase, seats: Array) -> LobbyState:
	var state := LobbyState.new()
	state.phase = phase
	state.seats.assign(seats)
	return state


static func _result(seats: Array, outcome: LobbyState.Outcome) -> LobbyState:
	var state := _lobby(RESULT, seats)
	state.outcome = outcome
	return state


static func _seat(
		id: int, readiness := NOT_READY, presence := HERE) -> LobbyState.Seat:
	var s := LobbyState.Seat.new()
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
