extends SceneTree
## Checks that the trimmed web template keeps every engine class the web
## export uses: a class it leaves out fails only in the browser, not at
## export. Exits 1 if one is left out.
##
## Reads the files the Web preset exports: `type="..."` in scenes and
## resources, and every engine class name in scripts, comments included, so
## a comment can make it fail but a use can't slip by.
##
## Run with the template's build profile:
##   godot --headless --path . -s res://tools/build_profile_check.gd -- <.gdbuild>

const PRESETS := "res://export_presets.cfg"
const PRESET := "Web"
## Classes a build option leaves out beyond the profile's own class list,
## with their inheriters. Must match scene/register_scene_types.cpp in Godot
## 4.7.2, which registers the 2D shapes only with 2D physics.
const OPTION_CLASSES: Dictionary[String, Array] = { "disable_physics_2d": ["Shape2D"] }
const SCRIPT_NAMES := "\\b[A-Z]\\w*"
const RESOURCE_TYPES := "type=\"(\\w+)\""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var profile: Variant = null
	if args.size() == 1:
		profile = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if profile is not Dictionary:
		print("Pass one .gdbuild file; got %s" % [args])
		quit(1)
		return
	var removed := _removed_classes(profile)
	var used := _used_classes(_exported_files("res://", _exclude_filters()))
	var left_out := 0
	for name: String in used:
		var needed := name
		while needed:
			if needed in removed:
				left_out += 1
				print("%s uses %s, but the template leaves out %s" % [used[name], name, needed])
			needed = ClassDB.get_parent_class(needed)
	print("%d engine classes used, %d left out" % [used.size(), left_out])
	quit(1 if left_out else 0)


static func _removed_classes(profile: Dictionary) -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	for name: String in profile.get("disabled_classes", []):
		out[name] = true
	var options: Dictionary = profile.get("disabled_build_options", {})
	for option in OPTION_CLASSES:
		if options.get(option, false):
			for base: String in OPTION_CLASSES[option]:
				out[base] = true
				for name in ClassDB.get_inheriters_from_class(base):
					out[name] = true
	return out


## The Web preset's exclude_filter patterns.
static func _exclude_filters() -> PackedStringArray:
	var presets := ConfigFile.new()
	presets.load(PRESETS)
	for section in presets.get_sections():
		if presets.get_value(section, "name", "") == PRESET:
			var filters := PackedStringArray()
			for pattern in (presets.get_value(section, "exclude_filter", "") as String).split(","):
				filters.append(pattern.strip_edges())
			return filters
	return PackedStringArray()


static func _exported_files(dir: String, excluded: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	for name in DirAccess.get_directories_at(dir):
		if not name.begins_with("."):
			out.append_array(_exported_files(dir + name + "/", excluded))
	for name in DirAccess.get_files_at(dir):
		var path := dir + name
		var relative := path.trim_prefix("res://")
		if not Array(excluded).any(func(pattern: String) -> bool: return relative.match(pattern)):
			out.append(path)
	return out


## Each engine class [param paths] name, with the first file naming it.
static func _used_classes(paths: Array[String]) -> Dictionary[String, String]:
	var script_names := RegEx.create_from_string(SCRIPT_NAMES)
	var resource_types := RegEx.create_from_string(RESOURCE_TYPES)
	var out: Dictionary[String, String] = {}
	for path in paths:
		var found: Array[RegExMatch] = []
		match path.get_extension():
			"gd":
				found = script_names.search_all(FileAccess.get_file_as_string(path))
			"tscn", "tres":
				found = resource_types.search_all(FileAccess.get_file_as_string(path))
		for result in found:
			var name := result.get_string(result.get_group_count())
			if ClassDB.class_exists(name) and name not in out:
				out[name] = path
	return out
