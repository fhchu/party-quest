extends RefCounted
## The game's own source files, read as text, for the suites that check
## rules about the code itself (dependencies_test.gd, code_rules_test.gd).

## Top-level folders that aren't ours: the vendored test framework, and
## generated output that git ignores.
const NOT_OURS: Array[String] = ["addons", "build"]


## Every file under [param dir] with one of [param extensions], in subfolders
## too.
static func files_in(dir: String, extensions: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in extensions:
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(files_in(dir.path_join(sub), extensions))
	return found


## Every script of ours: each .gd file outside the folders that aren't ours.
static func our_scripts() -> Array[String]:
	var out: Array[String] = []
	for folder in DirAccess.get_directories_at("res://"):
		if folder not in NOT_OURS:
			out.append_array(files_in("res://" + folder, ["gd"]))
	return out


## Global class name to res:// path, for every script of ours that declares
## a class_name. Godot resolves these without any path, so uses are found by
## name.
static func global_classes() -> Dictionary[String, String]:
	var declaration := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
	var out: Dictionary[String, String] = {}
	for path in our_scripts():
		var found := declaration.search(FileAccess.get_file_as_string(path))
		if found:
			out[found.get_string(1)] = path
	return out


## [param source] without comments and string literals, so a name in either
## isn't counted as a use.
static func code_only(source: String) -> String:
	for pattern: String in ["\"\"\"[\\s\\S]*?\"\"\"", "\"(?:[^\"\\\\\\n]|\\\\.)*\"",
			"'(?:[^'\\\\\\n]|\\\\.)*'", "#[^\\n]*"]:
		source = RegEx.create_from_string(pattern).sub(source, "", true)
	return source
