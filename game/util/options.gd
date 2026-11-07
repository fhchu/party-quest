extends RefCounted
## Dev options, read once into typed fields. README.md lists them.
##
## Desktop reads [code]--key=value[/code] user args (after [code]--[/code]);
## web reads the query string ([code]?key=value[/code]). A bare key means
## true.

## Run the game server instead of the client.
var server := false
## The game server's port; 0 when not given.
var port := 0
## The address the game server listens on; empty when not given.
var bind := ""
## Game server: quit once the room has been empty a while (Protocol.EMPTY_EXIT_SEC).
var exit_when_empty := false
## Dev tools. Client: the debug HUD and the keys that end a match. Game
## server: accepts those keys.
var dev := false
## Where the client connects; empty for the platform's default.
var url := ""
## Simulated delay each way. Given in ms as a round trip.
var lag_sec := 0.0
## Longest simulated hold-up. Given in ms.
var jitter_sec := 0.0
## A fixed interpolation delay instead of one that adapts. Given in ms.
var interp_fixed := false
var interp_sec := 0.0
## Random movement and attacks.
var bot := false
# Test hooks, in seconds after start; INF when not given.
var quit_after_sec := INF
var drop_after_sec := INF


## [param pairs] maps option names to their text, as [method read] gives it.
func _init(pairs: Dictionary) -> void:
	server = pairs.has("server")
	port = int(pairs.get("port", "0"))
	bind = pairs.get("bind", "")
	exit_when_empty = pairs.has("exit-when-empty")
	dev = pairs.has("dev")
	url = pairs.get("url", "")
	lag_sec = float(pairs.get("lag", "0")) / 1000.0 / 2
	jitter_sec = float(pairs.get("jitter", "0")) / 1000.0
	interp_fixed = pairs.has("interp")
	interp_sec = float(pairs.get("interp", "0")) / 1000.0
	bot = pairs.has("bot")
	quit_after_sec = float(pairs.get("quit-after", INF))
	drop_after_sec = float(pairs.get("drop-after", INF))


## The options given to this run, as text.
static func read() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			_add(out, arg.trim_prefix("--"))
	if OS.has_feature("web"):
		var search: String = JavaScriptBridge.get_interface("location").search
		for pair in search.trim_prefix("?").split("&", false):
			_add(out, pair.uri_decode())
	return out


static func _add(out: Dictionary, pair: String) -> void:
	var kv := pair.split("=", true, 1)
	out[kv[0]] = kv[1] if kv.size() > 1 else "true"
