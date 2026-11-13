extends GdUnitTestSuite
## The game's data in shared/data/: what every map and run must keep true.

const Condition := preload("res://shared/data/condition.gd")
const Map := preload("res://shared/data/map.gd")
const RunSetup := preload("res://shared/data/run_setup.gd")
const DummyKinds := preload("res://shared/data/dummy_kinds.gd")

const MAPS_DIR := "res://shared/data/maps/"
const RUNS_DIR := "res://shared/data/runs/"
const DUMMY_KINDS: DummyKinds = preload("res://shared/data/dummy_kinds.tres")


func test_every_condition_sets_the_field_its_type_needs() -> void:
	for condition in _all_conditions():
		match condition.type:
			Condition.Type.DEFEAT_ALL:
				assert_object(condition.kind).is_not_null()
			Condition.Type.TIME_UP:
				assert_float(condition.sec).is_greater(0.0)
			Condition.Type.CLEAR_ROOM:
				assert_bool(condition.room is Map).is_true()


func test_every_kind_a_map_places_has_a_snapshot_number() -> void:
	for map in _resources_in(MAPS_DIR):
		for spot in (map as Map).dummies:
			assert_int(DUMMY_KINDS.index_of(spot.kind)).is_not_equal(-1)


func test_every_run_starts_somewhere_and_its_passages_join_two_maps() -> void:
	for run in _resources_in(RUNS_DIR):
		var setup := run as RunSetup
		assert_object(setup.start).is_not_null()
		for passage in setup.passages:
			assert_object(passage.from).is_not_null()
			assert_object(passage.to).is_not_null()


func _all_conditions() -> Array[Condition]:
	var out: Array[Condition] = []
	for map in _resources_in(MAPS_DIR):
		out.append_array((map as Map).clear_when)
	for run in _resources_in(RUNS_DIR):
		out.append_array((run as RunSetup).win)
		out.append_array((run as RunSetup).lose)
	return out


func _resources_in(dir: String) -> Array[Resource]:
	var out: Array[Resource] = []
	for file in ResourceLoader.list_directory(dir):
		if file.ends_with(".tres"):
			out.append(load(dir + file))
	return out
