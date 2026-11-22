extends GdUnitTestSuite
## What the debug overlay shows for ping, RTT and IND.

const DebugOverlay := preload("res://client/debug_overlay.gd")

## Any time after the overlay started.
const NOW := 100.0

var overlay: DebugOverlay


func before_test() -> void:
	overlay = auto_free(DebugOverlay.new())
	add_child(overlay)


## The overlay's network line, drawn at [param now] with a drawing delay of
## [param delay_ms]. Calls must be at least [constant DebugOverlay.EVERY_SEC]
## apart, or the overlay doesn't redraw.
func _network_line(now: float, connected := true, delay_ms := 0) -> String:
	overlay.note_drawing(0, delay_ms, false)
	overlay.update(now, "", 0, connected)
	var label: Label = overlay.get_child(0)
	return label.text.split("\n")[1]


## Times an RTT of [param ms] ending at [param now]: you start moving, and a
## snapshot shows your character moved.
func _measure_rtt(now: float, ms: float) -> void:
	overlay.note_snapshot(now - ms / 1000.0, 0, true, Vector2.ZERO, 0)
	overlay.note_input(now - ms / 1000.0, Vector2.RIGHT, 0)
	overlay.note_snapshot(now, 0, true, Vector2.RIGHT, 0)


func test_ping_is_the_average_of_the_last_few_seconds() -> void:
	# Too old to count.
	overlay.note_ping(NOW - DebugOverlay.AVERAGE_SEC * 2, 900.0)
	overlay.note_ping(NOW - 1.0, 40.0)
	overlay.note_ping(NOW, 60.0)
	assert_str(_network_line(NOW)).contains("ping 50 ms")


func test_rtt_runs_from_starting_to_move_until_a_snapshot_shows_it() -> void:
	overlay.note_snapshot(NOW - 1.0, 0, true, Vector2.ZERO, 0)
	overlay.note_input(NOW - 0.2, Vector2.RIGHT, 0)
	# Still where it was: not an answer yet.
	overlay.note_snapshot(NOW - 0.1, 0, true, Vector2.ZERO, 0)
	overlay.note_snapshot(NOW, 0, true, Vector2.RIGHT, 0)
	assert_str(_network_line(NOW)).contains("RTT 200 ms")


func test_rtt_runs_from_an_attack_until_a_snapshot_shows_the_swing() -> void:
	overlay.note_snapshot(NOW - 1.0, 0, true, Vector2.ZERO, 0)
	overlay.note_input(NOW - 0.3, Vector2.ZERO, 1)
	overlay.note_snapshot(NOW, 0, true, Vector2.ZERO, 4)
	assert_str(_network_line(NOW)).contains("RTT 300 ms")


func test_a_dropped_connection_stops_the_rtt_timing() -> void:
	overlay.note_snapshot(NOW - 1.0, 0, true, Vector2.ZERO, 0)
	overlay.note_input(NOW - 0.5, Vector2.RIGHT, 0)
	overlay.note_connection_ended()
	overlay.note_snapshot(NOW - 0.2, 0, true, Vector2.ZERO, 0)
	overlay.note_snapshot(NOW, 0, true, Vector2.RIGHT, 0)
	assert_str(_network_line(NOW)).contains("RTT -")


func test_rtt_keeps_its_last_average_while_nothing_is_measured() -> void:
	_measure_rtt(NOW, 120.0)
	_network_line(NOW)
	var later := NOW + DebugOverlay.AVERAGE_SEC * 2
	assert_str(_network_line(later)).contains("RTT 120 ms")


func test_without_a_connection_ping_rtt_and_ind_are_dashes() -> void:
	overlay.note_ping(NOW, 40.0)
	_measure_rtt(NOW, 120.0)
	var line := _network_line(NOW, false, 60)
	assert_str(line).contains("ping -")
	assert_str(line).contains("RTT -")
	assert_str(line).contains("IND -")


func test_values_from_before_a_drop_dont_come_back() -> void:
	overlay.note_ping(NOW, 40.0)
	_measure_rtt(NOW, 120.0)
	_network_line(NOW, false)
	var line := _network_line(NOW + DebugOverlay.EVERY_SEC)
	assert_str(line).contains("ping -")
	assert_str(line).contains("RTT -")
