extends RefCounted
## Colors shared by the arena drawing and the UI.

# PLACEHOLDER (art): until there are sprites.
## One per seat, red, blue, yellow, green: player IDs are seat numbers, 1 to
## MAX_PLAYERS.
const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.25, 0.25),
	Color(0.25, 0.45, 0.95),
	Color(0.95, 0.8, 0.15),
	Color(0.25, 0.75, 0.3),
]


## The color of seat [param id], 1 to MAX_PLAYERS.
static func player_color(id: int) -> Color:
	return PLAYER_COLORS[id - 1]
