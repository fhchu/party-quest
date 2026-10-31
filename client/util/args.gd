extends RefCounted
## Command-line and URL options.
##
## Desktop reads [code]--key=value[/code] user args (after [code]--[/code]);
## web reads the query string ([code]?key=value[/code]). A bare key maps to
## [code]"true"[/code].


static func parse() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			_add(out, arg.substr(2))
	if OS.has_feature("web"):
		var search := str(JavaScriptBridge.eval("window.location.search", true))
		for pair in search.trim_prefix("?").split("&", false):
			_add(out, pair.uri_decode())
	return out


static func _add(out: Dictionary, pair: String) -> void:
	var kv := pair.split("=", true, 1)
	out[kv[0]] = kv[1] if kv.size() > 1 else "true"
