extends Node2D
## Draws the arena from one snapshot: the floor, walls, doors and the label
## under a shut town door, dummies with their labels, swings, players and
## shots.
## Your own character is drawn last, so it's on top.
## Holds no game state; GameRenderer hands it what to draw.

const ClientLoader := preload("res://client/client_loader.gd")
const WorldView := preload("res://client/world_view.gd")
const Palette := preload("res://client/palette.gd")

## The custom data layer on each floor tile: its density level, 0 for bare
## ground and higher for denser.
const DENSITY_LEVEL_DATA := "density_level"
## Each pixel of a floor tile is drawn this many screen px across.
const FLOOR_SCALE := 2
## How often each density level is picked, relative to the others, sparsest
## first: one per level in client/assets/textures/grass.tres, which must have a
## tile at each.
const DENSITY_WEIGHTS: Array[float] = [8.0, 4.0, 2.0, 1.0]
## The whole floor when there's no tile set. Fresh clones can't load the tile
## set: its image is ignored, keeping the art out of the public repo.
const FLAT_FLOOR_COLOR := Color("73c5a4")

# Players and dummies are drawn as shapes the size of their hurtboxes. Player
# colors are in palette.gd, dummy colors on each dummy kind.
## The strip over the floor where a dummy is about to charge.
const CHARGE_CUE_COLOR := Color(1, 0.55, 0, 0.5)
## How long the strip stays at the charge's full length before the charge.
## It grows to that length over the rest of the aim lock.
const CHARGE_CUE_HOLD_SEC := 0.1
## A struck dummy's flash.
const FLASH_COLOR := Color.WHITE
## Laid over the whole of an invulnerable player, outline and facing line
## included, for as long as they can't be hurt.
const INVULNERABLE_COLOR := Color(1, 1, 1, 0.5)
## How long a struck dummy shows white.
const DUMMY_FLASH_SEC := 0.15
const SWING_COLOR := Color.WHITE
const PROJECTILE_COLOR := Color(1, 0.1, 0.1)
## One flat color, so the wall's pieces read as one wall.
const WALL_COLOR := Color(0.35, 0.35, 0.4)
## A shut door, filling its gap in the wall.
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

## Under each shut door in town until everyone is ready.
const WAITING_TEXT := "WAITING FOR READY"

var _view: WorldView
## Drawn under everything else; null if [method _ready] finds no tile set.
var _floor: TileMapLayer
## [method tiles_by_density] of the floor's tile set.
var _density_tiles: Array[Array] = []
## The graphics seed the floor was last filled from; -1, which no graphics
## seed is, until the first.
var _floor_seed := -1
var _my_id := 0
## See [member GameView.slot_looks].
var _slot_looks: Dictionary[int, Array] = {}
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


## The density level of each cell of a floor [param cells] across, row by
## row: picked by [param weights], the same for the same
## [param graphics_seed].
static func floor_density(graphics_seed: int, cells: Vector2i,
		weights: Array[float]) -> PackedInt32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = graphics_seed
	var odds := PackedFloat32Array(weights)
	var out := PackedInt32Array()
	out.resize(cells.x * cells.y)
	for i in out.size():
		out[i] = rng.rand_weighted(odds)
	return out


## The atlas coords of [param tile_set]'s tiles at each density level, from
## its first source, sparsest level first.
static func tiles_by_density(tile_set: TileSet) -> Array[Array]:
	var source: TileSetAtlasSource = tile_set.get_source(tile_set.get_source_id(0))
	var out: Array[Array] = []
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		var level: int = source.get_tile_data(coords, 0).get_custom_data(
				DENSITY_LEVEL_DATA)
		while out.size() <= level:
			out.append([])
		out[level].append(coords)
	return out


static func _to_edge(shape: Shape2D, dir: Vector2) -> float:
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius
	var half := shape.get_rect().size / 2
	var x := half.x / absf(dir.x) if not is_zero_approx(dir.x) else INF
	var y := half.y / absf(dir.y) if not is_zero_approx(dir.y) else INF
	return minf(x, y)


func _ready() -> void:
	var tile_set: TileSet = load("res://client/assets/textures/grass.tres")
	if not tile_set:
		push_error("No floor tiles; drawing the floor flat.")
		return
	_floor = TileMapLayer.new()
	_floor.tile_set = tile_set
	_density_tiles = tiles_by_density(_floor.tile_set)
	_floor.scale = Vector2.ONE * FLOOR_SCALE
	# Whole tile pixels, not blurred, at FLOOR_SCALE.
	_floor.texture_filter = TEXTURE_FILTER_NEAREST
	# Under the walls and everything else this node draws.
	_floor.z_index = -1
	add_child(_floor)


## Draws [param view] (null draws only the walls). [param my_id] is your
## seat; [param waiting_for_ready] whether this is town and someone isn't
## ready; [param slot_looks] what each seat holds in each slot (see
## [member GameView.slot_looks]).
func show_view(view: WorldView, my_id: int, waiting_for_ready: bool,
		slot_looks: Dictionary[int, Array]) -> void:
	_view = view
	_slot_looks = slot_looks
	if view and _floor and view.graphics_seed != _floor_seed:
		_floor_seed = view.graphics_seed
		_fill_floor()
	_my_id = my_id
	_waiting_for_ready = waiting_for_ready
	queue_redraw()


func _draw() -> void:
	if not _view:
		for wall in ClientLoader.walls(0):
			draw_rect(wall, WALL_COLOR)
		return
	if not _floor:
		draw_rect(get_viewport_rect(), FLAT_FLOOR_COLOR)
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


## Covers the whole viewport, walls included: they're drawn over it, so the
## last row may be cut off at its bottom edge. Each density level's tiles are
## picked from evenly.
func _fill_floor() -> void:
	var cell := Vector2(_floor.tile_set.tile_size * FLOOR_SCALE)
	var cells := Vector2i((get_viewport_rect().size / cell).ceil())
	var levels := floor_density(_floor_seed, cells, DENSITY_WEIGHTS)
	var rng := RandomNumberGenerator.new()
	# Apart from floor_density's numbers, so the pick within a level doesn't
	# follow the level.
	rng.seed = hash([_floor_seed, "tiles"])
	var source := _floor.tile_set.get_source_id(0)
	_floor.clear()
	for y in cells.y:
		for x in cells.x:
			var choices: Array = _density_tiles[levels[y * cells.x + x]]
			var tile: Vector2i = choices[rng.randi_range(0, choices.size() - 1)]
			_floor.set_cell(Vector2i(x, y), source, tile)


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
	var looks: Array = _slot_looks.get(p.id, [])
	for i in mini(p.slot_ticks.size(), looks.size()):
		var look: ClientLoader.ItemLook = looks[i]
		if p.slot_ticks[i] > 0 and look and look.swing:
			_draw_swing(p.pos, p.facing, look.swing, p.slot_ticks[i])
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


## The slice of [param swing] active on its tick [param tick], from its
## offset ahead of [param pos], where it starts.
func _draw_swing(pos: Vector2, facing: Vector2, swing: ClientLoader.SwingLook, tick: int) -> void:
	var at := Transform2D(facing.angle() + swing.turn(tick), pos + facing * swing.offset)
	for piece in swing.pieces:
		draw_colored_polygon(at * piece, SWING_COLOR)
