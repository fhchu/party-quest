extends RefCounted
## How you've been playing lately, for the prompts: when you last moved,
## and whether you last moved and last acted by touch or with the keyboard.
## ClientState says when you get control of a character back and whether
## you can act; this decides which keys or touch buttons to show.

const GameView := preload("res://client/game_view.gd")

## How long without moving before the move keys come back.
const PROMPT_IDLE_SEC := 3.0

## -INF when you've just got control, so the move keys show at once.
var _last_moved_at := -INF
# The keyboard is the default for both.
var _moved_by_touch := false
var _acted_by_touch := false


func moved(now: float) -> void:
	_last_moved_at = now


## A touch on the screen: in the joystick's area it's a move, and any touch
## brings up the touch buttons.
func screen_touched(in_move_area: bool) -> void:
	_acted_by_touch = true
	if in_move_area:
		_moved_by_touch = true


## A key press: a move key brings back the move keys, any other key the
## action keys.
func key_pressed(is_move_key: bool) -> void:
	if is_move_key:
		_moved_by_touch = false
	else:
		_acted_by_touch = false


## You got control of a character back: on joining, after the result, into
## a new run, and (later) on revival.
func control_regained() -> void:
	_last_moved_at = -INF


## What to show at [param now]; nothing while you can't act
## ([param can_act]). Over the level select ([param level_select_open]) the
## move keys show for as long as you play by keyboard, since moving there
## means moving its cursor; by touch you tap a square instead.
func prompts(now: float, can_act: bool, level_select_open: bool) -> GameView.Prompts:
	var out := GameView.Prompts.new()
	if not can_act:
		return out
	var idle := now - _last_moved_at >= PROMPT_IDLE_SEC
	out.show_move_keys = (level_select_open or idle) and not _moved_by_touch
	out.action_prompt = (GameView.ActionPrompt.BUTTONS if _acted_by_touch
			else GameView.ActionPrompt.KEYS)
	return out
