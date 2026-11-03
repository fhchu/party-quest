extends RefCounted
## Simulated latency, for testing "two devices at 100 ms" on a network with
## 5 ms ping. Messages both ways share one queue, so their order is kept.

## About a couple of messages a second.
const JITTER_CHANCE := 1.0 / 30

var lag_sec := 0.0
var jitter_sec := 0.0
## In release order.
var _queue: Array[Delayed] = []


func _init(lag: float, jitter: float) -> void:
	lag_sec = lag
	jitter_sec = jitter


## Queues a send. It's dropped if the connection is gone when it's due.
func outgoing(now: float, f: Callable) -> void:
	_queue.append(Delayed.new(now + lag_sec + _jitter(), f, true))


func incoming(now: float, f: Callable) -> void:
	_queue.append(Delayed.new(now + lag_sec + _jitter(), f, false))


## Runs whatever is due. [param online] says whether sends can still go out.
func flush(now: float, online: Callable) -> void:
	while not _queue.is_empty() and _queue[0].release_at <= now:
		var item: Delayed = _queue.pop_front()
		if not item.outgoing or online.call():
			item.action.call()


func clear() -> void:
	_queue.clear()


## Holds up the odd message, delaying everything behind it like a Wi-Fi
## hiccup. A random delay on every message would just add the largest one to
## all of them, since order is kept.
func _jitter() -> float:
	return randf() * jitter_sec if randf() < JITTER_CHANCE else 0.0


class Delayed:
	var release_at: float
	var action: Callable
	var outgoing: bool

	func _init(at: float, run: Callable, is_outgoing: bool) -> void:
		release_at = at
		action = run
		outgoing = is_outgoing
