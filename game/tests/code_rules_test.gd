extends GdUnitTestSuite
## Written rules about our own scripts that can be checked by reading them:
## each test names the rule it keeps (.agents/rules/style.md, tests.md).

const SourceFiles := preload("res://tests/source_files.gd")
const TESTS_DIR := "res://tests/"
## A constant holding a preloaded script.
const SCRIPT_PRELOAD := "(?m)^\\s*const\\s+(\\w+)\\s*(?::\\s*\\w+\\s*)?:?=\\s*preload\\(" \
		+ "\"(res://[^\"]+\\.gd)\"\\)"
const CLASS_NAME := "(?m)^class_name\\s+(\\w+)"
## Statements a test body must not hold: it has to be plainly right.
const BRANCHES: Array[String] = ["if ", "elif ", "while ", "match "]
## How a loop over a table of cases names the case that failed: a message
## of its own, or a helper that asserts one named fact (tests.md).
const CASE_NAMERS: Array[String] = ["_failure_message", "_assert_"]


## style.md: "Preloaded scripts are constants named like the class".
func test_every_preloaded_script_is_named_like_its_class() -> void:
	var offenders := _misnamed_preloads()
	assert_array(offenders).override_failure_message(
			"Name each preloaded script like its class:\n%s" % "\n".join(offenders)
	).is_empty()


## tests.md, "No logic in a test's body": no branch, and a loop only over a
## table of cases whose failures name their case. A loop that drives the
## code goes in a helper named for what it does.
func test_no_test_body_holds_logic() -> void:
	var offenders := _tests_with_logic()
	assert_array(offenders).override_failure_message(
			"Move it into a helper named for what it does, or name the case that failed:\n%s"
			% "\n".join(offenders)).is_empty()


func test_a_loop_whose_failures_name_their_case_is_fine() -> void:
	var body := ["\tfor x: int in [1, 2]:", "\t\tassert_int(x).override_failure_message(\"%d\")"]
	assert_array(_logic_in_body(body)).is_empty()


func test_a_loop_through_a_helper_that_asserts_a_named_fact_is_fine() -> void:
	var body := ["\tfor i in sent.size():", "\t\t_assert_seat_kept(back[i], sent[i])"]
	assert_array(_logic_in_body(body)).is_empty()


func test_a_loop_whose_failures_dont_name_their_case_is_logic() -> void:
	assert_array(_logic_in_body(["\tfor x: int in [1, 2]:", "\t\tassert_int(x).is_equal(1)"])) \
			.contains_exactly(["for"])


func test_a_branch_is_logic_even_in_a_loop_that_names_its_case() -> void:
	var body := ["\tfor x: int in [1, 2]:", "\t\tif x > 1:",
			"\t\t\tassert_int(x).override_failure_message(\"%d\")"]
	assert_array(_logic_in_body(body)).contains_exactly(["if"])


func test_an_inline_if_is_not_a_branch() -> void:
	assert_array(_logic_in_body(["\tvar x := 1 if a else 2"])).is_empty()


func test_a_preload_may_name_an_acronym_in_capitals() -> void:
	assert_bool(_named_like("LobbyUI", "res://client/ui/lobby_ui.gd")).is_true()


func test_a_preload_named_for_another_class_is_misnamed() -> void:
	assert_bool(_named_like("Lobby", "res://client/ui/lobby_ui.gd")).is_false()


func test_a_preload_is_named_for_a_declared_class_name() -> void:
	assert_str(_class_of("res://tests/source_files.gd")).is_equal("SourceFiles")


## "path: Name, not Expected" for each preloaded script named unlike its
## class.
func _misnamed_preloads() -> Array[String]:
	var out: Array[String] = []
	for path in SourceFiles.our_scripts():
		out.append_array(_misnamed_preloads_in(path))
	return out


## "path: Name, not Expected" for each script [param path] preloads under a
## name unlike its class.
func _misnamed_preloads_in(path: String) -> Array[String]:
	var out: Array[String] = []
	# The source, not code_only: a preload's path is a string.
	var source := FileAccess.get_file_as_string(path)
	for found in RegEx.create_from_string(SCRIPT_PRELOAD).search_all(source):
		var const_name := found.get_string(1)
		if not _named_like(const_name, found.get_string(2)):
			out.append("%s: %s, not %s" % [path, const_name, _class_of(found.get_string(2))])
	return out


## "path: test_name has KEYWORD" for each test whose body holds logic.
func _tests_with_logic() -> Array[String]:
	var out: Array[String] = []
	for path in SourceFiles.files_in(TESTS_DIR.trim_suffix("/"), ["gd"]):
		if path.ends_with("_test.gd"):
			out.append_array(_logic_in_tests(path))
	return out


## Each "path: test_name has KEYWORD" for a test in [param path] whose body
## holds logic.
func _logic_in_tests(path: String) -> Array[String]:
	var out: Array[String] = []
	var bodies := _test_bodies(SourceFiles.code_only(FileAccess.get_file_as_string(path)))
	for test: String in bodies:
		for keyword in _logic_in_body(bodies[test]):
			out.append("%s: %s has %s" % [path, test, keyword])
	return out


## Each test function's name in [param code], to its body's lines: the
## indented and blank lines up to the next line that isn't.
func _test_bodies(code: String) -> Dictionary[String, Array]:
	var out: Dictionary[String, Array] = {}
	var test := ""
	for line in code.split("\n"):
		if line.begins_with("\t") or line.strip_edges().is_empty():
			if not test.is_empty():
				out[test].append(line)
		elif line.begins_with("func test_"):
			test = line.get_slice("(", 0).trim_prefix("func ")
			out[test] = []
		else:
			test = ""
	return out


## The logic keywords [param body], a test's lines, holds: each branch
## keyword it starts a statement with, and "for" for a loop whose failures
## don't name their case.
func _logic_in_body(body: Array) -> Array[String]:
	var out: Array[String] = []
	var names_case := false
	for line: String in body:
		for namer in CASE_NAMERS:
			names_case = names_case or namer in line
	for line: String in body:
		var statement := line.strip_edges()
		for branch in BRANCHES:
			if statement.begins_with(branch) and branch.strip_edges() not in out:
				out.append(branch.strip_edges())
		if statement.begins_with("for ") and not names_case and "for" not in out:
			out.append("for")
	return out


## Whether [param const_name] names the script at [param script_path] like its
## class, case aside, so an acronym may be in capitals.
func _named_like(const_name: String, script_path: String) -> bool:
	return const_name.to_lower() == _class_of(script_path).to_lower()


## The class a preloaded script is named for: its class_name, or else its
## file name in PascalCase.
func _class_of(script_path: String) -> String:
	var found := RegEx.create_from_string(CLASS_NAME).search(
			FileAccess.get_file_as_string(script_path))
	return found.get_string(1) if found else script_path.get_file().get_basename().to_pascal_case()
