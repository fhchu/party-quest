extends GdUnitTestSuite

const Options := preload("res://client/options.gd")


func test_defaults() -> void:
	var o := Options.new({})
	assert_float(o.lag_sec).is_equal(0.0)
	assert_bool(o.interp_fixed).is_false()


func test_values_are_converted_to_seconds() -> void:
	# As Options.read() gives them: text, "true" for a bare key.
	var o := Options.new({ "lag": "100", "jitter": "50", "interp": "80" })
	# Lag is a round trip; each direction waits half.
	assert_bool(is_equal_approx(o.lag_sec, 0.05)).is_true()
	assert_bool(is_equal_approx(o.jitter_sec, 0.05)).is_true()
	assert_bool(o.interp_fixed).is_true()
	assert_bool(is_equal_approx(o.interp_sec, 0.08)).is_true()
