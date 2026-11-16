extends GdUnitTestSuite

const Options := preload("res://util/options.gd")

## Only rounding: ms to seconds is exact otherwise.
const TOLERANCE := 1e-9


func test_defaults() -> void:
	var o := Options.new({})
	assert_int(o.port).is_equal(0)
	assert_float(o.lag_sec).is_equal(0.0)
	assert_bool(o.interp_fixed).is_false()


func test_values_are_converted_to_seconds() -> void:
	# As Options.read() gives them: text, "true" for a bare key.
	var o := Options.new({ "lag": "100", "jitter": "50", "interp": "80" })
	# Lag is a round trip; each direction waits half.
	assert_float(o.lag_sec).is_equal_approx(0.05, TOLERANCE)
	assert_float(o.jitter_sec).is_equal_approx(0.05, TOLERANCE)
	assert_bool(o.interp_fixed).is_true()
	assert_float(o.interp_sec).is_equal_approx(0.08, TOLERANCE)
