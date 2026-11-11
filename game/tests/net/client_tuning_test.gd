extends GdUnitTestSuite

const ClientTuning := preload("res://net/client_tuning.gd")


## Every field set to something other than its default. Values a 32-bit float
## holds exactly, so the round trip can compare for equality.
func _tuning() -> ClientTuning:
	var t := ClientTuning.new()
	t.arena = Rect2(1, 2, 640, 360)
	t.player_hurtbox = Vector2(16, 12)
	t.dummy_hurtbox = Vector2(20, 24)
	t.player_max_health = 5
	t.swing_arc = PackedVector2Array([Vector2.ZERO, Vector2(40, -8.5), Vector2(40, 8.5)])
	return t


func test_round_trip_keeps_every_field() -> void:
	var t := _tuning()
	var back := ClientTuning.new()
	assert_bool(back.read(t.to_bytes())).is_true()
	assert_that(back.arena).is_equal(t.arena)
	assert_that(back.player_hurtbox).is_equal(t.player_hurtbox)
	assert_that(back.dummy_hurtbox).is_equal(t.dummy_hurtbox)
	assert_int(back.player_max_health).is_equal(t.player_max_health)
	assert_that(back.swing_arc).is_equal(t.swing_arc)


func test_truncated_bytes_change_nothing() -> void:
	var bytes := _tuning().to_bytes()
	var t := ClientTuning.new()
	assert_bool(t.read(bytes.slice(0, bytes.size() - 1))).is_false()
	assert_int(t.player_max_health).is_zero()
