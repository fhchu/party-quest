extends RefCounted
## The level select town shows once the party leaves by its north door: the
## levels in a row, one cursor the whole party moves, and what's been pressed
## since the lobby last acted on it. The lobby keeps one for good, so the
## cursor stays where it was between runs.

var is_open := false
## The level the cursor points at, from 0, and the level chosen once
## [member is_level_chosen].
var cursor := 0
## Seats whose holders pressed back since the lobby last acted; back beats a
## level chosen in the same tick.
var backed_out_by: Array[int] = []
## Whether the cursor's level was chosen since the lobby last acted.
var is_level_chosen := false

var _level_count := 0


func _init(level_count: int) -> void:
	_level_count = level_count


func open() -> void:
	is_open = true


## Shuts it and forgets what was pressed; the cursor stays.
func close() -> void:
	is_open = false
	backed_out_by.clear()
	is_level_chosen = false


## Acts on seat [param player_id]'s [param presses]: each left or right
## press steps the cursor, so a diagonal moves it along the row. The levels
## are one row, so up and down aren't read. Select chooses the cursor's level; back is
## noted for the lobby.
func read_presses(player_id: int, presses: MenuPresses) -> void:
	cursor = wrapi(cursor + presses.right - presses.left, 0, _level_count)
	if presses.select > 0:
		is_level_chosen = true
	if presses.back > 0 and player_id not in backed_out_by:
		backed_out_by.append(player_id)


## Chooses [param level], from 0, as a tap on its square does. A level that
## doesn't exist, which only a bad client sends, changes nothing.
func choose(level: int) -> void:
	if level < 0 or level >= _level_count:
		return
	cursor = level
	is_level_chosen = true


## One seat's presses since its last input, as a menu reads them.
class MenuPresses:
	var left := 0
	var right := 0
	var select := 0
	var back := 0
