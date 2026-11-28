extends GdUnitTestSuite
## Which game folders may reference which. server/ and client/ are the two
## sides; shared/, sim/ and net/ are shared by both, so they must not
## reach into either side. shared/ and net/ are leaves: they reference no
## other folder. The exempt folders may use anything.

const SourceFiles := preload("res://tests/source_files.gd")
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
## one "from -> to" line each, paths from res://. A "to" ending in / allows
## every file under that folder, subfolders included. Lines starting with #
## are comments.
const LIST_PATH := "res://tests/dependencies.txt"


func test_no_folder_references_one_it_must_not() -> void:
	var offenders := _forbidden_references()
	assert_array(offenders).override_failure_message(
			"Each folder must not reference these (FORBIDDEN):\n%s" % "\n".join(offenders)
	).is_empty()


func test_every_reference_across_folders_is_listed() -> void:
	var unlisted := _unlisted_references()
	assert_array(unlisted).override_failure_message(
			"New references across folders. Ask the owner, add each to %s, and name it in"
			% LIST_PATH + " the PR description:\n%s" % "\n".join(unlisted)
	).is_empty()


func test_every_listed_reference_is_still_made() -> void:
	var stale := _stale_lines()
	assert_array(stale).override_failure_message(
			"Remove these lines from %s; the code no longer makes them:\n%s"
			% [LIST_PATH, "\n".join(stale)]
	).is_empty()


## Only a file makes references, so a line from a folder, or from a file
## that isn't there, allows nothing.
func test_every_line_starts_from_a_file() -> void:
	var not_files := _lines_not_from_a_file()
	assert_array(not_files).override_failure_message(
			"These lines in %s don't start from a file:\n%s"
			% [LIST_PATH, "\n".join(not_files)]
	).is_empty()


func test_a_folder_line_allows_a_file_in_a_subfolder() -> void:
	assert_bool(_is_listed("sim/a.gd -> shared/data/items/b.tres",
			["sim/a.gd -> shared/data/"])).is_true()


func test_a_folder_line_allows_nothing_from_another_file() -> void:
	assert_bool(_is_listed("sim/c.gd -> shared/data/b.gd",
			["sim/a.gd -> shared/data/"])).is_false()


func test_a_folder_line_allows_nothing_beside_its_folder() -> void:
	assert_bool(_is_listed("sim/a.gd -> shared/data/items.gd",
			["sim/a.gd -> shared/data/items/"])).is_false()


func test_a_file_line_allows_nothing_under_its_name() -> void:
	assert_bool(_is_listed("sim/a.gd -> shared/data/b.gd",
			["sim/a.gd -> shared/data"])).is_false()


## A script that uses a constant preloaded by another script, by
## inheriting it or as A.B, depends on the preloaded file without
## preloading it, so nothing shows the dependency. Preload it, or ask the
## script that has it to do the work.
func test_no_script_uses_another_scripts_preloads() -> void:
	var offenders := _uses_of_preloads_in_ruled_folders()
	assert_array(offenders).override_failure_message(
			"These use a constant another script preloaded:\n%s" % "\n".join(offenders)
	).is_empty()


func test_every_folder_is_ruled_or_exempt() -> void:
	var unruled := _unruled_folders()
	assert_array(unruled).override_failure_message(
			"Add these folders to FORBIDDEN or EXEMPT: %s" % ", ".join(unruled)
	).is_empty()


func test_finds_the_files_it_checks() -> void:
	for folder: String in FORBIDDEN:
		assert_array(SourceFiles.files_in("res://" + folder, CHECKED_EXTENSIONS)) \
				.append_failure_message("found no files in %s/" % folder).is_not_empty()


## "path references res://to" for each reference a ruled folder's file
## makes to a folder FORBIDDEN to it.
func _forbidden_references() -> Array[String]:
	var classes := SourceFiles.global_classes()
	var out: Array[String] = []
	for folder: String in FORBIDDEN:
		for path in SourceFiles.files_in("res://" + folder, CHECKED_EXTENSIONS):
			for to in _references(path, classes):
				if to.get_slice("/", 0) in FORBIDDEN[folder]:
					out.append("%s references res://%s" % [path, to])
	return out


## The references across folders that LIST_PATH doesn't allow.
func _unlisted_references() -> Array[String]:
	var listed := _listed_references()
	var out: Array[String] = []
	for found in _references_across_folders():
		if not _is_listed(found, listed):
			out.append(found)
	return out


## LIST_PATH's file lines that the code no longer makes. Folder lines are
## kept by hand, never reported unused.
func _stale_lines() -> Array[String]:
	var made := _references_across_folders()
	var out: Array[String] = []
	for line in _listed_references():
		if not line.ends_with("/") and line not in made:
			out.append(line)
	return out


## LIST_PATH's lines whose "from" isn't a file there.
func _lines_not_from_a_file() -> Array[String]:
	var out: Array[String] = []
	for line in _listed_references():
		if not FileAccess.file_exists("res://" + line.get_slice(" -> ", 0)):
			out.append(line)
	return out


## Each use a ruled folder's script makes of a constant another script
## preloaded.
func _uses_of_preloads_in_ruled_folders() -> Array[String]:
	var out: Array[String] = []
	for folder: String in FORBIDDEN:
		for path in SourceFiles.files_in("res://" + folder, ["gd"]):
			out.append_array(_uses_of_others_preloads(path))
	return out


## Top-level folders neither FORBIDDEN nor EXEMPT rules on.
func _unruled_folders() -> Array[String]:
	var out: Array[String] = []
	for folder in DirAccess.get_directories_at("res://"):
		if not FORBIDDEN.has(folder) and folder not in EXEMPT:
			out.append(folder)
	return out


## "from -> to" for every reference a ruled folder's file makes to a file in
## another folder, paths from res://.
func _references_across_folders() -> Array[String]:
	var classes := SourceFiles.global_classes()
	var out: Array[String] = []
	for folder: String in FORBIDDEN:
		for path in SourceFiles.files_in("res://" + folder, CHECKED_EXTENSIONS):
			var from := path.trim_prefix("res://")
			for to in _references(path, classes):
				var line := "%s -> %s" % [from, to]
				if to.get_slice("/", 0) != folder and line not in out:
					out.append(line)
	return out


## The files [param path] references, paths from res://: by a load() or
## preload(), an extends by path, a scene or resource's ext_resource path,
## or in a script, by one of [param classes]' global names.
func _references(path: String, classes: Dictionary[String, String]) -> Array[String]:
	var by_path := RegEx.create_from_string(
			"(?:load\\(\\s*|extends\\s+|path=)[\"']res://([^\"']+)[\"']")
	var source := FileAccess.get_file_as_string(path)
	var out: Array[String] = []
	for found in by_path.search_all(source):
		out.append(found.get_string(1))
	if path.get_extension() != "gd":
		return out
	var code := SourceFiles.code_only(source)
	for global_name in classes:
		var script := classes[global_name]
		if script != path and RegEx.create_from_string("\\b%s\\b" % global_name).search(code):
			out.append(script.trim_prefix("res://"))
	return out


## Whether [param reference], a "from -> to" line, is in [param listed]
## itself or under one of its folder lines.
func _is_listed(reference: String, listed: Array[String]) -> bool:
	if reference in listed:
		return true
	for line in listed:
		if line.ends_with("/") and reference.begins_with(line):
			return true
	return false


func _listed_references() -> Array[String]:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(LIST_PATH).split("\n", false):
		if not line.begins_with("#"):
			out.append(line.strip_edges())
	return out


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


## Each use [param path] makes of a constant another script preloaded.
func _uses_of_others_preloads(path: String) -> Array[String]:
	var dotted := RegEx.create_from_string("\\b([A-Za-z_]\\w*)\\.([A-Za-z_]\\w*)")
	var code := SourceFiles.code_only(FileAccess.get_file_as_string(path))
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
