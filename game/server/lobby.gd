extends RefCounted
## One lobby's rules about people: who holds which seat, seat holds, and
## which phase the lobby is in. The lobby makes every phase change; each
## phase's own rules live in its object (see [code]lobby_phase.gd[/code]),
## which never knows what comes next.
##
## No networking: server.gd maps connections onto seats and calls in. Every
## time-dependent call is passed the current time, so tests run on their own
## clock.

const WorldState := preload("res://sim/world_state.gd")
const WorldSimulator := preload("res://sim/world_simulator.gd")
const WorldSnapshot := preload("res://sim/world_snapshot.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const Snapshot := preload("res://net/snapshot.gd")
const LobbyPhase := preload("res://server/lobby_phase.gd")
const Seat := preload("res://server/seat.gd")
const Town := preload("res://server/town.gd")
const LevelSelect := preload("res://server/level_select.gd")
const Run := preload("res://server/run.gd")
const Result := preload("res://server/result.gd")
const PlayerData := preload("res://server/player_data.gd")
const Items := preload("res://shared/data/items.gd")
const Item := preload("res://shared/data/item.gd")
const EquipItem := preload("res://shared/data/items/equip_item.gd")

## The MVP's party size. The backend's maxEarners
## (server/internal/runs/runs.go) is the same limit.
const MAX_PLAYERS := 4
## The server stops a player whose client sends no input for this long. Inputs
## come every tick (client/client.gd's _physics_process), so this rides out a
## burst of lost or late ones.
const INPUT_SILENCE_SEC := 0.25
## With Server.exit_when_empty on, the game server quits once no seat has
## been held for this long.
const EMPTY_EXIT_SEC := 60.0
## What every new seat's holder starts with.
const STARTING_PLAYER_DATA: PlayerData = preload("res://server/data/starting_player_data.tres")
const ITEMS: Items = preload("res://shared/data/items.tres")
const GOLD: Item = preload("res://shared/data/items/item_gold.tres")
const SHIELD: Item = preload("res://shared/data/items/item_shield.tres")
# The on_hit names in shared/data/rooms/ that the lobby acts on.
const TOGGLE_READY := "toggle_ready"
const TOGGLE_SHIELD := "toggle_shield"
## Where in [member PlayerData.slot_items] a shield from the shield toggle
## unit goes: the use_item_2 slot.
const TOGGLED_SHIELD_SLOT := 1
## Each seat's participation as clients see it.
const WIRE_PARTICIPATION := {
	Seat.Participation.NOT_READY: LobbyState.Participation.NOT_READY,
	Seat.Participation.READY: LobbyState.Participation.READY,
	Seat.Participation.SPECTATING: LobbyState.Participation.SPECTATING,
}
## Each world outcome as clients see it.
const WIRE_OUTCOME := {
	WorldState.Outcome.NONE: LobbyState.Outcome.NONE,
	WorldState.Outcome.WON: LobbyState.Outcome.WON,
	WorldState.Outcome.LOST: LobbyState.Outcome.LOST,
}
## Each phase's name on the wire, by its script.
const WIRE_PHASE := {
	Town: LobbyState.Phase.TOWN,
	Run: LobbyState.Phase.RUN,
	Result: LobbyState.Phase.RESULT,
}

## A [code]town.gd[/code], [code]run.gd[/code] or [code]result.gd[/code].
## Changed only by [method _change_phase].
var phase: LobbyPhase = Town.new()
## Replaced by a fresh one in town and at the start of each run.
var world: WorldState
## Shows only in town; kept across runs, so its cursor stays where it was.
var level_select := LevelSelect.new(WorldSimulator.level_count())

## By session ID, which survives reconnects.
var _seats: Dictionary[String, Seat] = {}
## Whether clients' copies of [method state] are out of date, or a newcomer
## has none yet.
var _lobby_state_unsent := true
## The last time anyone held a seat, or when the lobby was made.
var _last_seated_msec := 0


func _init(now_msec: int) -> void:
	_last_seated_msec = now_msec
	world = WorldSimulator.town()


## Null if no seat has [param session_id].
func seat_of_session(session_id: String) -> Seat:
	return _seats.get(session_id)


## Null if [param peer_id] holds no seat. A DROPPED seat has no peer.
func seat_of_peer(peer_id: int) -> Seat:
	# At most MAX_PLAYERS seats: a search is simpler than a second index to
	# keep in sync.
	for seat: Seat in _seats.values():
		if seat.peer_id == peer_id:
			return seat
	return null


func seats() -> Array[Seat]:
	var out: Array[Seat] = []
	out.assign(_seats.values())
	return out


## Seats [param peer_id] as [param session_id]: back in their own seat if
## they hold one, else in the lowest free seat. A newcomer is a player in
## town and a spectator otherwise. Returns null when no seat is
## free. The caller handles a seat that's still connected elsewhere.
func join(session_id: String, peer_id: int) -> Seat:
	var seat: Seat = _seats.get(session_id)
	if not seat:
		if _seats.size() >= MAX_PLAYERS:
			return null
		seat = Seat.new()
		seat.player_id = _free_seat_number()
		seat.player_data = STARTING_PLAYER_DATA.duplicate(true)
		seat.participation = (Seat.Participation.NOT_READY if phase.newcomers_play()
				else Seat.Participation.SPECTATING)
		if seat.participation != Seat.Participation.SPECTATING:
			WorldSimulator.add_player(world, seat.player_id)
			_equip_character(seat)
		_seats[session_id] = seat
		# The party picks a level together, so a newcomer sends them back to
		# town to ready up with them.
		if level_select.is_open:
			_close_level_select()
	seat.peer_id = peer_id
	seat.connection = Seat.Connection.SILENT
	WorldSimulator.set_connected(world, seat.player_id, true)
	_lobby_state_unsent = true
	return seat


## A disconnected player can't be ready, so a drop clears it.
func drop(seat: Seat) -> void:
	seat.connection = Seat.Connection.DROPPED
	seat.peer_id = 0
	if seat.participation == Seat.Participation.READY:
		seat.participation = Seat.Participation.NOT_READY
	WorldSimulator.set_connected(world, seat.player_id, false)
	_lobby_state_unsent = true


## [param presses] counts each input action's presses since the last input;
## [param held_bits] has a bit per input action held.
func input(seat: Seat, move: Vector2, presses: PackedByteArray, held_bits: int,
		now_msec: int) -> void:
	if seat.connection != Seat.Connection.SILENT and seat.connection != Seat.Connection.ACTIVE:
		return
	seat.connection = Seat.Connection.ACTIVE
	seat.since_msec = now_msec
	# A spectator has no character, so the world ignores it.
	WorldSimulator.set_input(world, seat.player_id, move, presses, held_bits)


## An away player stays connected and just stops.
func set_away(seat: Seat, away: bool) -> void:
	if (seat.connection == Seat.Connection.DROPPED
			or away == (seat.connection == Seat.Connection.AWAY)):
		return
	if away:
		seat.connection = Seat.Connection.AWAY
		WorldSimulator.stop_player(world, seat.player_id)
	else:
		seat.connection = Seat.Connection.SILENT
	_lobby_state_unsent = true


## [param presses] are the presses of [param seat]'s last [method input], as
## the level select reads them. Ignored unless it shows and the seat's input
## counts.
func menu_input(seat: Seat, presses: LevelSelect.MenuPresses) -> void:
	if not level_select.is_open or seat.connection != Seat.Connection.ACTIVE:
		return
	var cursor_before := level_select.cursor
	level_select.read_presses(seat.player_id, presses)
	if level_select.cursor != cursor_before:
		_lobby_state_unsent = true


## A tap on level [param level]'s square, from 0. Does nothing unless the
## level select shows.
func choose_level(level: int) -> void:
	if level_select.is_open:
		level_select.choose(level)


## One tick: input silence, what was pressed at the level select, the doors,
## the world (unless frozen), the phase, the level select opening or else
## what the world's swings touched, then dropped seats.
func step(now_msec: int) -> void:
	# Before dropped seats are freed, so the empty wait starts when the last
	# one is freed.
	if not _seats.is_empty():
		_last_seated_msec = now_msec
	for seat: Seat in _seats.values():
		_step_seat(seat, now_msec)
	# Before the doors, so the door shuts as soon as backing out un-readies.
	_act_on_level_select()
	if phase.doors_follow_readiness():
		WorldSimulator.set_room_cleared(world, all_ready())

	WorldSimulator.step(world)
	# Before swings are acted on, so a swing that un-readies someone can't
	# stop the run the party just walked out to.
	if phase.is_over(world.outcome != WorldState.Outcome.NONE, world.is_time_up()):
		_end_phase()
	if world.level_select_requested and not level_select.is_open:
		level_select.open()
		_lobby_state_unsent = true
	else:
		# Skipped as the level select opens, so a swing that un-readies
		# someone can't leave the party in it with someone not ready.
		for contact in world.swing_contacts:
			_act_on_contact(contact)
	if not phase.holds_dropped_seats():
		for seat in seats():
			if seat.connection == Seat.Connection.DROPPED:
				_free_seat(seat)


## Whether nobody has held a seat for [constant EMPTY_EXIT_SEC].
func is_abandoned(now_msec: int) -> bool:
	return (_seats.is_empty()
			and now_msec - _last_seated_msec > EMPTY_EXIT_SEC * 1000)


## Whether clients need [method state] sent: it changed, or someone joined.
func is_lobby_state_unsent() -> bool:
	return _lobby_state_unsent


## Called once every connected seat has been sent its [method state].
func mark_lobby_state_sent() -> void:
	_lobby_state_unsent = false


## Returns whether anything changed.
func set_ready(seat: Seat, ready: bool) -> bool:
	var participation := Seat.Participation.READY if ready else Seat.Participation.NOT_READY
	if seat.participation == participation:
		return false
	seat.participation = participation
	_lobby_state_unsent = true
	return true


## Whether every seat is ready, so a run may start. False with no seats.
func all_ready() -> bool:
	return (not _seats.is_empty()
			and _seats.values().all(
				func(s: Seat) -> bool: return s.participation == Seat.Participation.READY))


## Starts level [param level]'s run, from 0, if [method all_ready], from any
## phase. Returns whether it did.
func start_run(level: int) -> bool:
	if not all_ready():
		return false
	_change_phase(Run.new())
	_replace_world(WorldSimulator.run(world, level))
	print("run seed %d" % world.rng.seed)
	return true


## Shows the result of a run that ended with [param outcome], over the
## run's world, frozen, until the world's time is up. Pays the run's gold.
func end_run(outcome: WorldState.Outcome) -> void:
	# Its world keeps the outcome, for clients to see during the result.
	world.outcome = outcome
	# Seats with a character played the run from its start; spectators have
	# none. A seat still dropped at the end earns nothing.
	var gold := world.gold_earned()
	for seat in seats():
		if (gold > 0 and world.players.has(seat.player_id)
				and seat.connection != Seat.Connection.DROPPED):
			seat.player_data.add_item(GOLD.id, gold)
	_change_phase(Result.new())
	WorldSimulator.show_result(world)


## [param you] is the seat it's for, so its holder learns their number.
func state(you: Seat = null) -> LobbyState:
	var out := LobbyState.new()
	out.phase = WIRE_PHASE[phase.get_script()]
	out.outcome = WIRE_OUTCOME[world.outcome]
	out.all_ready = all_ready()
	out.you = you.player_id if you else 0
	out.level_select_open = level_select.is_open
	out.cursor = level_select.cursor
	var sorted := seats()
	sorted.sort_custom(func(a: Seat, b: Seat) -> bool: return a.player_id < b.player_id)
	for seat in sorted:
		var s := LobbyState.Seat.new()
		s.id = seat.player_id
		s.participation = WIRE_PARTICIPATION[seat.participation]
		for id in seat.player_data.inventory:
			s.inventory[ITEMS.index_of_id(id)] = seat.player_data.inventory[id]
		for id in seat.player_data.slot_items:
			s.slot_items.append(LobbyState.NO_ITEM if id == PlayerData.EMPTY_SLOT
					else ITEMS.index_of_id(id))
		# An away seat looks connected: other players needn't know its tab
		# is hidden.
		if seat.connection == Seat.Connection.DROPPED:
			s.connection = LobbyState.Connection.DROPPED
		out.seats.append(s)
	return out


func snapshot() -> Snapshot:
	return WorldSnapshot.of(world)


func _change_phase(next: LobbyPhase) -> void:
	phase = next
	_lobby_state_unsent = true


## Moves on from [member phase], which just ended on its own.
func _end_phase() -> void:
	match WIRE_PHASE[phase.get_script()]:
		LobbyState.Phase.TOWN:
			start_run(world.selected_level)
		LobbyState.Phase.RUN:
			end_run(world.outcome)
		LobbyState.Phase.RESULT:
			_start_town()


## Acts on what was pressed at the level select since the last tick: back
## un-readies whoever pressed it and shuts the level select, and beats a
## level chosen in the same tick.
func _act_on_level_select() -> void:
	if not level_select.is_open:
		return
	if not level_select.backed_out_by.is_empty():
		for id in level_select.backed_out_by:
			var seat := _seat_of_player(id)
			if seat:
				set_ready(seat, false)
		_close_level_select()
	elif level_select.is_level_chosen:
		WorldSimulator.close_level_select(world, level_select.cursor)
		level_select.close()
		_lobby_state_unsent = true


## Shuts the level select and lets town's world run on from where it froze.
func _close_level_select() -> void:
	level_select.close()
	WorldSimulator.close_level_select(world, WorldState.NO_LEVEL)
	_lobby_state_unsent = true


func _start_town() -> void:
	_change_phase(Town.new())
	for seat in seats():
		seat.participation = Seat.Participation.NOT_READY
	_replace_world(WorldSimulator.town(world))


## Toggles readiness, or whether the attacker has a shield, if the unit
## it touched asks.
func _act_on_contact(contact: WorldState.SwingContact) -> void:
	var seat := _seat_of_player(contact.attacker_id)
	if not seat:
		return
	match contact.on_hit:
		TOGGLE_READY:
			set_ready(seat, seat.participation != Seat.Participation.READY)
		TOGGLE_SHIELD:
			_toggle_shield(seat)


## Gives [param seat]'s holder a shield in its slot, or removes the one they
## have.
func _toggle_shield(seat: Seat) -> void:
	var data := seat.player_data
	if data.quantity_of(SHIELD.id) > 0:
		data.remove_item(SHIELD.id, data.quantity_of(SHIELD.id))
	else:
		data.add_item(SHIELD.id, 1)
		data.slot_items[TOGGLED_SHIELD_SLOT] = SHIELD.id
	_equip_slot(seat, TOGGLED_SHIELD_SLOT)
	_lobby_state_unsent = true


## Gives [param seat]'s character what's in each of its holder's item
## slots.
func _equip_character(seat: Seat) -> void:
	for slot in seat.player_data.slot_items.size():
		_equip_slot(seat, slot)


## Gives [param seat]'s character what's in its holder's item slot
## [param slot], leaving its other slots as they are.
func _equip_slot(seat: Seat, slot: int) -> void:
	var id := seat.player_data.slot_items[slot]
	var item: EquipItem = null
	if id != PlayerData.EMPTY_SLOT:
		item = ITEMS.items[ITEMS.index_of_id(id)]
	WorldSimulator.set_slot_item(world, seat.player_id, slot, item)


## Null if no seat has [param player_id].
func _seat_of_player(player_id: int) -> Seat:
	for seat: Seat in _seats.values():
		if seat.player_id == player_id:
			return seat
	return null


## Frees [param seat] for someone else; the seats after it move down.
func _free_seat(seat: Seat) -> void:
	_seats.erase(_seats.find_key(seat))
	WorldSimulator.remove_player(world, seat.player_id)
	_close_gaps()
	_lobby_state_unsent = true


## Makes [param fresh] the lobby's world, with a character for every seat
## that isn't spectating. The old world, with its units, is dropped.
func _replace_world(fresh: WorldState) -> void:
	var playing := _seats.values().filter(func(seat: Seat) -> bool:
		return seat.participation != Seat.Participation.SPECTATING)
	for seat: Seat in playing:
		WorldSimulator.add_player(fresh, seat.player_id, seat.connection != Seat.Connection.DROPPED)
	WorldSimulator.place_party(fresh)
	world = fresh
	for seat: Seat in playing:
		_equip_character(seat)


func _step_seat(seat: Seat, now_msec: int) -> void:
	# The client went quiet without disconnecting.
	if (seat.connection == Seat.Connection.ACTIVE
			and now_msec - seat.since_msec > INPUT_SILENCE_SEC * 1000):
		seat.connection = Seat.Connection.SILENT
		WorldSimulator.stop_player(world, seat.player_id)


## Moves everyone after a freed seat down one (2 to 1, 3 to 2 ...), so the
## lobby's seats are always 1 to n. Only town frees seats.
## Characters keep their place; color and the next spawn spot follow the new
## number.
func _close_gaps() -> void:
	var sorted := seats()
	sorted.sort_custom(func(a: Seat, b: Seat) -> bool: return a.player_id < b.player_id)
	# In ascending order each new number is already free: it was the freed
	# seat's, or the one just moved down from it.
	for i in sorted.size():
		var seat := sorted[i]
		var number := i + 1
		if seat.player_id != number:
			WorldSimulator.renumber_player(world, seat.player_id, number)
			seat.player_id = number


## The lowest seat number nobody holds. Seats are numbered 1 to n with no
## gaps (see [method _close_gaps]), so it's the next one up; a held seat
## keeps its number, so a reconnecting player finds theirs waiting.
func _free_seat_number() -> int:
	var held_seat_numbers := _seats.values().map(func(s: Seat) -> int: return s.player_id)
	var n := 1
	while n in held_seat_numbers:
		n += 1
	return n
