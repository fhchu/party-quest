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
	assert_bool(arena.end.x <= viewport.x and arena.end.y <= viewport.y).is_true()


func test_every_item_has_its_own_id() -> void:
	var ids := ITEMS.items.map(func(item: Item) -> String: return item.id)
	assert_array(ids).not_contains([""])
	for id: String in ids:
		assert_int(ids.count(id)).is_equal(1)


func test_every_item_has_a_display_name() -> void:
	for item: Item in ITEMS.items:
		assert_str(item.display_name).is_not_empty()


func test_every_item_file_is_in_the_list() -> void:
	for file in DirAccess.get_files_at(ITEMS_DIR):
		if file.get_extension() == "tres":
			assert_array(ITEMS.items).contains([load(ITEMS_DIR + file)])


func test_every_item_has_a_number_the_lobby_state_can_send() -> void:
	assert_int(ITEMS.items.size()).is_less_equal(LobbyState.NO_ITEM)


func test_every_item_that_guards_is_a_shield_with_a_size() -> void:
	for item in ITEMS.items:
		var equip := item as EquipItem
		if equip and equip.action == EquipItem.Action.GUARD:
			assert_object(equip).is_instanceof(ItemShield)
			assert_float((equip as ItemShield).thickness_px).is_greater(0.0)
			assert_float((equip as ItemShield).length_px).is_greater(0.0)


func test_every_item_that_swings_is_a_sword_that_lasts_and_reaches() -> void:
	for item in ITEMS.items:
		var equip := item as EquipItem
		if equip and equip.action == EquipItem.Action.SWING:
			assert_object(equip).is_instanceof(ItemSword)
			assert_int(GameTime.ticks((equip as ItemSword).swing_active_sec)).is_greater(0)
			assert_float((equip as ItemSword).swing_radius).is_greater(0.0)
			assert_int((equip as ItemSword).swing_slices).is_greater(0)


func test_the_swing_arc_is_at_most_a_whole_turn() -> void:
	assert_float(SWORD.swing_arc()).is_less_equal(TAU)


func test_every_condition_sets_the_field_its_type_needs() -> void:
	for condition in _all_conditions():
		match condition.type:
			Condition.Type.TIME_UP:
				assert_float(condition.sec).is_greater(0.0)
			Condition.Type.CLEAR_ROOM:
				assert_bool(condition.room is Room).is_true()


func test_every_kind_a_map_places_has_a_snapshot_number() -> void:
	for room in _resources_in(ROOMS_DIR):
		for spot in (room as Room).dummies:
			assert_int(DUMMY_KINDS.index_of(spot.kind)).is_not_equal(-1)


func test_every_kind_lists_at_most_one_distinct_charge() -> void:
	for kind: DummyKind in DUMMY_KINDS.kinds:
		var charges := kind.attacks.filter(
				func(a: Resource) -> bool: return a is DummyKind.ChargeAttack)
		for charge: Resource in charges:
			assert_object(charge).is_same(kind.charge())


func test_every_run_starts_somewhere_and_its_passages_join_two_maps() -> void:
	for run in _resources_in(RUNS_DIR):
		var setup := run as RunSetup
		assert_object(setup.start).is_not_null()
		for passage in setup.passages:
			assert_object(passage.from).is_not_null()
			assert_object(passage.to).is_not_null()


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
