extends SceneTree
## Fails where the editor would only warn: headless runs print no GDScript
## warnings. Godot reads warning levels only as it starts, so it runs twice:
##
##   godot --headless --path . -s res://tools/warnings_check.gd -- --raise
##       writes res://override.cfg, raising each warning the editor shows to
##       an error;
##   godot --headless --path . -s res://tools/warnings_check.gd
##       then loads every script outside addons/. A script with a warning
##       prints a SCRIPT ERROR; Godot still loads it and exits 0, so the
##       caller looks for that line.
##
## The caller deletes override.cfg afterwards: the editor reads it too.

const WARNINGS := "debug/gdscript/warnings/"
# A warning's level in project settings.
const WARN := 1
const ERROR := 2
## Not the game's, so not ours to fix.
const SKIPPED_DIRS := ["res://addons/", "res://.godot/", "res://build/"]
const OVERRIDE := "res://override.cfg"


func _init() -> void:
	if "--raise" in OS.get_cmdline_user_args():
		_raise_warnings()
		quit()
		return
	var scripts := _scripts("res://")
	# Reloading the script that's running crashes Godot.
	scripts.erase(get_script().resource_path)
	for path in scripts:
		ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	print("%d scripts loaded" % scripts.size())
	quit()


static func _raise_warnings() -> void:
	var override := ConfigFile.new()
	for property in ProjectSettings.get_property_list():
		var setting: String = property.name
		if setting.begins_with(WARNINGS) and ProjectSettings.get_setting(setting) is int \
				and ProjectSettings.get_setting(setting) == WARN:
			override.set_value("debug", setting.trim_prefix("debug/"), ERROR)
	override.save(OVERRIDE)


static func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	if dir in SKIPPED_DIRS:
		return out
	for entry in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + entry + "/"))
	for entry in DirAccess.get_files_at(dir):
		if entry.ends_with(".gd"):
			out.append(dir + entry)
	return out
