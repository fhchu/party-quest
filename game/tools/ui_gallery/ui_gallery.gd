extends SceneTree
## Renders every shot in shots.gd to a PNG, plus a captioned contact sheet
## of all of them and a shots.json of names and captions. Run through
## ../../ui-gallery.sh; it needs a window, since a headless Godot draws
## nothing.
##
## [code]godot --path game -s res://tools/ui_gallery/ui_gallery.gd -- <out dir>[/code]

const Shots := preload("res://tools/ui_gallery/shots.gd")
const GameRenderer := preload("res://client/game_renderer.gd")
const GameRendererScene := preload("res://client/game_renderer.tscn")

## Shots are drawn at this multiple of the game's base resolution, as a
## browser window that size would show them.
const SHOT_SCALE := 2
## Thumbnails on the contact sheet, as a multiple of the base resolution.
const SHEET_SCALE := 1.5
const SHEET_COLUMNS := 2
const SHEET_GAP := 16
const SHEET_CAPTION_SIZE := 20
const SHEET_BG_COLOR := Color(0.18, 0.18, 0.2)
const SHEET_CAPTION_COLOR := Color(0.9, 0.9, 0.9)
const SHEET_FILE := "contact_sheet.png"
const INDEX_FILE := "shots.json"
## Shot names become file names.
const NAME_PATTERN := "^[a-z0-9_]+$"
## Containers lay out a frame after they enter the tree, then the result is
## drawn the frame after.
const SETTLE_FRAMES := 2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("usage: ui_gallery.gd -- <out dir>")
		quit(1)
		return
	var out_dir: String = args[0]
	var err := DirAccess.make_dir_recursive_absolute(out_dir)
	if err != OK:
		push_error("can't make %s: %s" % [out_dir, error_string(err)])
		quit(1)
		return

	var base := Shots.base_size()
	var shots := Shots.all()
	if not _names_are_file_names(shots):
		quit(1)
		return
	# One at a time, since every shot's touch buttons light from the one
	# global Input: a thumb held in one shot would light them in all.
	var images: Array[Image] = []
	for shot in shots:
		images.append(await _render_shot(shot, base))
	var sheet := _build_sheet(shots, images, base)
	await _settle()
	# The grid knows its size only once laid out.
	sheet.size = Vector2i((sheet.get_child(0) as Control).get_combined_minimum_size())
	await _settle()

	if not _write(out_dir, shots, images, sheet):
		quit(1)
		return
	print("%d shots in %s" % [shots.size(), out_dir])
	quit()


## [param shot] drawn at [constant SHOT_SCALE] times [param base]. Lifts its
## thumb before freeing it, so nothing it pressed stays held.
func _render_shot(shot: Shots.Shot, base: Vector2i) -> Image:
	var vp := _show_shot(shot, base)
	await _settle()
	var image := vp.get_texture().get_image()
	if not shot.thumb.is_empty():
		var lift := InputEventScreenTouch.new()
		lift.position = shot.thumb[-1]
		vp.push_input(lift, true)
	vp.free()
	return image


## A viewport drawing [param shot] at [constant SHOT_SCALE] times [param base].
func _show_shot(shot: Shots.Shot, base: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = base * SHOT_SCALE
	# Lays the UI out at the base size and draws it scaled, as the game's
	# canvas_items stretch mode does.
	vp.size_2d_override = base
	vp.size_2d_override_stretch = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var game_renderer: GameRenderer = GameRendererScene.instantiate()
	vp.add_child(game_renderer)
	game_renderer.render(shot.state)
	for i in shot.thumb.size():
		vp.push_input(_thumb_event(shot.thumb[i], i == 0), true)
	return vp


## The thumb landing at [param pos], or dragged there.
func _thumb_event(pos: Vector2, lands: bool) -> InputEvent:
	if lands:
		var touch := InputEventScreenTouch.new()
		touch.position = pos
		touch.pressed = true
		return touch
	var drag := InputEventScreenDrag.new()
	drag.position = pos
	return drag


## Whether every shot's name is a distinct, valid file name, so no PNG
## overwrites another. Reports each bad one.
func _names_are_file_names(shots: Array[Shots.Shot]) -> bool:
	var pattern := RegEx.create_from_string(NAME_PATTERN)
	var seen := {}
	var ok := true
	for shot in shots:
		if not pattern.search(shot.name):
			push_error("shot name %s isn't a file name (%s)" % [shot.name, NAME_PATTERN])
			ok = false
		elif seen.has(shot.name):
			push_error("two shots are named %s" % shot.name)
			ok = false
		seen[shot.name] = true
	return ok


## Saves each shot, the sheet and the index into [param out_dir]. False if
## a file couldn't be written.
func _write(
		out_dir: String, shots: Array[Shots.Shot], images: Array[Image],
		sheet: SubViewport) -> bool:
	var index: Array[Dictionary] = []
	for i in shots.size():
		if not _save(images[i], out_dir.path_join(shots[i].name + ".png")):
			return false
		index.append({ "name": shots[i].name, "caption": shots[i].caption })
	if not _save(sheet.get_texture().get_image(), out_dir.path_join(SHEET_FILE)):
		return false
	var f := FileAccess.open(out_dir.path_join(INDEX_FILE), FileAccess.WRITE)
	if not f:
		push_error("can't write %s" % INDEX_FILE)
		return false
	f.store_string(JSON.stringify(index, "\t"))
	f.close()
	return true


## A viewport showing each shot's image under its caption, in a grid.
func _build_sheet(
		shots: Array[Shots.Shot], images: Array[Image], base: Vector2i) -> SubViewport:
	var sheet := SubViewport.new()
	sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sheet)
	var bg := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = SHEET_BG_COLOR
	style.set_content_margin_all(SHEET_GAP)
	bg.add_theme_stylebox_override("panel", style)
	sheet.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = SHEET_COLUMNS
	grid.add_theme_constant_override("h_separation", SHEET_GAP)
	grid.add_theme_constant_override("v_separation", SHEET_GAP)
	bg.add_child(grid)
	for i in shots.size():
		var cell := VBoxContainer.new()
		grid.add_child(cell)
		var caption := Label.new()
		caption.text = "%s  (%s)" % [shots[i].caption, shots[i].name]
		caption.add_theme_font_size_override("font_size", SHEET_CAPTION_SIZE)
		caption.add_theme_color_override("font_color", SHEET_CAPTION_COLOR)
		cell.add_child(caption)
		var thumb := TextureRect.new()
		thumb.texture = ImageTexture.create_from_image(images[i])
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.custom_minimum_size = Vector2(base) * SHEET_SCALE
		cell.add_child(thumb)
	return sheet


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw


func _save(image: Image, path: String) -> bool:
	var err := image.save_png(path)
	if err != OK:
		push_error("can't write %s: %s" % [path, error_string(err)])
		return false
	return true
