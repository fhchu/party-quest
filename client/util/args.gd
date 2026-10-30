extends RefCounted
## Options come from `--key=value` user args (after `--`) on desktop and from
## the page's query string (`?key=value`) on web. A bare key maps to "true".


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
