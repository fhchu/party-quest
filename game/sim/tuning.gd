extends RefCounted
## Gameplay numbers, loaded once from balance.json.
##
## Every value is PLACEHOLDER (design). Durations in the file are in seconds;
## the [code]*_ticks[/code] values are converted from them at load.

const Protocol := preload("res://net/protocol.gd")

const BALANCE_PATH := "res://sim/balance.json"

static var _data: Dictionary = _load()

## Reported with match data. Change it whenever any value changes.
static var balance_version: String = _value("version")
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

## How long the arc is active. The player is rooted meanwhile.
static var swing_ticks := ticks(_value("swing.active_sec"))
## From the end of the arc to the next possible swing.
static var swing_cooldown_ticks := ticks(_value("swing.cooldown_sec"))
## A press this close to ready is remembered and fires when ready.
static var swing_buffer_ticks := ticks(_value("swing.buffer_sec"))
## How long the knockback push lasts; 0 moves the target at once.
static var knockback_ticks := ticks(_value("swing.knockback_sec"))
## After a player takes damage, how long no damage can hurt them.
static var player_invulnerable_ticks := ticks(_value("player.invulnerable_sec"))
## The match timer. The party loses when it runs out.
static var match_ticks := ticks(_value("match.duration_sec"))
## How long the outcome shows before town comes back.
static var result_ticks := ticks(_value("match.result_sec"))

static var _dummy_stats: Dictionary[String, DummyStats] = _load_dummy_stats()


## The attributes of the dummy kind named [param kind] in balance.json's
## [code]dummy_kinds[/code] (World.Kind's name in lower case).
static func dummy_stats(kind: String) -> DummyStats:
	if not _dummy_stats.has(kind):
		push_error("%s has no dummy_kinds.%s" % [BALANCE_PATH, kind])
		return DummyStats.new()
	return _dummy_stats[kind]


## Seconds to whole ticks, rounded; never 0 for a positive time.
static func ticks(sec: float) -> int:
	return maxi(roundi(sec * Protocol.TICK_RATE), 1 if sec > 0.0 else 0)


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
		stats.contact_push_ticks = ticks(_value(path + ".contact_push_sec"))
		stats.fire_interval_ticks = ticks(_value(path + ".fire_interval_sec"))
		stats.aim_lock_ticks = ticks(_value(path + ".aim_lock_sec"))
		stats.turn_rate = deg_to_rad(_value(path + ".turn_deg_per_sec"))
		stats.projectile_radius = _value(path + ".projectile_radius")
		stats.projectile_speed = _value(path + ".projectile_speed")
		stats.projectile_damage = _value(path + ".projectile_damage")
		out[kind] = stats
	return out


## One dummy kind's attributes.
class DummyStats:
	## 0: swings can't damage it.
	var health := 0
	var pushed_by_swings := false
	## Health a player loses touching it; 0 for none.
	var contact_damage := 0
	## How far touching it pushes a player away, in px.
	var contact_push_px := 0.0
	## How long that push lasts; 0 moves the player at once.
	var contact_push_ticks := 0
	## Between shots; 0 for a dummy that never shoots.
	var fire_interval_ticks := 0
	## How long before each shot it locks onto where its target is.
	var aim_lock_ticks := 0
	## How fast it turns, in radians per second.
	var turn_rate := 0.0
	## Its shots' radius, in px.
	var projectile_radius := 0.0
	## In px/s.
	var projectile_speed := 0.0
	## Health a player loses to one of its shots. The shot pushes like
	## touching it does.
	var projectile_damage := 0
