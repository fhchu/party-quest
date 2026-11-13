extends GdUnitTestSuite

const DummyKinds := preload("res://tests/dummy_kinds.gd")
const ArenaView := preload("res://client/arena_view.gd")


func test_every_dummy_kind_has_a_look() -> void:
	for kind in DummyKinds.DUMMY_KINDS.kinds.size():
		for start_live: bool in [false, true]:
			assert_object(ArenaView.dummy_look(kind, start_live)).is_not_null()
