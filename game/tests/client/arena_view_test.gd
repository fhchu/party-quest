extends GdUnitTestSuite

const DummyKinds := preload("res://tests/dummy_kinds.gd")
const ArenaView := preload("res://client/arena_view.gd")
const GameTime := preload("res://shared/game_time.gd")
const Snapshot := preload("res://net/snapshot.gd")
const RoomShape := preload("res://shared/room_shape.gd")


func test_every_dummy_kind_has_a_look() -> void:
	for kind in DummyKinds.DUMMY_KINDS.kinds.size():
		for start_live: bool in [false, true]:
			assert_object(ArenaView.dummy_look(kind, start_live)).is_not_null()


func test_a_charge_cue_grows_to_the_charge_length_then_holds_until_the_charge() -> void:
	var charge := DummyKinds.CHARGER.charge
	var lock_sec := GameTime.seconds(GameTime.ticks(charge.aim_lock_sec))
	var grow_sec := lock_sec - ArenaView.CHARGE_CUE_HOLD_SEC
	var d := Snapshot.Dummy.new()
	d.kind = DummyKinds.charger_kind
	assert_float(ArenaView.charge_cue_length(d)).is_zero()
	d.charge_windup_ticks_left = lock_sec * GameTime.TICK_RATE
	assert_float(ArenaView.charge_cue_length(d)).is_zero()
	d.charge_windup_ticks_left = (lock_sec - grow_sec / 2) * GameTime.TICK_RATE
	assert_float(ArenaView.charge_cue_length(d)).is_equal_approx(charge.length / 2, 0.01)
	d.charge_windup_ticks_left = ArenaView.CHARGE_CUE_HOLD_SEC * GameTime.TICK_RATE
	assert_float(ArenaView.charge_cue_length(d)).is_equal_approx(charge.length, 0.01)
	d.charge_windup_ticks_left = 1
	assert_float(ArenaView.charge_cue_length(d)).is_equal_approx(charge.length, 0.01)


func test_a_charge_cue_stops_at_the_floors_edge() -> void:
	var charge := DummyKinds.CHARGER.charge
	var d := Snapshot.Dummy.new()
	d.kind = DummyKinds.charger_kind
	d.facing = Vector2.RIGHT
	d.charge_windup_ticks_left = 1
	var floor_area := RoomShape.floor_area()
	d.pos = Vector2(floor_area.end.x - charge.length / 2, floor_area.get_center().y)
	var strip := ArenaView.charge_cue_strip(d)
	assert_int(strip.size()).is_equal(1)
	var reach := -INF
	for point in strip[0]:
		reach = maxf(reach, point.x)
	assert_float(reach).is_equal_approx(floor_area.end.x, 0.01)


func test_a_charge_cue_away_from_walls_is_its_whole_length() -> void:
	var charge := DummyKinds.CHARGER.charge
	var d := Snapshot.Dummy.new()
	d.kind = DummyKinds.charger_kind
	d.facing = Vector2.RIGHT
	d.charge_windup_ticks_left = 1
	d.pos = RoomShape.floor_area().get_center()
	var bounds := DummyKinds.CHARGER.hurtbox_or_default().get_rect()
	var reach := -INF
	for point in ArenaView.charge_cue_strip(d)[0]:
		reach = maxf(reach, point.x)
	assert_float(reach).is_equal_approx(d.pos.x + bounds.end.x + charge.length, 0.01)
