extends GdUnitTestSuite

const DummyKinds := preload("res://tests/dummy_kinds.gd")
const WorldRenderer := preload("res://client/world_renderer.gd")
const GameTime := preload("res://shared/game_time.gd")
const WorldView := preload("res://client/world_view.gd")
const RoomShape := preload("res://shared/room_shape.gd")


func test_a_floor_is_the_same_for_the_same_graphics_seed() -> void:
	var cells := Vector2i(20, 12)
	var weights: Array[float] = [1.0, 1.0, 1.0, 1.0]
	var floor_a := WorldRenderer.floor_tiles(42, cells, weights)
	assert_int(floor_a.size()).is_equal(cells.x * cells.y)
	assert_array(WorldRenderer.floor_tiles(42, cells, weights)).is_equal(floor_a)
	assert_array(WorldRenderer.floor_tiles(43, cells, weights)).is_not_equal(floor_a)


func test_a_floor_never_picks_a_tile_weighted_zero() -> void:
	var weights: Array[float] = [1.0, 0.0, 1.0]
	var tiles := WorldRenderer.floor_tiles(7, Vector2i(20, 12), weights)
	assert_bool(tiles.has(0) and tiles.has(2)).is_true()
	assert_bool(tiles.has(1)).is_false()


func test_a_heavier_tile_is_picked_more_often() -> void:
	var weights: Array[float] = [1.0, 3.0]
	var tiles := WorldRenderer.floor_tiles(7, Vector2i(40, 40), weights)
	assert_int(tiles.count(1)).is_greater(tiles.count(0) * 2)


func test_every_grass_tile_has_a_sheet_cell_and_a_weight() -> void:
	var count := WorldRenderer.GrassTile.size()
	assert_int(WorldRenderer.GRASS_SHEET_CELLS.size()).is_equal(count)
	assert_int(WorldRenderer.GRASS_WEIGHTS.size()).is_equal(count)


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
