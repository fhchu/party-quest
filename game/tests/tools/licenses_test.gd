extends GdUnitTestSuite

const Licenses := preload("res://tools/licenses.gd")


func test_notices_carry_godot_license() -> void:
	assert_str(Licenses.notices()).contains(Engine.get_license_text())


func test_notices_name_every_bundled_component() -> void:
	var text := Licenses.notices()
	for component: Dictionary in Engine.get_copyright_info():
		assert_str(text).contains(component.name)


func test_notices_carry_every_license_text() -> void:
	var text := Licenses.notices()
	var licenses := Engine.get_license_info()
	for license_name: String in licenses:
		assert_str(text).contains(licenses[license_name])
