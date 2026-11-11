extends GdUnitTestSuite
## Every UI gallery shot lays out readably: whatever the UI shows has a size,
## sits on screen and inside its parent, and the screen's areas don't
## overlap. Checks where things are, not how they look.

const Shots := preload("res://tools/ui_gallery/shots.gd")
const GameView := preload("res://client/game_view.gd")
const GameViewScene := preload("res://client/game_view.tscn")

## The UI's separate areas, as paths from GameView. None may overlap another.
const REGIONS: Array[NodePath] = [
	^"%LobbyUI/%LobbyCode",
	^"%LobbyUI/%Timer",
	^"%LobbyUI/%Prompts",
	^"%LobbyUI/%PartyBar",
	^"%Notice/Panel",
]
## Containers lay out their children a frame after they enter the tree.
const SETTLE_FRAMES := 2


func test_every_visible_control_is_on_screen() -> void:
	var screen := Rect2(Vector2.ZERO, _base_size())
	for shot in Shots.all():
		var game_view: GameView = await _show(shot)
		for c in _shown_controls(game_view):
			var where := _where(shot, game_view, c)
			assert_bool(c.size.x > 0 and c.size.y > 0) \
					.override_failure_message(where + " has no size").is_true()
			assert_bool(screen.encloses(c.get_global_rect())) \
					.override_failure_message(where + " is off screen").is_true()


func test_every_control_stays_inside_its_parent() -> void:
	for shot in Shots.all():
		var game_view: GameView = await _show(shot)
		for c in _shown_controls(game_view):
			var parent := c.get_parent() as Control
			if not parent:
				continue
			var message := _where(shot, game_view, c) + " spills out of its parent"
			assert_bool(parent.get_global_rect().encloses(c.get_global_rect())) \
					.override_failure_message(message).is_true()


func test_ui_regions_do_not_overlap() -> void:
	for shot in Shots.all():
		var game_view: GameView = await _show(shot)
		var shown: Array[Control] = []
		for path in REGIONS:
			var region: Control = game_view.get_node(path)
			if _is_shown(region):
				shown.append(region)
		_assert_apart(shot, game_view, shown)


## Fails for each pair of [param regions] that overlap.
func _assert_apart(shot: Shots.Shot, game_view: GameView, regions: Array[Control]) -> void:
	for i in regions.size():
		for j in range(i + 1, regions.size()):
			var message := "%s: %s overlaps %s" % [
					shot.name, game_view.get_path_to(regions[i]), game_view.get_path_to(regions[j])]
			assert_bool(regions[i].get_global_rect().intersects(regions[j].get_global_rect())) \
					.override_failure_message(message).is_false()


## The game's base resolution, which the UI is laid out at.
func _base_size() -> Vector2i:
	return Vector2i(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))


## A GameView showing [param shot] in a viewport the size of the base
## resolution, once it's laid out.
func _show(shot: Shots.Shot) -> GameView:
	var viewport: SubViewport = auto_free(SubViewport.new())
	viewport.size = _base_size()
	add_child(viewport)
	var game_view: GameView = GameViewScene.instantiate()
	viewport.add_child(game_view)
	game_view.render(shot.state)
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	return game_view


## Every control on screen. Hidden ones keep a stale layout, so they're left
## out, as are empty labels, which show nothing.
func _shown_controls(game_view: GameView) -> Array[Control]:
	var out: Array[Control] = []
	for node in game_view.find_children("*", "Control", true, false):
		if _is_shown(node):
			out.append(node)
	return out


func _is_shown(c: Control) -> bool:
	return c.is_visible_in_tree() and not (c is Label and (c as Label).text.is_empty())


func _where(shot: Shots.Shot, game_view: GameView, c: Control) -> String:
	return "%s: %s" % [shot.name, game_view.get_path_to(c)]
