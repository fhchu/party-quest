extends GdUnitTestSuite
## The UI gallery's shots still build and show, so the gallery doesn't break
## unnoticed when the UI changes. Drawing them needs a window, so that part
## runs only in ui-gallery.sh.

const Shots := preload("res://tools/ui_gallery/shots.gd")
const RoomUIScene := preload("res://client/ui/room_ui.tscn")

## Shot names become file names.
const NAME_PATTERN := "^[a-z0-9_]+$"


## Fails through GdUnit4's script-error reporting: a shot the room UI can no
## longer show errors out.
func test_every_shot_shows_on_the_room_ui() -> void:
	for shot in Shots.all():
		var room_ui: Control = auto_free(RoomUIScene.instantiate())
		add_child(room_ui)
		room_ui.show_state(shot.state)


func test_shot_names_are_unique_file_names() -> void:
	var pattern := RegEx.create_from_string(NAME_PATTERN)
	var seen := {}
	for shot in Shots.all():
		assert_object(pattern.search(shot.name)).override_failure_message(shot.name).is_not_null()
		assert_bool(seen.has(shot.name)).override_failure_message(shot.name).is_false()
		seen[shot.name] = true
