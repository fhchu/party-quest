extends GdUnitTestSuite
## What the debug overlay shows for ping, RTT and IND.

const DebugStats := preload("res://client/debug_stats.gd")
const Interpolator := preload("res://client/interpolator.gd")

## Any time after the client started.
const NOW := 100.0

var stats: DebugStats


func before_test() -> void:
	stats = DebugStats.new()


## The network line at [param now], with a drawing delay of
## [param delay_sec].
func _network_line(now: float, connected := true,
		delay_sec := Interpolator.MIN_DELAY_SEC) -> String:
	var interpolator := Interpolator.new()
	interpolator.fixed = true
	interpolator.delay_sec = delay_sec
	return stats.text(now, "", connected, interpolator).split("\n")[1]


## Times an RTT of [param ms] ending at [param now]: you start moving, and a
## snapshot shows your character moved.
func _measure_rtt(now: float, ms: float) -> void:
	var start := now - ms / 1000.0
	stats.note_snapshot(start, 0, true, Vector2.ZERO, 0)
	stats.note_input(start, Vector2.RIGHT)
	stats.note_snapshot(now, 0, true, Vector2.RIGHT, 0)


func test_ping_is_the_average_of_the_last_few_seconds() -> void:
	# Too old to count.
	stats.note_ping(NOW - DebugStats.AVERAGE_SEC * 2, 900.0)
	stats.note_ping(NOW - 1.0, 40.0)
	stats.note_ping(NOW, 60.0)
	assert_str(_network_line(NOW)).contains("ping 50 ms")


func test_rtt_runs_from_starting_to_move_until_a_snapshot_shows_it() -> void:
	stats.note_snapshot(NOW - 1.0, 0, true, Vector2.ZERO, 0)
	stats.note_input(NOW - 0.2, Vector2.RIGHT)
	# Still where it was: not an answer yet.
	stats.note_snapshot(NOW - 0.1, 0, true, Vector2.ZERO, 0)
	stats.note_snapshot(NOW, 0, true, Vector2.RIGHT, 0)
	assert_str(_network_line(NOW)).contains("RTT 200 ms")


func test_rtt_runs_from_an_attack_until_a_snapshot_shows_the_swing() -> void:
	stats.note_snapshot(NOW - 1.0, 0, true, Vector2.ZERO, 0)
	stats.note_attack(NOW - 0.3)
	stats.note_snapshot(NOW, 0, true, Vector2.ZERO, 4)
	assert_str(_network_line(NOW)).contains("RTT 300 ms")


func test_a_dropped_connection_stops_the_rtt_timing() -> void:
	stats.note_snapshot(NOW - 1.0, 0, true, Vector2.ZERO, 0)
	stats.note_input(NOW - 0.5, Vector2.RIGHT)
	stats.note_connection_lost()
	stats.note_snapshot(NOW - 0.2, 0, true, Vector2.ZERO, 0)
	stats.note_snapshot(NOW, 0, true, Vector2.RIGHT, 0)
	assert_str(_network_line(NOW)).contains("RTT -")


func test_rtt_keeps_its_last_average_while_nothing_is_measured() -> void:
	_measure_rtt(NOW, 120.0)
	_network_line(NOW)
	var later := NOW + DebugStats.AVERAGE_SEC * 2
	assert_str(_network_line(later)).contains("RTT 120 ms")


func test_without_a_connection_ping_rtt_and_ind_are_dashes() -> void:
	stats.note_ping(NOW, 40.0)
	_measure_rtt(NOW, 120.0)
	var line := _network_line(NOW, false, 0.08)
	assert_str(line).contains("ping -")
	assert_str(line).contains("RTT -")
	assert_str(line).contains("IND -")


func test_values_from_before_a_drop_dont_come_back() -> void:
	stats.note_ping(NOW, 40.0)
	_measure_rtt(NOW, 120.0)
	stats.note_connection_lost()
	var line := _network_line(NOW)
	assert_str(line).contains("ping -")
	assert_str(line).contains("RTT -")


func test_join_time_counts_from_the_page_starting_to_load() -> void:
	stats.page_loaded(NOW, 800.0)
	stats.note_joined(NOW + 1.5)
	assert_str(stats.text(NOW + 1.5, "", true, Interpolator.new())).contains("joined 2.3 s")
