extends RefCounted
## The client's options, read once into typed fields. README.md lists them.
##
## Desktop reads [code]--key=value[/code] user args (after [code]--[/code]);
## web reads the query string ([code]?key=value[/code]). A bare key means
## true.

## The debug overlay.
var dev := false
## Where it connects; empty for the platform's default.
var url := ""
## Simulated delay each way. Given in ms as a round trip.
var lag_sec := 0.0
## Longest simulated hold-up. Given in ms.
var jitter_sec := 0.0
## A fixed interpolation delay instead of one that adapts. Given in ms.
var interp_fixed := false
var interp_sec := 0.0


## [param pairs] maps option names to their text, as [method read] gives it.
func _init(pairs: Dictionary) -> void:
	dev = pairs.has("dev")
	url = pairs.get("url", "")
	lag_sec = float(pairs.get("lag", "0")) / 1000.0 / 2
	jitter_sec = float(pairs.get("jitter", "0")) / 1000.0
	interp_fixed = pairs.has("interp")
	interp_sec = float(pairs.get("interp", "0")) / 1000.0


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
