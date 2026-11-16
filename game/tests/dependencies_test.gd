extends GdUnitTestSuite
## Which game folders may reference which. server/ and client/ are the two
## sides; shared/, sim/ and net/ are shared by both, so they must not
## reach into either side. shared/ and net/ are leaves: they reference no
## other folder. The exempt folders may use anything.

## For each folder, the folders its scripts, scenes and resources must never
## reference.
const FORBIDDEN: Dictionary[String, Array] = {
	"shared": ["server", "client", "sim", "net"],
	"sim": ["server", "client"],
	"net": ["server", "client", "sim", "shared"],
	"server": ["client"],
	"client": ["server", "sim"],
}
## Top-level folders the rule doesn't apply to: dev-only code, the vendored
## test framework, and generated output that git ignores.
const EXEMPT: Array[String] = ["tests", "tools", "addons", "build"]
## The files that can reference another file by path.
const CHECKED_EXTENSIONS: Array[String] = ["gd", "tscn", "tres"]
## Every reference from one ruled folder's file to another folder's file,
## one "from -> to" line each, paths from res://. Lines starting with # are
## comments.
const LIST_PATH := "res://tests/dependencies.txt"
## Folders left out of the class_name search: the vendored framework and
## generated output, which aren't ours.
const NOT_OURS: Array[String] = ["addons", "build"]


func test_no_folder_references_one_it_must_not() -> void:
	# A load() or preload(), an extends by path, or a scene or resource's
	# ext_resource path. Group 1: the top-level folder referenced.
	var reference := RegEx.create_from_string(
			"(?:load\\(\\s*|extends\\s+|path=)[\"']res://([a-z_]+)/")
	for folder: String in FORBIDDEN:
		var offenders: Array[String] = []
		for path in _files_in("res://" + folder, CHECKED_EXTENSIONS):
			var source := FileAccess.get_file_as_string(path)
			for found in reference.search_all(source):
				if found.get_string(1) in FORBIDDEN[folder]:
					offenders.append("%s references res://%s/" % [path, found.get_string(1)])
		assert_array(offenders).override_failure_message(
				"%s/ must not reference %s/:\n%s" % [
					folder, "/ or ".join(FORBIDDEN[folder]), "\n".join(offenders)]
		).is_empty()


func test_every_reference_across_folders_is_listed() -> void:
	var unlisted: Array[String] = []
	var listed := _listed_references()
	for found in _references_across_folders():
		if found not in listed:
			unlisted.append(found)
	assert_array(unlisted).override_failure_message(
			"New references across folders. Ask the owner, add each to %s, and name it in"
			% LIST_PATH + " the PR description:\n%s" % "\n".join(unlisted)
	).is_empty()


func test_every_listed_reference_is_still_made() -> void:
	var made := _references_across_folders()
	var stale: Array[String] = []
	for line in _listed_references():
		if line not in made:
			stale.append(line)
	assert_array(stale).override_failure_message(
			"Remove these lines from %s; the code no longer makes them:\n%s"
			% [LIST_PATH, "\n".join(stale)]
	).is_empty()


## Godot resolves a global class name without any path, so a class_name would
## let one folder use another's script where this suite can't see it. The
## project preloads scripts into constants instead.
func test_no_script_declares_a_class_name() -> void:
	var declaration := RegEx.create_from_string("(?m)^class_name\\s")
	var offenders: Array[String] = []
	for folder in DirAccess.get_directories_at("res://"):
		if folder in NOT_OURS:
			continue
		for path in _files_in("res://" + folder, ["gd"]):
			if declaration.search(FileAccess.get_file_as_string(path)):
				offenders.append(path)
	assert_array(offenders).override_failure_message(
			"Preload the script into a constant instead of declaring class_name:\n%s"
			% "\n".join(offenders)
	).is_empty()


## A script that uses a constant preloaded by another script, by
## inheriting it or as A.B, depends on the preloaded file without
## preloading it, so nothing shows the dependency. Preload it, or ask the
## script that has it to do the work.
func test_no_script_uses_another_scripts_preloads() -> void:
	var offenders: Array[String] = []
	for folder: String in FORBIDDEN:
		for path in _files_in("res://" + folder, ["gd"]):
			offenders.append_array(_uses_of_others_preloads(path))
	assert_array(offenders).override_failure_message(
			"These use a constant another script preloaded:\n%s" % "\n".join(offenders)
	).is_empty()


func test_every_folder_is_ruled_or_exempt() -> void:
	var unruled: Array[String] = []
	for folder in DirAccess.get_directories_at("res://"):
		if not FORBIDDEN.has(folder) and folder not in EXEMPT:
			unruled.append(folder)
	assert_array(unruled).override_failure_message(
			"Add these folders to FORBIDDEN or EXEMPT: %s" % ", ".join(unruled)
	).is_empty()


func test_finds_the_files_it_checks() -> void:
	for folder: String in FORBIDDEN:
		assert_array(_files_in("res://" + folder, CHECKED_EXTENSIONS)).is_not_empty()


## "from -> to" for every reference a ruled folder's file makes to a file in
## another folder, paths from res://.
func _references_across_folders() -> Array[String]:
	var reference := RegEx.create_from_string(
			"(?:load\\(\\s*|extends\\s+|path=)[\"']res://([^\"']+)[\"']")
	var out: Array[String] = []
	for folder: String in FORBIDDEN:
		for path in _files_in("res://" + folder, CHECKED_EXTENSIONS):
			var from := path.trim_prefix("res://")
			for found in reference.search_all(FileAccess.get_file_as_string(path)):
				var to := found.get_string(1)
				var line := "%s -> %s" % [from, to]
				if to.get_slice("/", 0) != folder and line not in out:
					out.append(line)
	return out


func _listed_references() -> Array[String]:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(LIST_PATH).split("\n", false):
		if not line.begins_with("#"):
			out.append(line.strip_edges())
	return out


## Every file under [param dir] with one of [param extensions], in subfolders
## too.
func _files_in(dir: String, extensions: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in extensions:
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_files_in(dir.path_join(sub), extensions))
	return found


## Constant name to res:// path for each script [param path] preloads
## itself.
func _preloads(path: String) -> Dictionary[String, String]:
	var preload_const := RegEx.create_from_string(
			"(?m)^const\\s+(\\w+)[^=\\n]*=\\s*preload\\(\\s*\"(res://[^\"]+)\"")
	var out: Dictionary[String, String] = {}
	for found in preload_const.search_all(FileAccess.get_file_as_string(path)):
		out[found.get_string(1)] = found.get_string(2)
	return out


## The script [param path] extends by path, or "" for an engine class.
func _parent(path: String) -> String:
	var extends_path := RegEx.create_from_string("(?m)^extends\\s+\"(res://[^\"]+)\"")
	var found := extends_path.search(FileAccess.get_file_as_string(path))
	return found.get_string(1) if found else ""


## The preload constants [param path]'s ancestors declare.
func _inherited_preloads(path: String) -> Dictionary[String, String]:
	var parent := _parent(path)
	return _all_preloads(parent) if parent else {} as Dictionary[String, String]


## The preload constants [param path] has: its own and its ancestors'.
func _all_preloads(path: String) -> Dictionary[String, String]:
	return _preloads(path).merged(_inherited_preloads(path))


## [param source] without comments and string literals, so a name in either
## isn't counted as a use.
func _code_only(source: String) -> String:
	for pattern: String in ["\"\"\"[\\s\\S]*?\"\"\"", "\"(?:[^\"\\\\\\n]|\\\\.)*\"",
			"'(?:[^'\\\\\\n]|\\\\.)*'", "#[^\\n]*"]:
		source = RegEx.create_from_string(pattern).sub(source, "", true)
	return source


## Each use [param path] makes of a constant another script preloaded.
func _uses_of_others_preloads(path: String) -> Array[String]:
	var dotted := RegEx.create_from_string("\\b([A-Za-z_]\\w*)\\.([A-Za-z_]\\w*)")
	var code := _code_only(FileAccess.get_file_as_string(path))
	var own := _preloads(path)
	var out: Array[String] = []
	for inherited in _inherited_preloads(path):
		if RegEx.create_from_string("\\b%s\\b" % inherited).search(code):
			out.append("%s uses %s, inherited" % [path, inherited])
	for found in dotted.search_all(code):
		var script: String = own.get(found.get_string(1), "")
		if (script.ends_with(".gd") and script != path
				and found.get_string(2) in _all_preloads(script)):
			out.append("%s uses %s" % [path, found.get_string(0)])
	return out
