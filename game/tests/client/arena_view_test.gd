extends GdUnitTestSuite

const ArenaView := preload("res://client/arena_view.gd")
const World := preload("res://sim/world.gd")


func test_every_dummy_kind_has_a_look() -> void:
	for kind: World.Kind in World.Kind.values():
		for start_live: bool in [false, true]:
			assert_object(ArenaView.dummy_look(kind, start_live)).is_not_null()
