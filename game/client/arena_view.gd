extends Node2D
## Draws the arena from one snapshot: walls, dummies with their labels,
## swings, players and shots. Your own character is drawn last, so it's on top.
## Holds no game state; GameView hands it what to draw.

const GameTime := preload("res://shared/game_time.gd")
const Balance := preload("res://shared/data/balance.gd")
const DummyKinds := preload("res://shared/data/dummy_kinds.gd")
const RoomShape := preload("res://shared/room_shape.gd")
const Snapshot := preload("res://net/snapshot.gd")
const Palette := preload("res://client/palette.gd")

# PLACEHOLDER (art): shapes the size of their hurtboxes until there are
# sprites. Player colors are in palette.gd, dummy colors in _looks below.
## READY's and the turret's.
const DUMMY_COLOR := Color(0.8, 0.65, 0.4)
## The charger's.
const CHARGER_COLOR := Color(0.2, 0.7, 0.3)
## A struck dummy's flash.
const FLASH_COLOR := Color.WHITE
## Laid over the whole of an invulnerable player, outline and facing line
## included, for as long as they can't be hurt. Untuned.
const INVULNERABLE_COLOR := Color(1, 1, 1, 0.5)
## How long a struck dummy shows white. Untuned.
const DUMMY_FLASH_SEC := 0.15
const SWING_COLOR := Color(1, 1, 1, 0.3)
## Straight edges along the swing's curved side.
const SWING_SEGMENTS := 12
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

static var _player_hurtbox: Vector2 = BALANCE.player_hurtbox
# PLACEHOLDER (art): the swing's reach as a pie slice pointing along +x,
# until it's a sprite or an animation.
static var _swing_shape: PackedVector2Array = _pie_slice(
		BALANCE.swing_radius, BALANCE.swing_arc())

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


static func _pie_slice(radius: float, arc: float) -> PackedVector2Array:
	var points := PackedVector2Array([Vector2.ZERO])
	for i in SWING_SEGMENTS + 1:
		var angle := lerpf(-arc / 2, arc / 2, float(i) / SWING_SEGMENTS)
		points.append(Vector2.from_angle(angle) * radius)
	return points


static func _centered_box(center: Vector2, size: Vector2) -> Rect2:
	return Rect2(center - size / 2, size)


## Distance from a box's center to its edge in direction [param dir].
static func _to_box_edge(dir: Vector2, half: Vector2) -> float:
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
	var hurtbox := DUMMY_KINDS.kinds[d.kind].hurtbox
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


func _draw_player(p: Snapshot.Player) -> void:
	if p.swing_ticks > 0:
		_draw_swing(p.pos, p.facing)
	# Only the swing may leave the hurtbox, so a player at a wall stays on screen.
	var box := _centered_box(p.pos, _player_hurtbox)
	var color := Palette.player_color(p.id)
	draw_rect(box, color.darkened(Palette.DOWNED_DARKEN) if p.is_downed() else color)
	if p.id == _my_id:
		# Inset by half its width, so it's drawn inside the box.
		draw_rect(box.grow(-OUTLINE_WIDTH / 2), MARKING_COLOR, false, OUTLINE_WIDTH)
	var edge := p.pos + p.facing * _to_box_edge(p.facing, box.size / 2)
	draw_line(p.pos, edge, MARKING_COLOR, FACING_WIDTH)
	if p.invulnerable:
		draw_rect(box, INVULNERABLE_COLOR)


## An equilateral triangle on the front edge, [param front] px ahead of the
## center, pointing along +x.
func _draw_nose(front: float) -> void:
	var height := NOSE_SIZE * sqrt(3.0) / 2
	draw_colored_polygon(PackedVector2Array([
		Vector2(front + height, 0),
		Vector2(front, -NOSE_SIZE / 2),
		Vector2(front, NOSE_SIZE / 2),
	]), MARKING_COLOR)


func _draw_swing(pos: Vector2, facing: Vector2) -> void:
	draw_colored_polygon(Transform2D(facing.angle(), pos) * _swing_shape, SWING_COLOR)


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
