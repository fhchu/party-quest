extends GdUnitTestSuite
## Which game folders may reference which. server/ and client/ are the two
## sides; sim/, net/ and util/ are shared by both, so they must not reach into
## either side. main.gd and the exempt folders may use anything.

## For each folder, the folders its scripts, scenes and resources must never
## reference.
const FORBIDDEN: Dictionary[String, Array] = {
	"sim": ["server", "client"],
	"net": ["server", "client"],
	"util": ["server", "client"],
	"server": ["client"],
	"client": ["server"],
}
## Top-level folders the rule doesn't apply to: dev-only code, the vendored
## test framework, and generated output that git ignores.
const EXEMPT: Array[String] = ["tests", "tools", "addons", "build", "reports"]
## The files that can reference another file by path.
const CHECKED_EXTENSIONS: Array[String] = ["gd", "tscn", "tres"]
## Folders left out of the class_name search: the vendored framework and
## generated output, which aren't ours.
const NOT_OURS: Array[String] = ["addons", "build", "reports"]


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
