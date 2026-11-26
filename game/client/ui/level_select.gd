extends CanvasLayer
## The level select over town: a numbered square per level in a row, and the
## cursor pointing at the party's chosen one. The whole party moves one
## cursor; the server says where it is. Tapping or clicking a square chooses
## that level.

## [param level] is the tapped square's, from 0.
signal level_tapped(level: int)

const ClientLoader := preload("res://client/client_loader.gd")
const WorldRenderer := preload("res://client/world_renderer.gd")
const SquareScene := preload("res://client/ui/level_square.tscn")

## The button states a square looks the same in.
const SQUARE_STYLES: Array[StringName] = [&"normal", &"hover", &"pressed"]
const SQUARE_FONT_COLORS: Array[StringName] = [
	&"font_color", &"font_hover_color", &"font_pressed_color"]

@onready var _squares: HBoxContainer = %Squares


func _ready() -> void:
	# The town's colors: walls behind, grass squares numbered in wall green.
	(%Background as ColorRect).color = WorldRenderer.WALL_COLOR
	var square_style := StyleBoxFlat.new()
	square_style.bg_color = WorldRenderer.FLAT_FLOOR_COLOR
	for level in ClientLoader.level_count:
		var square: Control = SquareScene.instantiate()
		_squares.add_child(square)
		(square.get_node("%Cursor") as TextureRect).texture = ClientLoader.cursor_texture
		var button: Button = square.get_node("%Button")
		for style in SQUARE_STYLES:
			button.add_theme_stylebox_override(style, square_style)
		for font_color in SQUARE_FONT_COLORS:
			button.add_theme_color_override(font_color, WorldRenderer.WALL_COLOR)
		# Levels are numbered from 1 for players.
		button.text = str(level + 1)
		button.pressed.connect(level_tapped.emit.bind(level))


## Shows it with the cursor at [param cursor], from 0, or hides it when not
## [param open].
func show_level_select(open: bool, cursor: int) -> void:
	visible = open
	for level in _squares.get_child_count():
		var cursor_mark: CanvasItem = _squares.get_child(level).get_node("%Cursor")
		# Transparent rather than hidden, so every square keeps its place.
		cursor_mark.modulate.a = 1.0 if level == cursor else 0.0
