extends RefCounted
## What the client knows of the game, apart from its connection: the lobby,
## the world it draws, your seat and your input. It never touches the
## network or the clock; client.gd hands it each message once it's decoded
## and queued, with the time.

const Snapshot := preload("res://net/snapshot.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Interpolator := preload("res://client/interpolator.gd")
const WorldView := preload("res://client/world_view.gd")
const GameView := preload("res://client/game_view.gd")
const GameTime := preload("res://shared/game_time.gd")
const ClientLoader := preload("res://client/client_loader.gd")

## Your seat; 0 before the server names it.
var player_id := 0
## Presses of attack since the welcome: the server counts from scratch per
## connection.
var attack_count := 0
var interpolator := Interpolator.new()
## Null until the server sends it. Kept while reconnecting, so the last
## picture stays up; cleared when turned away.
var lobby: LobbyState
## What's drawn: blended from two snapshots. Null before the first; frozen
## while reconnecting.
var drawn: WorldView

## When you last pressed anything, for the key prompts; -INF when you've
## just got control, so they show at once.
var _last_input_at := -INF
## Whether you could act last frame, and in which phase and world, to tell
## when you get control back.
var _could_act := false
var _acting_in := Vector2i(-1, -1)


## Whether seat [param my_id] has a character it can move right now: in the
## lobby, connected, not spectating, and not in the result. Death will join
## these.
static func can_act(in_lobby: LobbyState, my_id: int, connected: bool) -> bool:
	if not in_lobby or not connected or in_lobby.phase == LobbyState.Phase.RESULT:
		return false
	var mine := in_lobby.find_seat(my_id)
	return mine != null and mine.readiness != LobbyState.Readiness.SPECTATING


## The screen for seat [param my_seat] in [param in_lobby] (null before the
## first lobby state), drawing [param world]. [param connected] is whether
## the client holds a live connection that the server has welcomed.
## [param idle_sec] is how long you've had a character you can move without
## pressing anything: 0 while you can't move one, INF right after you get
## one back. It decides the key prompts.
static func build_view(
		in_lobby: LobbyState, my_seat: int, world: WorldView, connected: bool,
		idle_sec: float) -> GameView:
	var out := GameView.new()
	out.my_id = my_seat
	out.world = world
	out.show_prompts = idle_sec >= GameView.PROMPT_IDLE_SEC
	if not in_lobby:
		out.notice = GameView.CONNECTING_TEXT
		return out
	out.in_lobby = true
	out.waiting_for_ready = in_lobby.phase == LobbyState.Phase.TOWN and not in_lobby.all_ready
	if not connected:
		out.notice = GameView.RECONNECTING_TEXT
	elif in_lobby.phase == LobbyState.Phase.RESULT:
		out.notice = (GameView.WON_TEXT if in_lobby.outcome == LobbyState.Outcome.WON
				else GameView.LOST_TEXT)
	var ticks := world.run_ticks_left if world else WorldView.NO_TIMER
	# The lobby state says RUN a moment before the first run snapshot is
	# drawn, and town's snapshots carry no timer.
	if in_lobby.phase == LobbyState.Phase.RUN and ticks != WorldView.NO_TIMER:
		out.timer_text = format_time(ticks)
	for seat in in_lobby.seats:
		var card := GameView.Card.new()
		card.id = seat.id
		card.status_text = status_text(seat, in_lobby.phase)
		card.health = health_of(seat, world)
		card.max_health = ClientLoader.player_max_health
		card.ready = seat.readiness == LobbyState.Readiness.READY
		card.disconnected = (seat.presence == LobbyState.Presence.DROPPED
				or seat.id == my_seat and not connected)
		out.cards.append(card)
	return out


## [param snap] as the client draws it.
static func world_view_of(snap: Snapshot) -> WorldView:
	var out := WorldView.new()
	out.tick = snap.tick
	if snap.run_ticks_left != Snapshot.NO_TIMER:
		out.run_ticks_left = snap.run_ticks_left
	out.layout_number = snap.layout_number
	out.door_bits = snap.door_bits
	out.room_cleared = snap.room_cleared
	for sp in snap.players:
		var p := WorldView.Player.new()
		p.id = sp.id
		p.pos = sp.pos
		p.facing = sp.facing
		p.swing_ticks = sp.swing_ticks
		p.connected = sp.connected
		p.health = sp.health
		p.invulnerable = sp.invulnerable
		out.players.append(p)
	for sd in snap.dummies:
		var d := WorldView.Dummy.new()
		d.id = sd.id
		d.pos = sd.pos
		d.facing = sd.facing
		d.ticks_since_struck = sd.ticks_since_struck
		d.kind = sd.kind
		d.charge_windup_ticks_left = sd.charge_windup_ticks_left
		out.dummies.append(d)
	for ss in snap.projectiles:
		var s := WorldView.Projectile.new()
		s.id = ss.id
		s.pos = ss.pos
		s.radius = ss.radius
		out.projectiles.append(s)
	return out


## Minutes and seconds, rounded up, so 0:00 shows only once time is up.
static func format_time(ticks_left: int) -> String:
	var sec := ceili(GameTime.seconds(ticks_left))
	return "%d:%02d" % [floori(sec / 60.0), sec % 60]


## What [param seat]'s bar says: spectating for a late joiner, ready or not
## in town, nothing otherwise.
static func status_text(seat: LobbyState.Seat, phase: LobbyState.Phase) -> String:
	if seat.readiness == LobbyState.Readiness.SPECTATING:
		return GameView.SPECTATING_TEXT
	if phase == LobbyState.Phase.TOWN:
		return (GameView.READY_TEXT if seat.readiness == LobbyState.Readiness.READY
				else GameView.NOT_READY_TEXT)
	return ""


## [param seat]'s bar fill: full for a late joiner (no character) and before
## the first snapshot, else its health in [param world].
static func health_of(seat: LobbyState.Seat, world: WorldView) -> int:
	if seat.readiness == LobbyState.Readiness.SPECTATING:
		return ClientLoader.player_max_health
	var p: WorldView.Player = world.find_player(seat.id) if world else null
	return p.health if p else ClientLoader.player_max_health


## [param interp_fixed] gives a fixed drawing delay of [param interp_sec]
## instead of one that adapts.
func _init(interp_fixed: bool, interp_sec: float) -> void:
	interpolator.fixed = interp_fixed
	if interp_fixed:
		interpolator.delay_sec = interp_sec


func welcomed(id: int) -> void:
	player_id = id
	attack_count = 0


func lobby_received(state: LobbyState) -> void:
	lobby = state
	# A freed lobby seat moves everyone after it down one.
	if state.you:
		player_id = state.you


## Returns whether [param snap] was taken: false for one older than what's
## already in.
func snapshot_received(snap: Snapshot, now: float) -> bool:
	return interpolator.add(world_view_of(snap), now)


## The server turned this client away for good.
func rejected() -> void:
	lobby = null
	drawn = null


## The connection is gone and a new one is coming; the last picture stays.
func connection_lost() -> void:
	interpolator.reset()


func attack_pressed(now: float) -> void:
	attack_count += 1
	_last_input_at = now


func moved(now: float) -> void:
	_last_input_at = now


func update(now: float, delta: float) -> void:
	interpolator.update(now, delta)
	# Nothing new while reconnecting: the last picture stays.
	var latest := interpolator.view(now)
	if latest:
		drawn = latest


## The screen for this frame. [param connected] is whether the client holds
## a live connection that the server has welcomed. A [param notice] means
## the client can't play, and the screen shows only it. Call it every frame:
## it also notices when you get control back.
func view(now: float, connected: bool, notice := "") -> GameView:
	var can_act_now := can_act(lobby, player_id, connected)
	_note_control(can_act_now)
	if notice:
		return GameView.only_notice(notice)
	var idle_sec := now - _last_input_at if can_act_now else 0.0
	return build_view(lobby, player_id, drawn, connected, idle_sec)


## Resets the key prompts' timer whenever you get control of a character
## back: on joining, after the result, into a new run, and (later) on
## revival. [param can_act_now] is [method can_act] for this frame.
func _note_control(can_act_now: bool) -> void:
	var where := Vector2i(lobby.phase if lobby else -1, drawn.layout_number if drawn else -1)
	if can_act_now and (not _could_act or where != _acting_in):
		_last_input_at = -INF
	_could_act = can_act_now
	_acting_in = where
