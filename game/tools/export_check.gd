extends SceneTree
## Checks that the web export keeps every data file as it is in source:
## the export rewrites .tres files, and can lose values on the way, such as
## an object default it saves as null. Exits 1 on any difference.
##
## Run after exporting a pack:
##   godot --headless --path . -s res://tools/export_check.gd -- <pack>

const DATA_DIR := "res://shared/data/"
## Set on every resource, and not data.
const SKIPPED := ["resource_path", "resource_name", "resource_local_to_scene", "script"]


func _init() -> void:
	var pack: String = OS.get_cmdline_user_args()[0]
	var paths := _data_files(DATA_DIR)
	var source := _read_all(paths)
	ProjectSettings.load_resource_pack(pack)
	var exported := _read_all(paths)
	var differences := 0
	for key: String in source:
		if exported.get(key) != source[key]:
			differences += 1
			print("%s: %s in source, %s exported" % [key, source[key], exported.get(key)])
	print("%d data files, %d values, %d differences" % [paths.size(), source.size(), differences])
	quit(1 if differences else 0)


static func _data_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for entry in ResourceLoader.list_directory(dir):
		if entry.ends_with("/"):
			out.append_array(_data_files(dir + entry))
		elif entry.ends_with(".tres"):
			out.append(dir + entry)
	return out


## Every value in [param paths]' files, loaded afresh, by file and property.
static func _read_all(paths: Array[String]) -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for path in paths:
		_flatten(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP), path, out)
	return out


## Puts [param value] in [param out] under [param key], with a resource's
## stored properties, and an array's items, each under its own key.
static func _flatten(value: Variant, key: String, out: Dictionary[String, String]) -> void:
	if value is Resource:
		out[key] = (value as Resource).get_class()
		for property in (value as Resource).get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.name not in SKIPPED:
				_flatten(value.get(property.name), key + "." + property.name, out)
	elif value is Array:
		for i in (value as Array).size():
			_flatten(value[i], "%s[%d]" % [key, i], out)
	else:
		out[key] = var_to_str(value)
