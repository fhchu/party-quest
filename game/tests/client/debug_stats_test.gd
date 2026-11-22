extends GdUnitTestSuite
## The ping the HUD shows, and what the debug overlay shows for RTT and IND.

const DebugStats := preload("res://client/debug_stats.gd")
const Interpolator := preload("res://client/interpolator.gd")
const WorldView := preload("res://client/world_view.gd")

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
	return stats.text(now, connected, interpolator).split("\n")[1]


## Your own character at [param pos], [param swing_ticks] into a swing.
func _own(pos: Vector2, swing_ticks: int) -> WorldView.Player:
	var own := WorldView.Player.new()
	own.pos = pos
	own.swing_ticks = swing_ticks
	return own


## Times an RTT of [param ms] ending at [param now]: you start moving, and a
## snapshot shows your character moved.
func _measure_rtt(now: float, ms: float) -> void:
	var start := now - ms / 1000.0
	stats.note_snapshot(start, 0, _own(Vector2.ZERO, 0))
	stats.note_input(start, Vector2.RIGHT)
	stats.note_snapshot(now, 0, _own(Vector2.RIGHT, 0))


func test_ping_is_the_average_of_the_last_few_seconds() -> void:
	# Too old to count.
	stats.note_ping(NOW - DebugStats.AVERAGE_SEC * 2, 900.0)
	stats.note_ping(NOW - 1.0, 40.0)
	stats.note_ping(NOW, 60.0)
	assert_float(stats.ping_ms(NOW)).is_equal(50.0)


func test_rtt_runs_from_starting_to_move_until_a_snapshot_shows_it() -> void:
	stats.note_snapshot(NOW - 1.0, 0, _own(Vector2.ZERO, 0))
	stats.note_input(NOW - 0.2, Vector2.RIGHT)
	# Still where it was: not an answer yet.
	stats.note_snapshot(NOW - 0.1, 0, _own(Vector2.ZERO, 0))
	stats.note_snapshot(NOW, 0, _own(Vector2.RIGHT, 0))
	assert_str(_network_line(NOW)).contains("RTT 200 ms")


func test_rtt_runs_from_an_attack_until_a_snapshot_shows_the_swing() -> void:
	stats.note_snapshot(NOW - 1.0, 0, _own(Vector2.ZERO, 0))
	stats.note_attack(NOW - 0.3)
	stats.note_snapshot(NOW, 0, _own(Vector2.ZERO, 4))
	assert_str(_network_line(NOW)).contains("RTT 300 ms")


func test_a_dropped_connection_stops_the_rtt_timing() -> void:
	stats.note_snapshot(NOW - 1.0, 0, _own(Vector2.ZERO, 0))
	stats.note_input(NOW - 0.5, Vector2.RIGHT)
	stats.note_connection_lost()
	stats.note_snapshot(NOW - 0.2, 0, _own(Vector2.ZERO, 0))
	stats.note_snapshot(NOW, 0, _own(Vector2.RIGHT, 0))
	assert_str(_network_line(NOW)).contains("RTT -")


func test_rtt_is_a_dash_once_nothing_was_measured_for_a_while() -> void:
	_measure_rtt(NOW, 120.0)
	assert_str(_network_line(NOW)).contains("RTT 120 ms")
	var later := NOW + DebugStats.AVERAGE_SEC * 2
	assert_str(_network_line(later)).contains("RTT -")


func test_without_a_connection_rtt_and_ind_are_dashes() -> void:
	_measure_rtt(NOW, 120.0)
	var line := _network_line(NOW, false, 0.08)
	assert_str(line).contains("RTT -")
	assert_str(line).contains("IND -")


func test_values_from_before_a_drop_dont_come_back() -> void:
	stats.note_ping(NOW, 40.0)
	_measure_rtt(NOW, 120.0)
	stats.note_connection_lost()
	assert_float(stats.ping_ms(NOW)).is_equal(-1.0)
	assert_str(_network_line(NOW)).contains("RTT -")


func test_join_time_counts_from_the_page_starting_to_load() -> void:
	stats.page_loaded(NOW, 800.0)
	stats.note_joined(NOW + 1.5)
	assert_str(stats.text(NOW + 1.5, true, Interpolator.new())).contains("joined 2.3 s")


## The snapshot line at [param now].
func _snapshot_line(now: float) -> String:
	return stats.text(now, true, Interpolator.new()).split("\n")[3]


func test_loss_is_the_share_of_snapshots_that_never_came() -> void:
	stats.note_frames(NOW - 2.0, 0, 0, 0)
	stats.note_frames(NOW, 90, 10, 0)
	assert_str(_snapshot_line(NOW)).contains("loss 10.0%  late 0")


func test_a_late_snapshot_counts_as_late_not_lost() -> void:
	stats.note_frames(NOW - 2.0, 0, 0, 0)
	stats.note_frames(NOW, 98, 2, 1)
	assert_str(_snapshot_line(NOW)).contains("loss 1.0%  late 1")


func test_loss_counts_only_the_last_few_seconds() -> void:
	stats.note_frames(NOW - DebugStats.AVERAGE_SEC * 3, 0, 0, 0)
	stats.note_frames(NOW - DebugStats.AVERAGE_SEC * 2, 50, 50, 0)
	stats.note_frames(NOW - 1.0, 100, 50, 0)
	stats.note_frames(NOW, 200, 50, 0)
	assert_str(_snapshot_line(NOW)).contains("loss 0.0%")
