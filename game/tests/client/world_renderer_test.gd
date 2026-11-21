extends GdUnitTestSuite

const DummyKinds := preload("res://tests/dummy_kinds.gd")
const WorldRenderer := preload("res://client/world_renderer.gd")
const GameTime := preload("res://shared/game_time.gd")
const WorldView := preload("res://client/world_view.gd")
const RoomShape := preload("res://shared/room_shape.gd")
const FloorNoise := preload("res://client/floor_noise.gd")


func test_a_floor_is_the_same_for_the_same_graphics_seed() -> void:
	var cells := Vector2i(20, 12)
	var floor_noise := _floor_noise([0.5], 0.1, false)
	var floor_a := WorldRenderer.floor_levels(42, cells, floor_noise)
	assert_int(floor_a.size()).is_equal(cells.x * cells.y)
	assert_array(WorldRenderer.floor_levels(42, cells, floor_noise)).is_equal(floor_a)
	assert_array(WorldRenderer.floor_levels(43, cells, floor_noise)).is_not_equal(floor_a)


func test_a_hard_edge_gives_each_level_from_its_threshold_up() -> void:
	var thresholds: Array[float] = [0.5, 0.7]
	for roll in [0.0, 0.99]:
		assert_int(WorldRenderer.density_level(0.49, thresholds, 0.0, roll)).is_equal(0)
		assert_int(WorldRenderer.density_level(0.5, thresholds, 0.0, roll)).is_equal(1)
		assert_int(WorldRenderer.density_level(0.7, thresholds, 0.0, roll)).is_equal(2)


func test_a_soft_edge_lets_the_roll_decide_only_near_the_threshold() -> void:
	var thresholds: Array[float] = [0.5]
	assert_int(WorldRenderer.density_level(0.39, thresholds, 0.1, 0.0)).is_equal(0)
	assert_int(WorldRenderer.density_level(0.61, thresholds, 0.1, 0.99)).is_equal(1)
	# Halfway through the edge, the chance is a half.
	assert_int(WorldRenderer.density_level(0.5, thresholds, 0.1, 0.4)).is_equal(1)
	assert_int(WorldRenderer.density_level(0.5, thresholds, 0.1, 0.6)).is_equal(0)


func test_a_floor_is_mirrored_only_when_its_noise_says_so() -> void:
	var layer := TileMapLayer.new()
	layer.tile_set = _tile_set({ Vector2i(0, 0): 0 })
	var cells := Vector2i(10, 10)
	WorldRenderer.fill_floor(layer, 7, cells, _floor_noise([], 0.0, false))
	assert_array(_alternatives(layer, cells)).not_contains([TileSetAtlasSource.TRANSFORM_FLIP_H])
	WorldRenderer.fill_floor(layer, 7, cells, _floor_noise([], 0.0, true))
	assert_array(_alternatives(layer, cells)).contains([TileSetAtlasSource.TRANSFORM_FLIP_H])
	layer.free()


func test_floor_cells_cover_the_viewport_with_a_cut_off_last_row() -> void:
	var tile_set := TileSet.new()
	var cell := tile_set.tile_size.x * WorldRenderer.FLOOR_SCALE
	var viewport := Vector2(cell * 20, cell * 11 + cell / 4.0)
	assert_object(WorldRenderer.floor_cells(tile_set, viewport)).is_equal(Vector2i(20, 12))


func test_floor_tiles_are_grouped_by_their_density_level() -> void:
	var tile_set := _tile_set({ Vector2i(0, 0): 2, Vector2i(1, 0): 0, Vector2i(2, 0): 2 })
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


func _floor_noise(thresholds: Array[float], softness: float, mirrored: bool) -> FloorNoise:
	var out := FloorNoise.new()
	out.noise = FastNoiseLite.new()
	out.level_thresholds = thresholds
	out.edge_softness = softness
	out.mirrored = mirrored
	return out


## One tile at each of [param levels]' atlas coords, with that density level.
func _tile_set(levels: Dictionary) -> TileSet:
	var out := TileSet.new()
	out.add_custom_data_layer()
	out.set_custom_data_layer_name(0, WorldRenderer.DENSITY_LEVEL_DATA)
	out.set_custom_data_layer_type(0, TYPE_INT)
	var source := TileSetAtlasSource.new()
	var texture := PlaceholderTexture2D.new()
	texture.size = Vector2(out.tile_size * Vector2i(levels.size(), 1))
	source.texture = texture
	out.add_source(source)
	for coords: Vector2i in levels:
		source.create_tile(coords)
		source.get_tile_data(coords, 0).set_custom_data(
				WorldRenderer.DENSITY_LEVEL_DATA, levels[coords])
	return out


func _alternatives(layer: TileMapLayer, cells: Vector2i) -> Array[int]:
	var out: Array[int] = []
	for y in cells.y:
		for x in cells.x:
			out.append(layer.get_cell_alternative_tile(Vector2i(x, y)))
	return out
