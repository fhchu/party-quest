extends GdUnitTestSuite

const Protocol := preload("res://net/protocol.gd")
const ArenaView := preload("res://client/arena_view.gd")


func test_every_dummy_kind_has_a_look() -> void:
	for kind: Protocol.DummyKind in Protocol.DummyKind.values():
		for start_live: bool in [false, true]:
			assert_object(ArenaView.dummy_look(kind, start_live)).is_not_null()
