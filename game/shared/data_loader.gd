extends RefCounted
## Reads balance.json once, in the file's units. The classes that use a
## value copy it when they load, converting durations to ticks, and read
## their copy from then on.
##
## Every value is PLACEHOLDER (design).

const BALANCE_PATH := "res://shared/balance.json"

static var _data: Dictionary = _load()

## At most the viewport's size (project.godot): the whole arena is always on
## screen, so there's no camera to control.
static var arena := Rect2(0, 0, _value("arena.width"), _value("arena.height"))
## In px/s.
static var player_speed: float = _value("player.speed")
## Centered on the player's position; used for walls and for being hit.
static var player_hurtbox := Vector2(
		_value("player.hurtbox.width"), _value("player.hurtbox.height"))
## A player's health at the start of each world. At 0 they keep playing,
## until death exists.
static var player_max_health: int = _value("player.max_health")
static var swing_radius: float = _value("swing.radius")
## Width of the arc in radians, centered on facing.
static var swing_arc: float = deg_to_rad(_value("swing.arc_deg"))
static var swing_root_during_cooldown: bool = _value("swing.root_during_cooldown")
## How far a hit pushes its target, in px.
static var knockback_px: float = _value("swing.knockback_px")
## Health a swing deals to a damageable dummy.
static var swing_damage: int = _value("swing.damage")
## Every dummy's.
static var dummy_hurtbox := Vector2(
		_value("dummy.hurtbox.width"), _value("dummy.hurtbox.height"))

# Durations, in seconds.
static var swing_active_sec: float = _value("swing.active_sec")
static var swing_cooldown_sec: float = _value("swing.cooldown_sec")
static var swing_buffer_sec: float = _value("swing.buffer_sec")
static var knockback_sec: float = _value("swing.knockback_sec")
static var player_invulnerable_sec: float = _value("player.invulnerable_sec")
static var result_sec: float = _value("run.result_sec")

## Each dummy kind's attributes by name, in balance.json's order. A kind is
## its index in that order, in the simulation and in snapshots.
static var _dummy_kinds: Dictionary[String, DummyStats] = _load_dummy_stats()
## Each map by name. After [member _dummy_kinds], which it names kinds from.
static var _maps: Dictionary[String, Map] = _load_maps()
## Each run by name.
static var _runs: Dictionary[String, RunSetup] = _load_runs()


## The kind named [param kind_name] in balance.json's [code]dummy_kinds[/code].
static func dummy_kind(kind_name: String) -> int:
	var kind := _dummy_kinds.keys().find(kind_name)
	if kind == -1:
		push_error("%s has no dummy_kinds.%s" % [BALANCE_PATH, kind_name])
	return kind


static func dummy_kind_count() -> int:
	return _dummy_kinds.size()


## The attributes of [param kind], from [method dummy_kind].
static func dummy_stats(kind: int) -> DummyStats:
	return _dummy_kinds.values()[kind]


## The map named [param map_name] in balance.json's [code]maps[/code].
static func map(map_name: String) -> Map:
	if not _maps.has(map_name):
		push_error("%s has no maps.%s" % [BALANCE_PATH, map_name])
		return Map.new()
	return _maps[map_name]


## The run named [param run_name] in balance.json's [code]runs[/code].
static func run(run_name: String) -> RunSetup:
	if not _runs.has(run_name):
		push_error("%s has no runs.%s" % [BALANCE_PATH, run_name])
		return RunSetup.new()
	return _runs[run_name]


static func _load() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(BALANCE_PATH))
	if not data is Dictionary:
		push_error("can't read %s as a JSON object" % BALANCE_PATH)
		return {}
	return data


## Looks up a dotted path such as [code]"swing.radius"[/code]. A missing key is
## an error, not a silent 0.
static func _value(path: String) -> Variant:
	var value: Variant = _data
	for key in path.split("."):
		if not (value is Dictionary and value.has(key)):
			push_error("%s is missing \"%s\"" % [BALANCE_PATH, path])
			return 0
		value = value[key]
	return value


static func _load_dummy_stats() -> Dictionary[String, DummyStats]:
	var out: Dictionary[String, DummyStats] = {}
	var kinds: Variant = _value("dummy_kinds")
	if not kinds is Dictionary:
		return out
	for kind: String in kinds:
		var path := "dummy_kinds." + kind
		var stats := DummyStats.new()
		stats.health = _value(path + ".health")
		stats.pushed_by_swings = _value(path + ".pushed_by_swings")
		stats.contact_damage = _value(path + ".contact_damage")
		stats.contact_push_px = _value(path + ".contact_push_px")
		stats.contact_push_sec = _value(path + ".contact_push_sec")
		stats.fire_interval_sec = _value(path + ".fire_interval_sec")
		stats.aim_lock_sec = _value(path + ".aim_lock_sec")
		stats.turn_rate = deg_to_rad(_value(path + ".turn_deg_per_sec"))
		stats.projectile_radius = _value(path + ".projectile_radius")
		stats.projectile_speed = _value(path + ".projectile_speed")
		stats.projectile_damage = _value(path + ".projectile_damage")
		out[kind] = stats
	return out


static func _load_maps() -> Dictionary[String, Map]:
	var out: Dictionary[String, Map] = {}
	var maps: Variant = _value("maps")
	if not maps is Dictionary:
		return out
	for map_name: String in maps:
		var m := Map.new()
		for spot: Dictionary in _value("maps.%s.dummies" % map_name):
			var d := MapDummy.new()
			d.kind = dummy_kind(spot["kind"])
			d.offset = Vector2(spot["offset"][0], spot["offset"][1])
			d.on_hit = spot.get("on_hit", "")
			m.dummies.append(d)
		out[map_name] = m
	return out


static func _load_runs() -> Dictionary[String, RunSetup]:
	var out: Dictionary[String, RunSetup] = {}
	var runs: Variant = _value("runs")
	if not runs is Dictionary:
		return out
	for run_name: String in runs:
		var path := "runs." + run_name
		var setup := RunSetup.new()
		setup.map_name = _value(path + ".map")
		setup.win = _condition_entries(path + ".run_conditions.win")
		setup.lose = _condition_entries(path + ".run_conditions.lose")
		out[run_name] = setup
	return out


## Each entry is an object with one key, the condition's name.
static func _condition_entries(path: String) -> Array[ConditionEntry]:
	var out: Array[ConditionEntry] = []
	for item: Dictionary in _value(path):
		if item.size() != 1:
			push_error("%s: each of %s names one condition" % [BALANCE_PATH, path])
			continue
		var entry := ConditionEntry.new()
		entry.name = item.keys()[0]
		entry.arg = item.values()[0]
		out.append(entry)
	return out


## Which map a run is on, and what ends it. Wins are checked before
## losses.
class RunSetup:
	var map_name := ""
	var win: Array[ConditionEntry] = []
	var lose: Array[ConditionEntry] = []


## One run condition as balance.json names it.
class ConditionEntry:
	## Such as [code]"defeat_all"[/code].
	var name := ""
	## Its value: a kind name, seconds, or true for none.
	var arg: Variant


## What a world starts with.
class Map:
	var dummies: Array[MapDummy] = []


## One dummy a map places.
class MapDummy:
	## From [method dummy_kind].
	var kind := 0
	## From the arena's center, in px.
	var offset := Vector2.ZERO
	## What a swing touching it asks the lobby to do; empty for nothing.
	var on_hit := ""


## One dummy kind's attributes.
class DummyStats:
	## 0: swings can't damage it.
	var health := 0
	var pushed_by_swings := false
	## Health a player loses touching it; 0 for none.
	var contact_damage := 0
	## How far touching it pushes a player away, in px.
	var contact_push_px := 0.0
	## How long that push lasts, in seconds; 0 moves the player at once.
	var contact_push_sec := 0.0
	## Between shots, in seconds; 0 for a dummy that never shoots.
	var fire_interval_sec := 0.0
	## How long before each shot it locks onto where its target is, in
	## seconds.
	var aim_lock_sec := 0.0
	## How fast it turns, in radians per second.
	var turn_rate := 0.0
	## Its shots' radius, in px.
	var projectile_radius := 0.0
	## In px/s.
	var projectile_speed := 0.0
	## Health a player loses to one of its shots. The shot pushes like
	## touching it does.
	var projectile_damage := 0
