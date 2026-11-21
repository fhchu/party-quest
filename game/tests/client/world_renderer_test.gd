extends GdUnitTestSuite

const DummyKinds := preload("res://tests/dummy_kinds.gd")
const WorldRenderer := preload("res://client/world_renderer.gd")
const GameTime := preload("res://shared/game_time.gd")
const WorldView := preload("res://client/world_view.gd")
const RoomShape := preload("res://shared/room_shape.gd")


func test_a_floor_is_the_same_for_the_same_graphics_seed() -> void:
	var cells := Vector2i(20, 12)
	var weights: Array[float] = [1.0, 1.0, 1.0, 1.0]
	var floor_a := WorldRenderer.floor_density(42, cells, weights)
	assert_int(floor_a.size()).is_equal(cells.x * cells.y)
	assert_array(WorldRenderer.floor_density(42, cells, weights)).is_equal(floor_a)
	assert_array(WorldRenderer.floor_density(43, cells, weights)).is_not_equal(floor_a)


func test_floor_tiles_are_grouped_by_their_density_level() -> void:
	var tile_set := TileSet.new()
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, WorldRenderer.DENSITY_LEVEL_DATA)
	tile_set.set_custom_data_layer_type(0, TYPE_INT)
	var source := TileSetAtlasSource.new()
	source.texture = PlaceholderTexture2D.new()
	(source.texture as PlaceholderTexture2D).size = Vector2(48, 16)
	tile_set.add_source(source)
	var levels := { Vector2i(0, 0): 2, Vector2i(1, 0): 0, Vector2i(2, 0): 2 }
	for coords: Vector2i in levels:
		source.create_tile(coords)
		source.get_tile_data(coords, 0).set_custom_data(
				WorldRenderer.DENSITY_LEVEL_DATA, levels[coords])
	var grouped := WorldRenderer.tiles_by_density(tile_set)
	assert_int(grouped.size()).is_equal(3)
	assert_array(grouped[0]).is_equal([Vector2i(1, 0)])
	assert_array(grouped[1]).is_empty()
	assert_array(grouped[2]).contains_exactly_in_any_order([Vector2i(0, 0), Vector2i(2, 0)])


func test_a_charge_cue_grows_to_the_charge_length_then_holds_until_the_charge() -> void:
	var charge := DummyKinds.CHARGER.charge()
	var lock_sec := GameTime.seconds(GameTime.ticks(charge.aim_lock_sec))
	var grow_sec := lock_sec - WorldRenderer.CHARGE_CUE_HOLD_SEC
	var d := WorldView.Dummy.new()
	d.kind = DummyKinds.charger_kind
	assert_float(WorldRenderer.charge_cue_length(d)).is_zero()
	d.charge_windup_ticks_left = lock_sec * GameTime.TICK_RATE
	assert_float(WorldRenderer.charge_cue_length(d)).is_zero()
	d.charge_windup_ticks_left = (lock_sec - grow_sec / 2) * GameTime.TICK_RATE
	assert_float(WorldRenderer.charge_cue_length(d)).is_equal_approx(charge.length / 2, 0.01)
	d.charge_windup_ticks_left = WorldRenderer.CHARGE_CUE_HOLD_SEC * GameTime.TICK_RATE
	assert_float(WorldRenderer.charge_cue_length(d)).is_equal_approx(charge.length, 0.01)
	d.charge_windup_ticks_left = 1
	assert_float(WorldRenderer.charge_cue_length(d)).is_equal_approx(charge.length, 0.01)


func test_a_charge_cue_stops_at_the_floors_edge() -> void:
	var charge := DummyKinds.CHARGER.charge()
	var d := WorldView.Dummy.new()
	d.kind = DummyKinds.charger_kind
	d.facing = Vector2.RIGHT
	d.charge_windup_ticks_left = 1
	var floor_area := RoomShape.floor_area()
	d.pos = Vector2(floor_area.end.x - charge.length / 2, floor_area.get_center().y)
	var strip := WorldRenderer.charge_cue_strip(d)
	assert_int(strip.size()).is_equal(1)
	var reach := -INF
	for point in strip[0]:
		reach = maxf(reach, point.x)
	assert_float(reach).is_equal_approx(floor_area.end.x, 0.01)


func test_a_charge_cue_away_from_walls_is_its_whole_length() -> void:
	var charge := DummyKinds.CHARGER.charge()
	var d := WorldView.Dummy.new()
	d.kind = DummyKinds.charger_kind
	d.facing = Vector2.RIGHT
	d.charge_windup_ticks_left = 1
	d.pos = RoomShape.floor_area().get_center()
	var bounds := DummyKinds.CHARGER.hurtbox_or_default().get_rect()
	var reach := -INF
	for point in WorldRenderer.charge_cue_strip(d)[0]:
		reach = maxf(reach, point.x)
	assert_float(reach).is_equal_approx(d.pos.x + bounds.end.x + charge.length, 0.01)
