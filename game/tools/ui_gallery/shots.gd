extends RefCounted
## Every in-lobby screen in the states worth looking at, arena included, for
## the UI gallery ([code]ui-gallery.sh[/code]). Add a shot here with each new
## screen or state, so a UI change can be reviewed as pictures.

const Run := preload("res://server/run.gd")
const Protocol := preload("res://net/protocol.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Room := preload("res://shared/data/room.gd")
const RunSetup := preload("res://shared/data/run_setup.gd")
const WorldState := preload("res://sim/world_state.gd")
const WorldLoader := preload("res://sim/world_loader.gd")
const WorldSimulator := preload("res://sim/world_simulator.gd")
const WorldSnapshot := preload("res://sim/world_snapshot.gd")
const Lobby := preload("res://server/lobby.gd")
const GameView := preload("res://client/game_view.gd")
const ClientState := preload("res://client/client_state.gd")
const ClientLoader := preload("res://client/client_loader.gd")
const TouchControls := preload("res://client/ui/touch_controls.gd")
const InputState := preload("res://client/input_state.gd")
const Client := preload("res://client/client.gd")
const WorldRenderer := preload("res://client/world_renderer.gd")
const UnitType := preload("res://shared/data/unit_type.gd")
const AttackFire := preload("res://shared/data/attacks/attack_fire.gd")
const Items := preload("res://shared/data/items.gd")
const Item := preload("res://shared/data/item.gd")
const ITEMS: Items = preload("res://shared/data/items.tres")
const SWORD: Item = preload("res://shared/data/items/item_sword.tres")
const SHIELD: Item = preload("res://shared/data/items/item_shield.tres")
const TURRET_TYPE := preload("res://shared/data/units/unit_turret.tres")
const BOSS_TYPE := preload("res://shared/data/units/unit_boss.tres")

## Every shot's floor is drawn from this one graphics seed, so the floor
## looks the same from one run of the gallery to the next and only what a
## change touches differs.
const GRAPHICS_SEED := 67
## A run timer partway through.
const MID_RUN_SEC := 161
## Gold the seats in the won result have earned: a few runs' worth, so the
## label shows a number other than one run's.
const EARNED_GOLD := 3
# What the HUD shows under the timer: fps in every shot, ping while connected.
const SHOT_FPS := 60
const SHOT_PING_MS := 42
const TOWN := LobbyState.Phase.TOWN
const RUN := LobbyState.Phase.RUN
const RESULT := LobbyState.Phase.RESULT
const HERE := LobbyState.Connection.HERE
const DROPPED := LobbyState.Connection.DROPPED
const NOT_READY := LobbyState.Participation.NOT_READY
const READY := LobbyState.Participation.READY
const SPECTATING := LobbyState.Participation.SPECTATING
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
## Where the thumb lands on the joystick, and how far it pushes from there.
const THUMB_DOWN := Vector2(90, 270)
const THUMB_PUSH := Vector2(28, -20)
## P1 touching the enemy.
const HURT_SPOTS := { 1: Vector2(305, 96), 2: Vector2(350, 140), 3: Vector2(120, 250) }


## In the order the gallery lays them out.
static func all() -> Array[Shot]:
	var shots: Array[Shot] = []
	shots.append_array(_town_shots())
	shots.append_array(_shield_shots())
	shots.append_array(_level_select_shots())
	shots.append_array(_run_shots())
	shots.append(_shot("connecting", "Connecting, before you have a seat",
			ClientState.build_view(null, 0, null, false)))
	shots.append(_shot("rejected_full", "Turned away: lobby full",
			GameView.only_notice(Client.REJECTED_TEXTS[Protocol.RejectReason.FULL])))
	shots.append(_shot("rejected_duplicate_session", "Turned away: playing in another tab",
			GameView.only_notice(Client.REJECTED_TEXTS[Protocol.RejectReason.DUPLICATE_SESSION])))
	shots.append(_shot("rejected_version", "Turned away: old version",
			GameView.only_notice(Client.REJECTED_TEXTS[Protocol.RejectReason.VERSION])))
	shots.append(_shot("unsupported_browser", "Browser can't run the game",
			GameView.only_notice(Client.UNSUPPORTED_BROWSER_TEXT)))
	return shots


static func _town_shots() -> Array[Shot]:
	var two := [_seat(1), _seat(2)]
	var mixed := [_seat(1, READY), _seat(2, READY), _seat(3), _seat(4)]
	var everyone := [_seat(1, READY), _seat(2, READY), _seat(3, READY)]
	var four_view := _town_view(FOUR_SPOTS, false)
	var all_ready := _lobby(TOWN, everyone)
	all_ready.all_ready = true
	var reconnecting := ClientState.build_view(
			_lobby(TOWN, mixed), 1, ClientState.world_view_of(four_view), false)
	# No ping without a live connection.
	reconnecting.fps_text = GameView.FPS_TEXT % SHOT_FPS
	var swinging := _town_view(TWO_SPOTS, false)
	swinging.players[0].slot_ticks = PackedByteArray(
			[ClientLoader.item_looks[ITEMS.index_of_id(SWORD.id)].swing.ticks, 0])
	var by_touch := _state(_lobby(TOWN, two), 1, _town_view(TWO_SPOTS, false), true, true)
	var thumb_held := _shot("town_touch_moving",
			"Played by touch, thumb on the joystick pushing up and right", by_touch)
	thumb_held.thumb = PackedVector2Array([THUMB_DOWN, THUMB_DOWN + THUMB_PUSH])
	var slot_1_held := _shot("town_touch_slot_1_pressed",
			"Played by touch, thumb on slot 1's button: its circle brightens", by_touch)
	slot_1_held.thumb = PackedVector2Array([_slot_1_center()])
	return [
		_shot("town_joined", "Town, two players, nobody ready, prompts showing",
				_state(_lobby(TOWN, two), 1, _town_view(TWO_SPOTS, false), true)),
		_shot("town_swing", "P1 at the end of a swing to the right: its last slice, on their right",
				_state(_lobby(TOWN, two), 1, swinging)),
		_shot("town_all_ready", "Town, everyone ready: the north door is open, bars green",
				_state(all_ready, 1, _town_view(THREE_SPOTS, true))),
		_shot("reconnecting", "Your connection dropped: frozen, your card d/c", reconnecting),
		_shot("town_touch",
				"Played by touch, idle, slot 2 empty: both item buttons, no key prompts",
				by_touch),
		thumb_held,
		slot_1_held,
	]


## Town again, with your slot 2 holding a shield.
static func _shield_shots() -> Array[Shot]:
	var shielded := _lobby(TOWN, [_with_shield(_seat(1)), _seat(2)])
	var by_touch := _state(shielded, 1, _town_view(TWO_SPOTS, false), true, true)
	var held := _shot("town_touch_shield_pressed",
			"Played by touch with a shield, thumb on slot 2's button: its circle brightens",
			by_touch)
	held.thumb = PackedVector2Array([_slot_1_center() + TouchControls.SLOT_2_OFFSET])
	var raised := _town_view(TWO_SPOTS, false)
	raised.players[0].slot_ticks = PackedByteArray([0, 1])
	return [
		_shot("town_shield",
				"Holding a shield in slot 2: K captioned with it, keys where they were",
				_state(shielded, 1, _town_view(TWO_SPOTS, false), true)),
		_shot("town_touch_shield",
				"Played by touch with a shield: the same buttons, where they were",
				by_touch),
		held,
		_shot("town_shield_raised",
				"P1 with their shield up: orange, on their facing side",
				_state(shielded, 1, raised)),
	]


static func _level_select_shots() -> Array[Shot]:
	var everyone := [_seat(1, READY), _seat(2, READY), _seat(3, READY)]
	var menu := _lobby(TOWN, everyone)
	menu.all_ready = true
	menu.level_select_open = true
	menu.cursor = 1
	var town := _town_view(THREE_SPOTS, true)
	return [
		_shot("level_select",
				"The level select over town, cursor on level 2: keys say Move, Select, Back",
				_state(menu, 1, town)),
		_shot("level_select_touch",
				"The level select by touch: no joystick or item buttons, Back bottom left",
				_state(menu, 1, town, false, true)),
	]


static func _run_shots() -> Array[Shot]:
	var party := [_seat(1), _seat(2), _seat(3)]
	var late := [_seat(1), _seat(2), _seat(3, NOT_READY, DROPPED), _seat(4, SPECTATING)]
	var mid := MID_RUN_SEC * GameTime.TICK_RATE
	var setup := WorldLoader.LEVELS.runs[0]
	var start_view := _spawned_view(setup.start, party.size(), _run_start_ticks(), setup)
	# The second room, so the shot has a shooter: its turret.
	var hurt := _view(setup.passages[0].to, HURT_SPOTS, mid, setup)
	hurt.players[0].health = WorldState.data.player_max_health - 1
	hurt.players[0].invulnerable = true
	hurt.players[1].health = 0
	_fire_at(hurt, _unit_of(hurt, TURRET_TYPE), HURT_SPOTS[3])
	hurt.players[2].connected = false
	var door_open := _view(setup.start, DOOR_SPOTS, mid, setup)
	door_open.units.clear()
	door_open.room_cleared = true
	var won := _view(setup.start, THREE_SPOTS, mid, setup)
	won.units.clear()
	won.room_cleared = true
	var lost := _view(setup.start, THREE_SPOTS, 0, setup)
	var boss_room := _view(setup.passages[1].to, THREE_SPOTS, mid, setup)
	_fire_at(boss_room, _unit_of(boss_room, BOSS_TYPE), THREE_SPOTS[1])
	return [
		_shot("run_start",
				"Run start: the party's square at the spawn, one enemy, door shut, timer, prompts",
				_state(_lobby(RUN, party), 1, start_view, true)),
		_shot("run_late_joiner",
				"Mid-run, seen by a late joiner (P4): P1 hurt, P2 downed, enemy turned, a shot",
				_state(_lobby(RUN, late), 4, hurt)),
		_shot("run_boss",
				"The last room: the boss, turned toward P1, and one of its large shots",
				_state(_lobby(RUN, party), 1, boss_room)),
		_shot("run_charge_cue",
				"The charger about to charge P1: its cue at full length",
				_state(_lobby(RUN, party), 1, _charge_cue_view(mid))),
		_shot("run_charge_cue_wall",
				"The charger about to charge up-left into the north wall: its cue cut at the wall",
				_state(_lobby(RUN, party), 1, _charge_cue_at_wall_view(mid))),
		_shot("run_door_open", "Room cleared: the north door is open, P1 at it",
				_state(_lobby(RUN, party), 1, door_open)),
		_shot("result_won", "Result: won, the gold earned so far top left",
				_state(_result(_paid(party), LobbyState.Outcome.WON), 1, won)),
		_shot("result_lost", "Result: lost (time ran out)",
				_state(_result(party, LobbyState.Outcome.LOST), 1, lost)),
	]


static func _shot(shot_name: String, caption: String, state: GameView) -> Shot:
	return Shot.new(shot_name, caption, state)


## What a connected seat [param my_id] sees. [param idle] is a seat that
## hasn't moved for long enough that the move keys are back;
## [param by_touch] one that last moved and acted by touch.
static func _state(lobby: LobbyState, my_id: int, view: Snapshot, idle := false,
		by_touch := false) -> GameView:
	var s := ClientState.build_view(lobby, my_id, ClientState.world_view_of(view), true)
	var input := InputState.new()
	if not idle:
		input.moved(0.0)
	if by_touch:
		input.screen_touched(true)
	s.prompts = input.prompts(
			0.0, ClientState.can_act(lobby, my_id, true), lobby.level_select_open)
	s.fps_text = GameView.FPS_TEXT % SHOT_FPS
	s.ping_text = GameView.PING_TEXT % SHOT_PING_MS
	return s


## [param view]'s first unit of [param unit_type].
static func _unit_of(view: Snapshot, unit_type: UnitType) -> Snapshot.Unit:
	var number := WorldLoader.UNITS.index_of(unit_type)
	return view.units.filter(func(d: Snapshot.Unit) -> bool: return d.unit_type == number)[0]


## Turns [param shooter] toward [param target] and adds one of its shots
## halfway there.
static func _fire_at(view: Snapshot, shooter: Snapshot.Unit, target: Vector2) -> void:
	shooter.facing = shooter.pos.direction_to(target)
	var shot := Snapshot.Projectile.new()
	shot.pos = shooter.pos.lerp(target, 0.5)
	var fire: AttackFire = WorldLoader.UNITS.types[shooter.unit_type].attacks[0]
	shot.radius = fire.projectile_radius
	view.projectiles.append(shot)


## The first room's charger facing P1, halfway through the time its cue
## holds at full length.
static func _charge_cue_view(ticks_left: int) -> Snapshot:
	var setup := WorldLoader.LEVELS.runs[0]
	var view := _view(setup.start, THREE_SPOTS, ticks_left, setup)
	var charger := view.units[0]
	charger.facing = charger.pos.direction_to(THREE_SPOTS[1])
	charger.charge_windup_ticks_left = WorldRenderer.CHARGE_CUE_HOLD_SEC / 2 * GameTime.TICK_RATE
	return view


## [method _charge_cue_view], with the charger near the north wall and
## facing into it at a slant.
static func _charge_cue_at_wall_view(ticks_left: int) -> Snapshot:
	var view := _charge_cue_view(ticks_left)
	var charger := view.units[0]
	charger.pos.y = WorldState.data.floor_area.position.y + 40
	charger.facing = Vector2(-1, -1).normalized()
	return view


## A fresh world in [param room], playing [param run]'s rooms and goals if
## given.
static func _fresh_world(room: Room, run: RunSetup = null) -> WorldState:
	if not run:
		return WorldSimulator.start(WorldLoader.run_plan(room))
	return WorldSimulator.start(WorldLoader.run_plan(room, run.passages, run.win, run.lose))


## The run's timer when it starts.
static func _run_start_ticks() -> int:
	var world := _fresh_world(WorldLoader.LEVELS.runs[0].start, WorldLoader.LEVELS.runs[0])
	return WorldSnapshot.of(world).run_ticks_left


## A snapshot of a fresh world in [param room] with players at
## [param spots] (seat number to position), in [param run] if any.
static func _view(room: Room, spots: Dictionary,
		ticks_left := Snapshot.NO_TIMER, run: RunSetup = null) -> Snapshot:
	var w := _fresh_world(room, run)
	for id: int in spots:
		WorldSimulator.add_player(w, id)
		w.players[id].pos = spots[id]
	var snap := WorldSnapshot.of(w)
	snap.graphics_seed = GRAPHICS_SEED
	snap.run_ticks_left = ticks_left
	return snap


## Town with players at [param spots], its door open if
## [param everyone_ready], as the lobby sets it.
static func _town_view(spots: Dictionary, everyone_ready: bool) -> Snapshot:
	var town := WorldLoader.TOWN
	var snap := _view(town.start, spots, Snapshot.NO_TIMER, town)
	snap.room_cleared = everyone_ready
	return snap


## [method _view], with players 1 to [param count] where the world puts them
## when it starts.
static func _spawned_view(room: Room, count: int, ticks_left: int, run: RunSetup) -> Snapshot:
	var w := _fresh_world(room, run)
	for id in range(1, count + 1):
		WorldSimulator.add_player(w, id)
	WorldSimulator.place_party(w)
	var snap := WorldSnapshot.of(w)
	snap.graphics_seed = GRAPHICS_SEED
	snap.run_ticks_left = ticks_left
	return snap


static func _lobby(phase: LobbyState.Phase, seats: Array) -> LobbyState:
	var state := LobbyState.new()
	state.phase = phase
	state.seats.assign(seats)
	return state


## Copies of [param seats], each having earned [constant EARNED_GOLD].
static func _paid(seats: Array) -> Array:
	return seats.map(func(s: LobbyState.Seat) -> LobbyState.Seat:
		return _seat(s.id, s.participation, s.connection, EARNED_GOLD))


static func _result(seats: Array, outcome: LobbyState.Outcome) -> LobbyState:
	var state := _lobby(RESULT, seats)
	state.outcome = outcome
	return state


static func _seat(
		id: int, participation := NOT_READY, connection := HERE, gold := 0) -> LobbyState.Seat:
	var s := LobbyState.Seat.new()
	s.id = id
	s.participation = participation
	s.connection = connection
	s.slot_items = PackedInt32Array([ITEMS.index_of_id(SWORD.id), LobbyState.NO_ITEM])
	if gold > 0:
		s.inventory[ClientLoader.gold_index] = gold
	return s


## [param seat], holding a shield in slot 2.
static func _with_shield(seat: LobbyState.Seat) -> LobbyState.Seat:
	var slots := seat.slot_items
	slots[1] = ITEMS.index_of_id(SHIELD.id)
	seat.slot_items = slots
	return seat


## Where slot 1's button's center is on the shots' screen.
static func _slot_1_center() -> Vector2:
	return Vector2(base_size()) * TouchControls.SLOT_1_CENTER_RATIO


## The game's screen size, which every shot lays out at.
static func base_size() -> Vector2i:
	return Vector2i(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))

class Shot:
	## File name without extension: lowercase, digits and underscores.
	var name: String
	## One line saying what state this is, shown on the contact sheet.
	var caption: String
	var state: GameView
	## Where a thumb is held, for the touch controls: where it landed, then
	## where it was dragged. Empty for none.
	var thumb := PackedVector2Array()

	func _init(p_name: String, p_caption: String, p_state: GameView) -> void:
		name = p_name
		caption = p_caption
		state = p_state
