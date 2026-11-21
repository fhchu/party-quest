extends GdUnitTestSuite
## What the debug overlay shows for ping, RTT and IND.

const DebugOverlay := preload("res://client/debug_overlay.gd")

## Any time after the overlay started.
const NOW := 100.0

var overlay: DebugOverlay


func before_test() -> void:
	overlay = auto_free(DebugOverlay.new())
	add_child(overlay)


## The overlay's network line, drawn at [param now]. Calls must be at least
## [constant DebugOverlay.EVERY_SEC] apart, or the overlay doesn't redraw.
func _network_line(now: float, connected := true) -> String:
	overlay.update(now, "", 0, connected)
	var label: Label = overlay.get_child(0)
	return label.text.split("\n")[1]


func test_ping_is_the_average_of_the_last_few_seconds() -> void:
	# Too old to count.
	overlay.note_ping(NOW - DebugOverlay.AVERAGE_SEC * 2, 900.0)
	overlay.note_ping(NOW - 1.0, 40.0)
	overlay.note_ping(NOW, 60.0)
	assert_str(_network_line(NOW)).contains("ping 50 ms")


func test_rtt_keeps_its_last_average_while_nothing_is_measured() -> void:
	overlay.note_rtt(NOW, 120.0)
	_network_line(NOW)
	var later := NOW + DebugOverlay.AVERAGE_SEC * 2
	assert_str(_network_line(later)).contains("RTT 120 ms")


func test_without_a_connection_ping_rtt_and_ind_are_dashes() -> void:
	overlay.note_ping(NOW, 40.0)
	overlay.note_rtt(NOW, 120.0)
	overlay.note_drawing(0, 60, true)
	var line := _network_line(NOW, false)
	assert_str(line).contains("ping -")
	assert_str(line).contains("RTT -")
	assert_str(line).contains("IND -")


func test_values_from_before_a_drop_dont_come_back() -> void:
	overlay.note_ping(NOW, 40.0)
	overlay.note_rtt(NOW, 120.0)
	_network_line(NOW, false)
	var line := _network_line(NOW + DebugOverlay.EVERY_SEC)
	assert_str(line).contains("ping -")
	assert_str(line).contains("RTT -")
