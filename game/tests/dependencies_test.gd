extends GdUnitTestSuite
## Which game folders may load scripts from which. server/ and client/ are
## the two sides; sim/, net/ and util/ are shared by both, so they must not
## reach into either side. main.gd, tools/ and tests/ may use anything.

## For each folder, the folders its scripts must never load from.
const FORBIDDEN: Dictionary[String, Array] = {
	"sim": ["server", "client"],
	"net": ["server", "client"],
	"util": ["server", "client"],
	"server": ["client"],
	"client": ["server"],
}


func test_no_folder_loads_from_one_it_must_not() -> void:
	# Group 1: the top-level folder a load() or preload() reaches into.
	var reference := RegEx.create_from_string("load\\(\"res://([a-z_]+)/")
	for folder: String in FORBIDDEN:
		var offenders: Array[String] = []
		for path in _scripts_in("res://" + folder):
			var source := FileAccess.get_file_as_string(path)
			for found in reference.search_all(source):
				if found.get_string(1) in FORBIDDEN[folder]:
					offenders.append("%s loads res://%s/" % [path, found.get_string(1)])
		assert_array(offenders).override_failure_message(
				"%s/ must not load from %s/:\n%s" % [
					folder, "/ or ".join(FORBIDDEN[folder]), "\n".join(offenders)]
		).is_empty()


func test_finds_the_scripts_it_checks() -> void:
	for folder: String in FORBIDDEN:
		assert_array(_scripts_in("res://" + folder)).is_not_empty()


## Every .gd file under [param dir], in subfolders too.
func _scripts_in(dir: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() == "gd":
			found.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_scripts_in(dir.path_join(sub)))
	return found
