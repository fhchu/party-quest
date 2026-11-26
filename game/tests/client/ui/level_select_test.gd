extends GdUnitTestSuite
## The level select overlay: a square per level, the cursor on one, taps.

const LevelSelect := preload("res://client/ui/level_select.gd")
const LevelSelectScene := preload("res://client/ui/level_select.tscn")
const ClientLoader := preload("res://client/client_loader.gd")

## Its own count, so the test doesn't depend on today's levels.
const LEVEL_COUNT := 3

var _overlay: LevelSelect


func before_test() -> void:
	ClientLoader.level_count = LEVEL_COUNT
	_overlay = auto_free(LevelSelectScene.instantiate())
	add_child(_overlay)


func after_test() -> void:
	ClientLoader.level_count = ClientLoader.LEVELS.runs.size()


func test_it_shows_a_numbered_square_per_level() -> void:
	assert_array(_square_numbers()).is_equal(["1", "2", "3"])


func test_the_cursor_shows_only_at_its_level() -> void:
	_overlay.show_level_select(true, 1)
	var shown: Array[int] = []
	for level in LEVEL_COUNT:
		if _cursor(level).modulate.a > 0.0:
			shown.append(level)
	assert_array(shown).is_equal([1])


func test_it_hides_when_shut() -> void:
	_overlay.show_level_select(true, 0)
	_overlay.show_level_select(false, 0)
	assert_bool(_overlay.visible).is_false()


func test_pressing_a_square_names_its_level() -> void:
	var tapped: Array[int] = []
	_overlay.level_tapped.connect(func(level: int) -> void: tapped.append(level))
	_button(1).pressed.emit()
	assert_array(tapped).is_equal([1])


func _square(level: int) -> Node:
	return _overlay.get_node("%Squares").get_child(level)


func _cursor(level: int) -> CanvasItem:
	return _square(level).get_node("%Cursor")


func _button(level: int) -> Button:
	return _square(level).get_node("%Button")


func _square_numbers() -> Array[String]:
	var out: Array[String] = []
	for square in _overlay.get_node("%Squares").get_children():
		out.append((square.get_node("%Button") as Button).text)
	return out
