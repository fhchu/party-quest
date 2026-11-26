extends GdUnitTestSuite
## The level select overlay: a square per level, the cursor on one, taps.

const LevelSelect := preload("res://client/ui/level_select.gd")
const LevelSelectScene := preload("res://client/ui/level_select.tscn")
const ClientLoader := preload("res://client/client_loader.gd")

var _overlay: LevelSelect


func before_test() -> void:
	_overlay = auto_free(LevelSelectScene.instantiate())
	add_child(_overlay)


func test_it_shows_a_numbered_square_per_level() -> void:
	var numbers: Array[String] = []
	for level in ClientLoader.level_count:
		numbers.append(str(level + 1))
	assert_array(_square_numbers()).is_equal(numbers)


func test_the_cursor_shows_only_at_its_level() -> void:
	_overlay.show_level_select(true, 1)
	var shown: Array[int] = []
	for level in ClientLoader.level_count:
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
	for level in ClientLoader.level_count:
		out.append(_button(level).text)
	return out
