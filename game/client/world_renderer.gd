extends Node2D
## Draws the arena from one snapshot: the grass floor, walls, doors and the label under a
## shut town door, dummies with their labels, swings, players and shots.
## Your own character is drawn last, so it's on top.
## Holds no game state; GameRenderer hands it what to draw.

const GameTime := preload("res://shared/game_time.gd")
const ClientLoader := preload("res://client/client_loader.gd")
const WorldView := preload("res://client/world_view.gd")
const Palette := preload("res://client/palette.gd")

## The floor's tiles, in the order [constant GRASS_SHEET_CELLS] and
## [constant GRASS_WEIGHTS] list them.
enum GrassTile {
	EMPTY,
	TWO_STRANDS,
	RIGHT_HALF,
	LONG_GRASS,
}

## Not in git: the art is kept out of the public repo, so a fresh clone has
## no file here and draws [constant PLAIN_GRASS_COLOR] instead.
const GRASS_SHEET_PATH := "res://client/art/grass.png"
## One tile's side in the sheet, in sheet px.
const GRASS_TILE_SIZE := 16
## Each sheet pixel is drawn this many screen px across.
const GRASS_SCALE := 2
const FLOOR_CELL_SIZE := GRASS_TILE_SIZE * GRASS_SCALE
## Where each [enum GrassTile] is in the sheet, in tiles.
const GRASS_SHEET_CELLS: Array[Vector2i] = [
	Vector2i(0, 1),
	Vector2i(0, 0),
	Vector2i(1, 1),
	Vector2i(1, 0),
]
## How often each [enum GrassTile] is picked, relative to the others. Untuned.
const GRASS_WEIGHTS: Array[float] = [8.0, 4.0, 2.0, 1.0]
## The whole floor when the sheet is missing: the empty tile's color.
const PLAIN_GRASS_COLOR := Color8(115, 197, 164)

# PLACEHOLDER (art): shapes the size of their hurtboxes until there are
# sprites. Player colors are in palette.gd, dummy colors on each dummy kind.
## The strip over the floor where a dummy is about to charge. Untuned.
const CHARGE_CUE_COLOR := Color(1, 0.55, 0, 0.5)
## How long the strip stays at the charge's full length before the charge.
## It grows to that length over the rest of the aim lock. Untuned.
const CHARGE_CUE_HOLD_SEC := 0.1
## A struck dummy's flash.
const FLASH_COLOR := Color.WHITE
## Laid over the whole of an invulnerable player, outline and facing line
## included, for as long as they can't be hurt. Untuned.
const INVULNERABLE_COLOR := Color(1, 1, 1, 0.5)
## How long a struck dummy shows white. Untuned.
const DUMMY_FLASH_SEC := 0.15
const SWING_COLOR := Color(1, 1, 1, 0.3)
const PROJECTILE_COLOR := Color(1, 0.1, 0.1)
## One flat color, so the wall's pieces read as one wall.
const WALL_COLOR := Color(0.35, 0.35, 0.4)
## A shut door, filling its gap in the wall. PLACEHOLDER (art): brown until
## doors have textures.
const DOOR_COLOR := Color(0.45, 0.3, 0.15)
## Facing marks and your own player's outline.
const MARKING_COLOR := Color.WHITE
const FACING_WIDTH := 2.0
const OUTLINE_WIDTH := 1.0
## Straight edges around a round outline.
const OUTLINE_SEGMENTS := 32
const LABEL_COLOR := Color.WHITE
const LABEL_FONT_SIZE := 8
## Centered on the dummy; wide enough for the longest label.
const LABEL_WIDTH := 120.0
## From the top of the dummy to the label's baseline.
const LABEL_GAP := 3.0

static var _player_hurtbox: Shape2D = ClientLoader.player_hurtbox

## Under each shut door in town until everyone is ready. PLACEHOLDER
## (design): the wording.
const WAITING_TEXT := "WAITING FOR READY"

var _view: WorldView
var _grass_sheet: Texture2D
## The [enum GrassTile] of each floor cell, row by row, for
## [member _floor_seed].
var _floor_tiles := PackedInt32Array()
var _floor_seed := -1
var _my_id := 0
var _waiting_for_ready := false


## How far ahead of [param d]'s edge its charge cue reaches, in px; 0 when
## there's none to draw. An aim lock no longer than [constant
## CHARGE_CUE_HOLD_SEC] shows the full length at once.
static func charge_cue_length(d: WorldView.Dummy) -> float:
	if d.charge_windup_ticks_left <= 0:
		return 0.0
	var look := ClientLoader.dummy_looks[d.kind]
	var lock_sec := look.charge_lock_sec
	var grow_sec := lock_sec - CHARGE_CUE_HOLD_SEC
	if grow_sec <= 0:
		return look.charge_length
	var since_lock := lock_sec - GameTime.seconds(d.charge_windup_ticks_left)
	return look.charge_length * minf(since_lock / grow_sec, 1.0)


## Distance from [param shape]'s center to its edge in direction [param dir]:
## a circle's radius, else its bounding box's edge.
## [param d]'s charge cue in arena px: a strip as wide as the dummy, from
## its edge along its facing for [method charge_cue_length], cut off at the
## floor's edge. Empty when there's none to draw.
static func charge_cue_strip(d: WorldView.Dummy) -> Array[PackedVector2Array]:
	var length := charge_cue_length(d)
	if length == 0.0:
		return []
	var bounds := ClientLoader.dummy_looks[d.kind].hurtbox.get_rect()
	var strip := Rect2(bounds.end.x, bounds.position.y, length, bounds.size.y)
	var corners := PackedVector2Array([
		strip.position, Vector2(strip.end.x, strip.position.y),
		strip.end, Vector2(strip.position.x, strip.end.y),
	])
	var floor_area := ClientLoader.floor_area
	var floor_corners := PackedVector2Array([
		floor_area.position, Vector2(floor_area.end.x, floor_area.position.y),
		floor_area.end, Vector2(floor_area.position.x, floor_area.end.y),
	])
	return Geometry2D.intersect_polygons(
			Transform2D(d.facing.angle(), d.pos) * corners, floor_corners)


## The [enum GrassTile] of each cell of a floor [param cells] across, row by
## row: picked by [param weights], the same for the same
## [param graphics_seed].
static func floor_tiles(graphics_seed: int, cells: Vector2i,
		weights: Array[float]) -> PackedInt32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = graphics_seed
	var odds := PackedFloat32Array(weights)
	var out := PackedInt32Array()
	out.resize(cells.x * cells.y)
	for i in out.size():
		out[i] = rng.rand_weighted(odds)
	return out


static func _to_edge(shape: Shape2D, dir: Vector2) -> float:
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius
	var half := shape.get_rect().size / 2
	var x := half.x / absf(dir.x) if not is_zero_approx(dir.x) else INF
	var y := half.y / absf(dir.y) if not is_zero_approx(dir.y) else INF
	return minf(x, y)


func _ready() -> void:
	# Whole sheet pixels, not blurred, at GRASS_SCALE.
	texture_filter = TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(GRASS_SHEET_PATH):
		_grass_sheet = load(GRASS_SHEET_PATH)
	else:
		push_error("No floor art at %s; drawing the floor plain." % GRASS_SHEET_PATH)


## Draws [param view] (null draws only the walls). [param my_id] is your
## seat; [param waiting_for_ready] whether this is town and someone isn't
## ready.
func show_view(view: WorldView, my_id: int, waiting_for_ready: bool) -> void:
	_view = view
	if view and view.graphics_seed != _floor_seed:
		_floor_seed = view.graphics_seed
		_floor_tiles = floor_tiles(_floor_seed, _floor_cells(), GRASS_WEIGHTS)
	_my_id = my_id
	_waiting_for_ready = waiting_for_ready
	queue_redraw()


func _draw() -> void:
	if not _view:
		for wall in ClientLoader.walls(0):
			draw_rect(wall, WALL_COLOR)
		return
	_draw_floor()
	for wall in ClientLoader.walls(_view.door_bits):
		draw_rect(wall, WALL_COLOR)
	if not _view.room_cleared:
		for door in ClientLoader.doors(_view.door_bits):
			draw_rect(door, DOOR_COLOR)
			if _waiting_for_ready:
				_draw_label_below(door, WAITING_TEXT)
	# Over the floor, under every body.
	for d in _view.dummies:
		_draw_charge_cue(d)
	for d in _view.dummies:
		_draw_dummy(d)
	var mine: WorldView.Player = null
	for p in _view.players:
		if p.id == _my_id:
			mine = p
		else:
			_draw_player(p)
	if mine:
		_draw_player(mine)
	# On top, so a shot is seen up to the moment it hits.
	for s in _view.projectiles:
		draw_circle(s.pos, s.radius, PROJECTILE_COLOR)


## Floor cells across and down: enough to fill the viewport, so the last
## row may be cut off at its bottom edge.
func _floor_cells() -> Vector2i:
	return Vector2i((get_viewport_rect().size / FLOOR_CELL_SIZE).ceil())


## The whole viewport, walls included: they're drawn over it.
func _draw_floor() -> void:
	if not _grass_sheet:
		draw_rect(get_viewport_rect(), PLAIN_GRASS_COLOR)
		return
	var cells := _floor_cells()
	var tile := Vector2.ONE * GRASS_TILE_SIZE
	var cell := Vector2.ONE * FLOOR_CELL_SIZE
	for y in cells.y:
		for x in cells.x:
			var sheet_cell := GRASS_SHEET_CELLS[_floor_tiles[y * cells.x + x]]
			draw_texture_rect_region(_grass_sheet, Rect2(Vector2(x, y) * cell, cell),
					Rect2(Vector2(sheet_cell) * tile, tile))


## Its hurtbox's shape, turned with its facing; the label stays upright.
func _draw_dummy(d: WorldView.Dummy) -> void:
	var flashing := GameTime.seconds(d.ticks_since_struck) < DUMMY_FLASH_SEC
	var kind := ClientLoader.dummy_looks[d.kind]
	var hurtbox := kind.hurtbox
	# Unturned, so the label sits over it whatever its facing.
	var bounds := hurtbox.get_rect()
	# Drawn around the dummy's center, with +x along its facing.
	draw_set_transform(d.pos, d.facing.angle())
	hurtbox.draw(get_canvas_item(), FLASH_COLOR if flashing else kind.color)
	if kind.nose_size > 0:
		_draw_nose(bounds.end.x, kind.nose_size)
	draw_set_transform(Vector2.ZERO)
	if kind.label:
		_draw_label(Vector2(d.pos.x, d.pos.y + bounds.position.y - LABEL_GAP), kind.label)


## Centered under [param rect], [constant LABEL_GAP] below it. Town's only
## door is in the north wall, so below is into the room.
func _draw_label_below(rect: Rect2, text: String) -> void:
	_draw_label(Vector2(rect.get_center().x, rect.end.y + LABEL_GAP + LABEL_FONT_SIZE), text)


## Centered on [param baseline_center].
func _draw_label(baseline_center: Vector2, text: String) -> void:
	draw_string(ThemeDB.fallback_font, baseline_center - Vector2(LABEL_WIDTH / 2, 0), text,
			HORIZONTAL_ALIGNMENT_CENTER, LABEL_WIDTH, LABEL_FONT_SIZE, LABEL_COLOR)


## As wide as the dummy, from its edge along its facing.
func _draw_charge_cue(d: WorldView.Dummy) -> void:
	for piece in charge_cue_strip(d):
		draw_colored_polygon(piece, CHARGE_CUE_COLOR)


func _draw_player(p: WorldView.Player) -> void:
	if p.swing_ticks > 0:
		_draw_swing(p.pos, p.facing, p.swing_ticks)
	var color := Palette.player_color(p.id)
	# Unturned, like the player's hurtbox.
	draw_set_transform(p.pos)
	_player_hurtbox.draw(
			get_canvas_item(), color.darkened(Palette.DOWNED_DARKEN) if p.is_downed() else color)
	if p.id == _my_id:
		_draw_outline(_player_hurtbox)
	draw_line(Vector2.ZERO, p.facing * _to_edge(_player_hurtbox, p.facing),
			MARKING_COLOR, FACING_WIDTH)
	if p.invulnerable:
		_player_hurtbox.draw(get_canvas_item(), INVULNERABLE_COLOR)
	draw_set_transform(Vector2.ZERO)


## Inset by half its width, so it's drawn inside [param shape]: a circle's
## round edge, else its bounding box.
func _draw_outline(shape: Shape2D) -> void:
	if shape is CircleShape2D:
		var radius := (shape as CircleShape2D).radius - OUTLINE_WIDTH / 2
		draw_arc(Vector2.ZERO, radius, 0, TAU, OUTLINE_SEGMENTS, MARKING_COLOR, OUTLINE_WIDTH)
		return
	draw_rect(shape.get_rect().grow(-OUTLINE_WIDTH / 2), MARKING_COLOR, false, OUTLINE_WIDTH)


## An equilateral triangle on the front edge, [param front] px ahead of the
## center, pointing along +x.
func _draw_nose(front: float, size: float) -> void:
	var height := size * sqrt(3.0) / 2
	draw_colored_polygon(PackedVector2Array([
		Vector2(front + height, 0),
		Vector2(front, -size / 2),
		Vector2(front, size / 2),
	]), MARKING_COLOR)


## The slice active with [param ticks_left] of the swing left, from
## [member ClientLoader.swing_offset] ahead of [param pos], where it starts.
func _draw_swing(pos: Vector2, facing: Vector2, ticks_left: int) -> void:
	var turn := ClientLoader.swing_turn(ticks_left)
	var at := Transform2D(facing.angle() + turn, pos + facing * ClientLoader.swing_offset)
	for piece in ClientLoader.swing_pieces:
		draw_colored_polygon(at * piece, SWING_COLOR)
