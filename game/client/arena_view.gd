extends Node2D
## Draws the arena from one snapshot: walls, dummies with their labels,
## swings and players. Your own character is drawn last, so it's on top.
## Holds no game state; the client (or the UI gallery) hands it what to draw.

const Tuning := preload("res://sim/tuning.gd")
const World := preload("res://sim/world.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Palette := preload("res://client/palette.gd")

# PLACEHOLDER (art): shapes the size of their hurtboxes until there are
# sprites. Player colors are in palette.gd.
const DUMMY_COLOR := Color(0.8, 0.65, 0.4)
## START before everyone is ready. Not grey: the background is grey.
const START_WAITING_COLOR := Color(0.7, 0.2, 0.15)
## START once everyone is ready.
const START_LIVE_COLOR := Color(0.2, 0.9, 0.3)
## A struck dummy's flash and an invulnerable player's blink. White, not red,
## which reads as blood.
const FLASH_COLOR := Color.WHITE
## How long each on and off of an invulnerable player's blink lasts.
const INVULNERABLE_BLINK_SEC := 0.1
const SWING_COLOR := Color(1, 1, 1, 0.3)
const WALL_COLOR := Color(0.35, 0.35, 0.4)
const WALL_WIDTH := 2.0
## Facing line and your own player's outline.
const MARKING_COLOR := Color.WHITE
const FACING_WIDTH := 2.0
const OUTLINE_WIDTH := 1.0
## Enough straight pieces that the swing's edge looks round.
const ARC_SEGMENTS := 12
const LABEL_COLOR := Color.WHITE
const LABEL_FONT_SIZE := 8
## Centered on the dummy; wide enough for the longest label.
const LABEL_WIDTH := 120.0
## From the top of the dummy to the label's baseline.
const LABEL_GAP := 3.0

# PLACEHOLDER (design): the wording.
const READY_LABEL := "READY"
const START_WAITING_LABEL := "WAITING FOR READY"
const START_LIVE_LABEL := "START"

var _view: Snapshot
var _my_id := 0
var _start_live := false


## The label over a lobby dummy of [param kind]; empty for other kinds.
## [param start_live] is whether everyone is ready.
static func label_for(kind: World.Kind, start_live: bool) -> String:
	match kind:
		World.Kind.READY:
			return READY_LABEL
		World.Kind.START:
			return START_LIVE_LABEL if start_live else START_WAITING_LABEL
	return ""


static func _dummy_color(kind: World.Kind, start_live: bool) -> Color:
	match kind:
		World.Kind.START:
			return START_LIVE_COLOR if start_live else START_WAITING_COLOR
	return DUMMY_COLOR


## Distance from a box's center to its edge in direction [param dir].
static func _to_box_edge(dir: Vector2, half: Vector2) -> float:
	var x := half.x / absf(dir.x) if not is_zero_approx(dir.x) else INF
	var y := half.y / absf(dir.y) if not is_zero_approx(dir.y) else INF
	return minf(x, y)


## Draws [param view] (null draws only the walls). [param my_id] is your
## seat; [param start_live] whether everyone in the lobby is ready.
func show_view(view: Snapshot, my_id: int, start_live: bool) -> void:
	_view = view
	_my_id = my_id
	_start_live = start_live
	queue_redraw()


func _draw() -> void:
	draw_rect(Tuning.arena, WALL_COLOR, false, WALL_WIDTH)
	if not _view:
		return
	for d in _view.dummies:
		_draw_dummy(d)
	var mine: Snapshot.Player = null
	for p in _view.players:
		if p.id == _my_id:
			mine = p
		else:
			_draw_player(p)
	if mine:
		_draw_player(mine)


func _draw_dummy(d: Snapshot.Dummy) -> void:
	var kind := d.kind as World.Kind
	var box := World.hurtbox(d.pos, Tuning.dummy_hurtbox)
	draw_rect(box, FLASH_COLOR if d.flashing else _dummy_color(kind, _start_live))
	var label := label_for(kind, _start_live)
	if label:
		var at := Vector2(d.pos.x - LABEL_WIDTH / 2, box.position.y - LABEL_GAP)
		draw_string(ThemeDB.fallback_font, at, label, HORIZONTAL_ALIGNMENT_CENTER,
				LABEL_WIDTH, LABEL_FONT_SIZE, LABEL_COLOR)


func _draw_player(p: Snapshot.Player) -> void:
	if p.swing_ticks > 0:
		_draw_swing(p.pos, p.facing)
	# Only the swing may leave the hurtbox, so a player at a wall stays on screen.
	var box := World.hurtbox(p.pos, Tuning.player_hurtbox)
	var blinking_white := p.invulnerable and _blink_on()
	draw_rect(box, FLASH_COLOR if blinking_white else Palette.player_color(p.id))
	if p.id == _my_id:
		# Inset by half its width, so it's drawn inside the box.
		draw_rect(box.grow(-OUTLINE_WIDTH / 2), MARKING_COLOR, false, OUTLINE_WIDTH)
	var edge := p.pos + p.facing * _to_box_edge(p.facing, box.size / 2)
	draw_line(p.pos, edge, MARKING_COLOR, FACING_WIDTH)


## Whether an invulnerable player is white this moment. Goes by the
## snapshot's tick, so every client blinks in step.
func _blink_on() -> bool:
	return floori(_view.tick / float(Tuning.ticks(INVULNERABLE_BLINK_SEC))) % 2 == 0


func _draw_swing(pos: Vector2, facing: Vector2) -> void:
	var points := PackedVector2Array([pos])
	for i in ARC_SEGMENTS + 1:
		var t := float(i) / ARC_SEGMENTS
		var angle := facing.angle() + lerpf(-Tuning.swing_arc / 2, Tuning.swing_arc / 2, t)
		points.append(pos + Vector2.from_angle(angle) * Tuning.swing_radius)
	draw_colored_polygon(points, SWING_COLOR)
