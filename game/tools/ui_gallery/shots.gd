extends RefCounted
## Every in-lobby screen in the states worth looking at, arena included, for
## the UI gallery ([code]ui-gallery.sh[/code]). Add a shot here with each new
## screen or state, so a UI change can be reviewed as pictures.

const Run := preload("res://server/run.gd")
const GameTime := preload("res://shared/game_time.gd")
const Protocol := preload("res://net/protocol.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Map := preload("res://shared/data/map.gd")
const RunSetup := preload("res://shared/data/run_setup.gd")
const World := preload("res://sim/world.gd")
const Lobby := preload("res://server/lobby.gd")
const GameViewState := preload("res://client/ui/game_view_state.gd")
const ArenaView := preload("res://client/arena_view.gd")

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
## P1 at the open north door, the others following.
const DOOR_SPOTS := { 1: Vector2(320, 26), 2: Vector2(300, 70), 3: Vector2(350, 90) }
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
	var four_view := _view(Lobby.TOWN, FOUR_SPOTS)
	var all_ready := _lobby(TOWN, everyone)
	all_ready.all_ready = true
	var reconnecting := GameViewState.build(
			_lobby(TOWN, mixed), 1, four_view, false, BUSY_SEC)
	reconnecting.lobby_code = LOBBY_CODE
	return [
		_shot("town_joined", "Town, two players, nobody ready, prompts showing",
				_state(_lobby(TOWN, two), 1, _view(Lobby.TOWN, TWO_SPOTS), IDLE_SEC)),
		_shot("town_all_ready", "Town, everyone ready: START is live",
				_state(all_ready, 1, _view(Lobby.TOWN, THREE_SPOTS))),
		_shot("reconnecting", "Your connection dropped: frozen, your card d/c", reconnecting),
	]


static func _run_shots() -> Array[Shot]:
	var party := [_seat(1), _seat(2), _seat(3)]
	var late := [_seat(1), _seat(2), _seat(3, NOT_READY, DROPPED), _seat(4, SPECTATING)]
	var mid := MID_RUN_SEC * GameTime.TICK_RATE
	var setup := Lobby.RUN
	var start_view := _view(setup.start, THREE_SPOTS, _run_start_ticks(), setup)
	# The second room's turret, so the shot has a shooter.
	var hurt := _view(setup.passages[0].to, HURT_SPOTS, mid, setup)
	hurt.players[0].health = World.player_max_health - 1
	hurt.players[0].invulnerable = true
	hurt.players[1].health = 0
	# Turned toward P3.
	hurt.dummies[0].facing = hurt.dummies[0].pos.direction_to(HURT_SPOTS[3])
	var shot := Snapshot.Projectile.new()
	shot.pos = hurt.dummies[0].pos.lerp(HURT_SPOTS[3], 0.5)
	shot.radius = preload("res://shared/data/dummy_kinds/turret.tres").projectile_radius
	hurt.projectiles.append(shot)
	hurt.players[2].connected = false
	var door_open := _view(setup.start, DOOR_SPOTS, mid, setup)
	door_open.dummies.clear()
	door_open.room_cleared = true
	var won := _view(setup.start, THREE_SPOTS, mid, setup)
	won.dummies.clear()
	won.room_cleared = true
	var lost := _view(setup.start, THREE_SPOTS, 0, setup)
	return [
		_shot("run_start", "Run start: one enemy, north door shut, timer, prompts showing",
				_state(_lobby(RUN, party), 1, start_view, IDLE_SEC)),
		_shot("run_late_joiner",
				"Mid-run, seen by a late joiner (P4): P1 hurt, P2 downed, enemy turned, a shot",
				_state(_lobby(RUN, late), 4, hurt)),
		_shot("run_charge_cue",
				"The charger about to charge P1: its cue at full length",
				_state(_lobby(RUN, party), 1, _charge_cue_view(mid))),
		_shot("run_door_open", "Room cleared: the north door is open, P1 at it",
				_state(_lobby(RUN, party), 1, door_open)),
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


## The first room's charger facing P1, halfway through the time its cue
## shows at full length.
static func _charge_cue_view(ticks_left: int) -> Snapshot:
	var view := _view(Lobby.RUN.start, THREE_SPOTS, ticks_left, Lobby.RUN)
	var charger := view.dummies[0]
	charger.facing = charger.pos.direction_to(THREE_SPOTS[1])
	var aim_lock_sec: float = World.DUMMY_KINDS.kinds[charger.kind].aim_lock_sec
	var grown := GameTime.seconds(GameTime.ticks(aim_lock_sec)) - ArenaView.CHARGE_CUE_GROW_SEC
	charger.charge_windup_ticks_left = (
			(grown + ArenaView.CHARGE_CUE_HIDE_SEC) / 2 * GameTime.TICK_RATE)
	return view


## The run's timer when it starts.
static func _run_start_ticks() -> int:
	return Lobby.fresh_world(Lobby.RUN.start, null, Lobby.RUN) \
			.snapshot().run_ticks_left


## A snapshot of a fresh world in [param map] with players at
## [param spots] (seat number to position), in [param run] if any.
static func _view(map: Map, spots: Dictionary,
		ticks_left := Snapshot.NO_TIMER, run: RunSetup = null) -> Snapshot:
	var w := Lobby.fresh_world(map, null, run)
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
