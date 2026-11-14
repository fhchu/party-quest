extends GdUnitTestSuite

const DummyKinds := preload("res://tests/dummy_kinds.gd")
const ArenaView := preload("res://client/arena_view.gd")
const GameTime := preload("res://shared/game_time.gd")
const Snapshot := preload("res://net/snapshot.gd")


func test_every_dummy_kind_has_a_look() -> void:
	for kind in DummyKinds.DUMMY_KINDS.kinds.size():
		for start_live: bool in [false, true]:
			assert_object(ArenaView.dummy_look(kind, start_live)).is_not_null()


func test_a_charge_cue_grows_to_the_charge_length_then_goes_before_the_charge() -> void:
	var kind := DummyKinds.CHARGER
	var lock_sec := GameTime.seconds(GameTime.ticks(kind.aim_lock_sec))
	var d := Snapshot.Dummy.new()
	d.kind = DummyKinds.charger_kind
	assert_float(ArenaView.charge_cue_length(d)).is_zero()
	d.charge_windup_ticks_left = lock_sec * GameTime.TICK_RATE
	assert_float(ArenaView.charge_cue_length(d)).is_zero()
	var half_grown := lock_sec - ArenaView.CHARGE_CUE_GROW_SEC / 2
	d.charge_windup_ticks_left = half_grown * GameTime.TICK_RATE
	assert_float(ArenaView.charge_cue_length(d)).is_equal_approx(kind.charge_length / 2, 0.01)
	var grown := lock_sec - ArenaView.CHARGE_CUE_GROW_SEC
	var gone := ArenaView.CHARGE_CUE_HIDE_SEC
	d.charge_windup_ticks_left = (grown + gone) / 2 * GameTime.TICK_RATE
	assert_float(ArenaView.charge_cue_length(d)).is_equal_approx(kind.charge_length, 0.01)
	d.charge_windup_ticks_left = gone * GameTime.TICK_RATE
	assert_float(ArenaView.charge_cue_length(d)).is_zero()
