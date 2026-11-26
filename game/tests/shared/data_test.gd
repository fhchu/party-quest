extends GdUnitTestSuite
## The game's data in shared/data/: what every room and run must keep true.

const Condition := preload("res://shared/data/condition.gd")
const Room := preload("res://shared/data/room.gd")
const RunSetup := preload("res://shared/data/run_setup.gd")
const DummyKinds := preload("res://shared/data/dummy_kinds.gd")
const DummyKind := preload("res://shared/data/dummy_kind.gd")
const Item := preload("res://shared/data/item.gd")
const Items := preload("res://shared/data/items.gd")
const LobbyState := preload("res://net/lobby_state.gd")
const ItemSword := preload("res://shared/data/items/item_sword.gd")
const ItemShield := preload("res://shared/data/items/item_shield.gd")
const EquipItem := preload("res://shared/data/items/equip_item.gd")

const ROOMS_DIR := "res://shared/data/rooms/"
const RUNS_DIR := "res://shared/data/runs/"
const DUMMY_KINDS: DummyKinds = preload("res://shared/data/dummy_kinds.tres")
const BALANCE := preload("res://shared/data/balance.tres")
const ITEMS: Items = preload("res://shared/data/items.tres")
const SWORD: ItemSword = preload("res://shared/data/items/item_sword.tres")
const ITEMS_DIR := "res://shared/data/items/"


func test_arena_fits_the_viewport() -> void:
	var viewport := Vector2(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	var arena: Rect2 = BALANCE.arena()
	assert_float(arena.end.x).is_less_equal(viewport.x)
	assert_float(arena.end.y).is_less_equal(viewport.y)


func test_every_item_has_its_own_id() -> void:
	var ids := ITEMS.items.map(func(item: Item) -> String: return item.id)
	assert_array(ids).not_contains([""])
	for id: String in ids:
		assert_int(ids.count(id)).override_failure_message("%s is used twice" % id).is_equal(1)


func test_every_item_has_a_display_name() -> void:
	for item: Item in ITEMS.items:
		assert_str(item.display_name).override_failure_message("%s has no name" % item.id) \
				.is_not_empty()


func test_every_item_file_is_in_the_list() -> void:
	for item in _resources_in(ITEMS_DIR):
		assert_array(ITEMS.items).contains([item])


func test_every_item_has_a_number_the_lobby_state_can_send() -> void:
	assert_int(ITEMS.items.size()).is_less_equal(LobbyState.NO_ITEM)


func test_every_item_that_guards_is_a_shield_with_a_size() -> void:
	for item in _items_that(EquipItem.Action.GUARD):
		assert_object(item).override_failure_message("%s isn't a shield" % item.id) \
				.is_instanceof(ItemShield)
		assert_float((item as ItemShield).thickness_px) \
				.override_failure_message("%s has no thickness" % item.id).is_greater(0.0)
		assert_float((item as ItemShield).length_px) \
				.override_failure_message("%s has no length" % item.id).is_greater(0.0)


func test_every_item_that_swings_is_a_sword_that_lasts_and_reaches() -> void:
	for item in _items_that(EquipItem.Action.SWING):
		assert_object(item).override_failure_message("%s isn't a sword" % item.id) \
				.is_instanceof(ItemSword)
		assert_int(GameTime.ticks((item as ItemSword).swing_active_sec)) \
				.override_failure_message("%s swings for no time" % item.id).is_greater(0)
		assert_float((item as ItemSword).swing_radius) \
				.override_failure_message("%s has no reach" % item.id).is_greater(0.0)
		assert_int((item as ItemSword).swing_slices) \
				.override_failure_message("%s has no slices" % item.id).is_greater(0)


func test_the_swing_arc_is_at_most_a_whole_turn() -> void:
	assert_float(SWORD.swing_arc()).is_less_equal(TAU)


func test_every_time_up_condition_has_a_time() -> void:
	for condition in _conditions_of(Condition.Type.TIME_UP):
		assert_float(condition.sec).override_failure_message(
				"a time-up condition in %s has no time" % condition.resource_path).is_greater(0.0)


func test_every_clear_room_condition_names_a_room() -> void:
	for condition in _conditions_of(Condition.Type.CLEAR_ROOM):
		assert_object(condition.room).override_failure_message(
				"a clear-room condition in %s names no room" % condition.resource_path) \
				.is_instanceof(Room)


func test_every_kind_a_map_places_has_a_snapshot_number() -> void:
	for room in _resources_in(ROOMS_DIR):
		for spot in (room as Room).dummies:
			assert_int(DUMMY_KINDS.index_of(spot.kind)).override_failure_message(
					"%s places an unlisted kind" % room.resource_path).is_not_equal(-1)


func test_every_kind_lists_at_most_one_distinct_charge() -> void:
	for kind: DummyKind in DUMMY_KINDS.kinds:
		var charges := kind.attacks.filter(
				func(a: Resource) -> bool: return a is DummyKind.ChargeAttack)
		for charge: Resource in charges:
			assert_object(charge).override_failure_message(
					"%s lists two charges" % kind.resource_path).is_same(kind.charge())


func test_every_run_starts_somewhere_and_its_passages_join_two_maps() -> void:
	for run in _resources_in(RUNS_DIR):
		var setup := run as RunSetup
		assert_object(setup.start).override_failure_message(
				"%s starts nowhere" % run.resource_path).is_not_null()
		for passage in setup.passages:
			assert_object(passage.from).is_not_null()
			assert_object(passage.to).is_not_null()


func _items_that(action: EquipItem.Action) -> Array[EquipItem]:
	var out: Array[EquipItem] = []
	for item in ITEMS.items:
		if item is EquipItem and (item as EquipItem).action == action:
			out.append(item)
	return out


func _conditions_of(type: Condition.Type) -> Array[Condition]:
	var out: Array[Condition] = []
	for condition in _all_conditions():
		if condition.type == type:
			out.append(condition)
	return out


func _all_conditions() -> Array[Condition]:
	var out: Array[Condition] = []
	for room in _resources_in(ROOMS_DIR):
		out.append_array((room as Room).clear_when)
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
