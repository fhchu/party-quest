extends RefCounted
## Gameplay numbers, loaded once from balance.json.
##
## Every value is PLACEHOLDER (design). Durations in the file are in seconds;
## the [code]*_ticks[/code] values are converted from them at load.

const Protocol := preload("res://net/protocol.gd")

const BALANCE_PATH := "res://sim/balance.json"

# Load-test props, not design: enough of them to load the snapshot and the
# drawing. Their speed, size and turn time are arbitrary.
const DUMMY_COUNT := 30
const DUMMY_SPEED := 30.0
const DUMMY_HURTBOX := Vector2(10, 10)
const DUMMY_TURN_SEC := 1.5

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
static var swing_radius: float = _value("swing.radius")
## Width of the arc in radians, centered on facing.
static var swing_arc: float = deg_to_rad(_value("swing.arc_deg"))
## Holding attack counts as another press every buffer window. Needs a buffer.
static var swing_hold_repeats: bool = _value("swing.hold_repeats")
static var swing_root_during_cooldown: bool = _value("swing.root_during_cooldown")
## How far a hit pushes its target, in px.
static var knockback_px: float = _value("swing.knockback_px")
static var target_dummy_hurtbox := Vector2(
		_value("target_dummy.hurtbox.width"), _value("target_dummy.hurtbox.height"))

## How long the arc is active. The player is rooted meanwhile.
static var swing_ticks := ticks(_value("swing.active_sec"))
## From the end of the arc to the next possible swing.
static var swing_cooldown_ticks := ticks(_value("swing.cooldown_sec"))
## A press this close to ready is remembered and fires when ready.
static var swing_buffer_ticks := ticks(_value("swing.buffer_sec"))
## How long the knockback push lasts; 0 moves the target at once.
static var knockback_ticks := ticks(_value("swing.knockback_sec"))
static var hit_flash_ticks := ticks(_value("hit_flash_sec"))
static var dummy_turn_ticks := ticks(DUMMY_TURN_SEC)


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
