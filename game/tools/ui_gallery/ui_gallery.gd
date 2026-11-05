extends SceneTree
## Renders every shot in shots.gd to a PNG, plus a captioned contact sheet
## of all of them and a shots.json of names and captions. Run through
## ../../ui-gallery.sh; it needs a window, since a headless Godot draws
## nothing.
##
## [code]godot --path game -s res://tools/ui_gallery/ui_gallery.gd -- <out dir>[/code]

const Shots := preload("res://tools/ui_gallery/shots.gd")
const ArenaView := preload("res://client/arena_view.gd")
const RoomHudScene := preload("res://client/ui/room_hud.tscn")
const CenterNoticeScene := preload("res://client/ui/center_notice.tscn")

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

	var base := Vector2i(
			ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	var shots := Shots.all()
	var viewports: Array[SubViewport] = []
	for shot in shots:
		viewports.append(_show_shot(shot, base))
	var sheet := _build_sheet(shots, viewports, base)
	await _settle()
	# The grid knows its size only once laid out.
	sheet.size = Vector2i((sheet.get_child(0) as Control).get_combined_minimum_size())
	await _settle()

	if not _write(out_dir, shots, viewports, sheet):
		quit(1)
		return
	print("%d shots in %s" % [shots.size(), out_dir])
	quit()


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
	# The same three pieces, in the same order, as client.gd puts on screen.
	var s := shot.state
	var arena := ArenaView.new()
	vp.add_child(arena)
	arena.show_view(s.view, s.my_id, s.room != null and s.room.all_ready())
	var hud: Control = RoomHudScene.instantiate()
	vp.add_child(hud)
	hud.show_state(s)
	var notice: Control = CenterNoticeScene.instantiate()
	vp.add_child(notice)
	notice.show_text(s.notice)
	return vp


## Saves each shot, the sheet and the index into [param out_dir]. False if
## a file couldn't be written.
func _write(
		out_dir: String, shots: Array[Shots.Shot], viewports: Array[SubViewport],
		sheet: SubViewport) -> bool:
	var index: Array[Dictionary] = []
	for i in shots.size():
		if not _save(viewports[i], out_dir.path_join(shots[i].name + ".png")):
			return false
		index.append({ "name": shots[i].name, "caption": shots[i].caption })
	if not _save(sheet, out_dir.path_join(SHEET_FILE)):
		return false
	var f := FileAccess.open(out_dir.path_join(INDEX_FILE), FileAccess.WRITE)
	if not f:
		push_error("can't write %s" % INDEX_FILE)
		return false
	f.store_string(JSON.stringify(index, "\t"))
	f.close()
	return true


## A viewport showing each shot's live texture under its caption, in a grid.
func _build_sheet(
		shots: Array[Shots.Shot], viewports: Array[SubViewport], base: Vector2i) -> SubViewport:
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
		thumb.texture = viewports[i].get_texture()
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.custom_minimum_size = Vector2(base) * SHEET_SCALE
		cell.add_child(thumb)
	return sheet


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw


func _save(vp: SubViewport, path: String) -> bool:
	var err := vp.get_texture().get_image().save_png(path)
	if err != OK:
		push_error("can't write %s: %s" % [path, error_string(err)])
		return false
	return true
