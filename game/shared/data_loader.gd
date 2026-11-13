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
## The side of one square tile, in px. The arena is a whole number of tiles
## each way, and its walls are one tile thick.
static var tile_size: float = _value("tile.size")
## How wide a door's gap in its wall is, in px: a whole number of tiles.
static var door_width: float = _value("door.width")
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


## The map named [param map_name] in balance.json's [code]maps[/code]; null
## if there's none.
static func map(map_name: String) -> Map:
	return _maps.get(map_name)


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
		var path := "maps." + map_name
		var m := Map.new()
		m.name = map_name
		if _data["maps"][map_name].has("clear_when"):
			m.clear_when = _condition_entries(path + ".clear_when")
		for spot: Dictionary in _value(path + ".dummies"):
			var d := MapDummy.new()
			d.kind = dummy_kind(spot["kind"])
			d.offset = Vector2(spot["offset"][0], spot["offset"][1])
			d.on_hit = spot.get("on_hit", "")
			m.dummies.append(d)
		out[map_name] = m
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


## One run condition as balance.json names it.
class ConditionEntry:
	## Such as [code]"defeat_all"[/code].
	var name := ""
	## Its value: a kind name, seconds, or true for none.
	var arg: Variant


## A room's layout: what's in it when the party first enters.
class Map:
	## Its key in balance.json's [code]maps[/code].
	var name := ""
	var dummies: Array[MapDummy] = []
	## The room is cleared once any of these is met; with none, it starts
	## cleared.
	var clear_when: Array[ConditionEntry] = []


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
