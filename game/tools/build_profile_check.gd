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
## With `--fix` before the profile, it first sets to false each disable_*
## build option that leaves out a class the export uses, rewrites the profile
## and says which. A class the profile's own list leaves out still fails.

const PRESETS := "res://export_presets.cfg"
const PRESET := "Web"
## Classes a build option leaves out beyond the profile's own class list,
## with their inheriters. Must match scene/register_scene_types.cpp in Godot
## 4.7.2, which registers the 2D shapes only with 2D physics.
const OPTION_CLASSES: Dictionary[String, Array] = { "disable_physics_2d": ["Shape2D"] }
const SCRIPT_NAMES := "\\b[A-Z]\\w*"
const RESOURCE_TYPES := "type=\"(\\w+)\""
const FIX_FLAG := "--fix"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var fix := not args.is_empty() and args[0] == FIX_FLAG
	var paths := args.slice(1) if fix else args
	var profile: Variant = null
	if paths.size() == 1 and FileAccess.file_exists(paths[0]):
		profile = JSON.parse_string(FileAccess.get_file_as_string(paths[0]))
	if profile is not Dictionary:
		print("Pass one .gdbuild file, after %s to fix it; got %s" % [FIX_FLAG, args])
		quit(1)
		return
	var used := _used_classes(_exported_files("res://", _exclude_filters()))
	if fix:
		var fixed := _fix_options(profile, used)
		for option in fixed:
			print("Set %s to false in %s: the export uses its classes" % [option, paths[0]])
		if fixed:
			FileAccess.open(paths[0], FileAccess.WRITE).store_string(
					JSON.stringify(profile, "\t", true))
	var removed := _removed_classes(profile)
	var left_out := 0
	for name: String in used:
		var needed := _removed_ancestor(name, removed)
		while needed:
			left_out += 1
			print("%s uses %s, but the template leaves out %s" % [used[name], name, needed])
			needed = _removed_ancestor(ClassDB.get_parent_class(needed), removed)
	print("%d engine classes used, %d left out" % [used.size(), left_out])
	quit(1 if left_out else 0)


## Sets to false each disable_* option in [param profile] that leaves out a
## class named in [param used], and returns the options it set.
static func _fix_options(profile: Dictionary, used: Dictionary) -> Array[String]:
	var fixed: Array[String] = []
	var options: Dictionary = profile.get("disabled_build_options", {})
	for option: String in OPTION_CLASSES:
		if not options.get(option, false):
			continue
		var removed := _option_classes(option)
		var needs := func(name: String) -> bool: return _removed_ancestor(name, removed) != ""
		if used.keys().any(needs):
			options[option] = false
			fixed.append(option)
	return fixed


static func _removed_classes(profile: Dictionary) -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	for name: String in profile.get("disabled_classes", []):
		out[name] = true
	var options: Dictionary = profile.get("disabled_build_options", {})
	for option: String in OPTION_CLASSES:
		if options.get(option, false):
			out.merge(_option_classes(option))
	return out


## The classes [param option] leaves out: its bases and their inheriters.
static func _option_classes(option: String) -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	for base: String in OPTION_CLASSES[option]:
		out[base] = true
		for name in ClassDB.get_inheriters_from_class(base):
			out[name] = true
	return out


## [param name] or the nearest of its ancestors in [param removed], or ""
## if none is.
static func _removed_ancestor(name: String, removed: Dictionary[String, bool]) -> String:
	while name and name not in removed:
		name = ClassDB.get_parent_class(name)
	return name


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
