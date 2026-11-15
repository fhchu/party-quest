extends Node2D
## Draws the arena from one snapshot: walls, dummies with their labels,
## swings, players and shots. Your own character is drawn last, so it's on top.
## Holds no game state; GameView hands it what to draw.

const GameTime := preload("res://shared/game_time.gd")
const Balance := preload("res://shared/data/balance.gd")
const DummyKinds := preload("res://shared/data/dummy_kinds.gd")
const RoomShape := preload("res://shared/room_shape.gd")
const SwingShape := preload("res://shared/swing_shape.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Palette := preload("res://client/palette.gd")

# PLACEHOLDER (art): shapes the size of their hurtboxes until there are
# sprites. Player colors are in palette.gd, dummy colors in _looks below.
## READY's and the turret's.
const DUMMY_COLOR := Color(0.8, 0.65, 0.4)
## The charger's.
const CHARGER_COLOR := Color(0.2, 0.7, 0.3)
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
## The side of the nose on a dummy that shows its facing, in px.
const NOSE_SIZE := 4.0
const OUTLINE_WIDTH := 1.0
## Straight edges around a round outline.
const OUTLINE_SEGMENTS := 32
const LABEL_COLOR := Color.WHITE
const LABEL_FONT_SIZE := 8
## Centered on the dummy; wide enough for the longest label.
const LABEL_WIDTH := 120.0
## From the top of the dummy to the label's baseline.
const LABEL_GAP := 3.0

const BALANCE: Balance = preload("res://shared/data/balance.tres")
const DUMMY_KINDS: DummyKinds = preload("res://shared/data/dummy_kinds.tres")
const READY_KIND := preload("res://shared/data/dummy_kinds/ready.tres")
const START_KIND := preload("res://shared/data/dummy_kinds/start.tres")
const TURRET_KIND := preload("res://shared/data/dummy_kinds/turret.tres")
const CHARGER_KIND := preload("res://shared/data/dummy_kinds/charger.tres")

static var _player_hurtbox: Shape2D = BALANCE.player_hurtbox
static var _swing_offset: float = BALANCE.swing_offset
static var _swing_arc: float = BALANCE.swing_arc()
static var _swing_slices: int = BALANCE.swing_slices
static var _swing_ticks := GameTime.ticks(BALANCE.swing_active_sec)
# PLACEHOLDER (art): the swing's active slice as a pie slice pointing along
# +x, until it's a sprite or an animation.
static var _swing_pieces: Array[PackedVector2Array] = SwingShape.pieces(
		BALANCE.swing_radius, _swing_arc / _swing_slices)

# PLACEHOLDER (design): the labels' wording.
## How each dummy kind is drawn. START turns green once everyone is ready;
## its waiting red isn't grey, because the background is grey.
static var _looks: Dictionary[int, DummyLook] = {
	DUMMY_KINDS.index_of(READY_KIND): DummyLook.new(DUMMY_COLOR, "READY"),
	DUMMY_KINDS.index_of(START_KIND): DummyLook.new(
			Color(0.7, 0.2, 0.15), "WAITING FOR READY",
			DummyLook.new(Color(0.2, 0.9, 0.3), "START")),
	DUMMY_KINDS.index_of(TURRET_KIND): DummyLook.new(DUMMY_COLOR, "", null, true),
	DUMMY_KINDS.index_of(CHARGER_KIND): DummyLook.new(CHARGER_COLOR, ""),
}

var _view: Snapshot
var _my_id := 0
var _start_live := false


## How a dummy of [param kind] is drawn. [param start_live] is whether
## everyone is ready.
static func dummy_look(kind: int, start_live: bool) -> DummyLook:
	var look := _looks[kind]
	return look.when_live if start_live and look.when_live else look


## How far ahead of [param d]'s edge its charge cue reaches, in px; 0 when
## there's none to draw. An aim lock no longer than [constant
## CHARGE_CUE_HOLD_SEC] shows the full length at once.
static func charge_cue_length(d: Snapshot.Dummy) -> float:
	if d.charge_windup_ticks_left <= 0:
		return 0.0
	var charge := DUMMY_KINDS.kinds[d.kind].charge
	var lock_sec := GameTime.seconds(GameTime.ticks(charge.aim_lock_sec))
	var grow_sec := lock_sec - CHARGE_CUE_HOLD_SEC
	if grow_sec <= 0:
		return charge.length
	var since_lock := lock_sec - GameTime.seconds(d.charge_windup_ticks_left)
	return charge.length * minf(since_lock / grow_sec, 1.0)


## Distance from [param shape]'s center to its edge in direction [param dir]:
## a circle's radius, else its bounding box's edge.
## [param d]'s charge cue in arena px: a strip as wide as the dummy, from
## its edge along its facing for [method charge_cue_length], cut off at the
## floor's edge. Empty when there's none to draw.
static func charge_cue_strip(d: Snapshot.Dummy) -> Array[PackedVector2Array]:
	var length := charge_cue_length(d)
	if length == 0.0:
		return []
	var bounds := DUMMY_KINDS.kinds[d.kind].hurtbox_or_default().get_rect()
	var strip := Rect2(bounds.end.x, bounds.position.y, length, bounds.size.y)
	var corners := PackedVector2Array([
		strip.position, Vector2(strip.end.x, strip.position.y),
		strip.end, Vector2(strip.position.x, strip.end.y),
	])
	var floor_area := RoomShape.floor_area()
	var floor_corners := PackedVector2Array([
		floor_area.position, Vector2(floor_area.end.x, floor_area.position.y),
		floor_area.end, Vector2(floor_area.position.x, floor_area.end.y),
	])
	return Geometry2D.intersect_polygons(
			Transform2D(d.facing.angle(), d.pos) * corners, floor_corners)


static func _to_edge(shape: Shape2D, dir: Vector2) -> float:
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius
	var half := shape.get_rect().size / 2
	var x := half.x / absf(dir.x) if not is_zero_approx(dir.x) else INF
	var y := half.y / absf(dir.y) if not is_zero_approx(dir.y) else INF
	return minf(x, y)


## Draws [param view] (null draws only the walls). [param my_id] is your
## seat; [param start_live] whether everyone in town is ready.
func show_view(view: Snapshot, my_id: int, start_live: bool) -> void:
	_view = view
	_my_id = my_id
	_start_live = start_live
	queue_redraw()


func _draw() -> void:
	if not _view:
		for wall in RoomShape.walls([]):
			draw_rect(wall, WALL_COLOR)
		return
	var door_sides := RoomShape.sides_in(_view.door_bits)
	for wall in RoomShape.walls(door_sides):
		draw_rect(wall, WALL_COLOR)
	if not _view.room_cleared:
		for side in door_sides:
			draw_rect(RoomShape.door(side), DOOR_COLOR)
	# Over the floor, under every body.
	for d in _view.dummies:
		_draw_charge_cue(d)
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
	# On top, so a shot is seen up to the moment it hits.
	for s in _view.projectiles:
		draw_circle(s.pos, s.radius, PROJECTILE_COLOR)


## Its hurtbox's shape, turned with its facing; the label stays upright.
func _draw_dummy(d: Snapshot.Dummy) -> void:
	var look := dummy_look(d.kind, _start_live)
	var age := d.ticks_since_struck
	var flashing := age >= 0 and GameTime.seconds(age) < DUMMY_FLASH_SEC
	var hurtbox := DUMMY_KINDS.kinds[d.kind].hurtbox_or_default()
	# Unturned, so the label sits over it whatever its facing.
	var bounds := hurtbox.get_rect()
	# Drawn around the dummy's center, with +x along its facing.
	draw_set_transform(d.pos, d.facing.angle())
	hurtbox.draw(get_canvas_item(), FLASH_COLOR if flashing else look.color)
	if look.shows_facing:
		_draw_nose(bounds.end.x)
	draw_set_transform(Vector2.ZERO)
	if look.label:
		var at := Vector2(d.pos.x - LABEL_WIDTH / 2, d.pos.y + bounds.position.y - LABEL_GAP)
		draw_string(ThemeDB.fallback_font, at, look.label, HORIZONTAL_ALIGNMENT_CENTER,
				LABEL_WIDTH, LABEL_FONT_SIZE, LABEL_COLOR)


## As wide as the dummy, from its edge along its facing.
func _draw_charge_cue(d: Snapshot.Dummy) -> void:
	for piece in charge_cue_strip(d):
		draw_colored_polygon(piece, CHARGE_CUE_COLOR)


func _draw_player(p: Snapshot.Player) -> void:
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
func _draw_nose(front: float) -> void:
	var height := NOSE_SIZE * sqrt(3.0) / 2
	draw_colored_polygon(PackedVector2Array([
		Vector2(front + height, 0),
		Vector2(front, -NOSE_SIZE / 2),
		Vector2(front, NOSE_SIZE / 2),
	]), MARKING_COLOR)


## The slice active with [param ticks_left] of the swing left, from
## [member _swing_offset] ahead of [param pos], where it starts.
func _draw_swing(pos: Vector2, facing: Vector2, ticks_left: int) -> void:
	var turn := SwingShape.slice_turn(
			_swing_arc, _swing_slices, _swing_ticks - ticks_left, _swing_ticks)
	var at := Transform2D(facing.angle() + turn, pos + facing * _swing_offset)
	for piece in _swing_pieces:
		draw_colored_polygon(at * piece, SWING_COLOR)


## A dummy kind's color and the label over it (empty for none).
class DummyLook:
	var color: Color
	var label: String
	## Replaces this look once everyone in town is ready; null if it
	## doesn't change.
	var when_live: DummyLook
	## Draw a nose on the side it faces.
	var shows_facing: bool

	func _init(
			look_color: Color, look_label: String, live: DummyLook = null,
			facing_shown := false) -> void:
		color = look_color
		label = look_label
		when_live = live
		shows_facing = facing_shown
