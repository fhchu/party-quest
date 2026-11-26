extends GdUnitTestSuite

const Options := preload("res://client/options.gd")


func test_with_no_options_there_is_no_lag_and_the_delay_adapts() -> void:
	var o := Options.new({})
	assert_float(o.lag_sec).is_equal(0.0)
	assert_bool(o.interp_fixed).is_false()


func test_values_are_converted_to_seconds() -> void:
	# As Options.read() gives them: text, "true" for a bare key.
	var o := Options.new({ "lag": "100", "jitter": "50", "interp": "80" })
	# Lag is a round trip; each direction waits half.
	assert_float(o.lag_sec).is_equal_approx(0.05, 0.0001)
	assert_float(o.jitter_sec).is_equal_approx(0.05, 0.0001)
	assert_bool(o.interp_fixed).is_true()
	assert_float(o.interp_sec).is_equal_approx(0.08, 0.0001)
