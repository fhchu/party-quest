extends SceneTree
## Writes the license notices the web build has to carry: Godot's own and
## those of the libraries built into the engine, as reported by the engine
## running this script, so they run the version that exports the game.
## deploy/export-web.sh serves the file as licenses.txt beside the game.
##
## [code]godot --headless --path game -s res://tools/licenses.gd -- OUT_PATH[/code]


## The full notice text: Godot's license, each bundled component's
## copyright lines, then the text of every license those name.
static func notices() -> String:
	var lines := PackedStringArray([
		"This game is made with the Godot Engine (https://godotengine.org).",
		"",
		Engine.get_license_text(),
		"",
		"Godot includes the following third-party components.",
	])
	for component: Dictionary in Engine.get_copyright_info():
		lines.append("")
		lines.append(component.name)
		for part: Dictionary in component.parts:
			for holder: String in part.copyright:
				lines.append("  (c) " + holder)
			lines.append("  License: " + part.license)
	var licenses := Engine.get_license_info()
	for license_name: String in licenses:
		lines.append_array(["", "", "License: " + license_name, "", licenses[license_name]])
	return "\n".join(lines) + "\n"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("usage: godot --headless -s res://tools/licenses.gd -- OUT_PATH")
		quit(1)
		return
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		printerr("can't write %s: %s"
				% [args[0], error_string(FileAccess.get_open_error())])
		quit(1)
		return
	file.store_string(notices())
	quit()
