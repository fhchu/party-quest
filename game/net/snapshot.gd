extends RefCounted
## One tick of the world as clients see it. The server makes it from the
## World; snapshot_codec.gd packs it to fit one datagram.

var tick := 0
var players: Array[Player] = []
var dummies: Array[Dummy] = []


## Null if no player has [param id].
func find_player(id: int) -> Player:
	for p in players:
		if p.id == id:
			return p
	return null


class Player:
	## The seat number.
	var id := 0
	var pos := Vector2.ZERO
	var facing := Vector2.RIGHT
	## Left in the swing; 0 when not swinging.
	var swing_ticks := 0
	var connected := true
	var health := 0
	## Flashing from damage.
	var hit := false

	func copy() -> Player:
		var p := Player.new()
		p.id = id
		p.pos = pos
		p.facing = facing
		p.swing_ticks = swing_ticks
		p.connected = connected
		p.health = health
		p.hit = hit
		return p


class Dummy:
	var pos := Vector2.ZERO
	## Flashing from a hit.
	var hit := false
	## A World.Kind. An int, since world.gd already depends on this script.
	var kind := 0

	func copy() -> Dummy:
		var d := Dummy.new()
		d.pos = pos
		d.hit = hit
		d.kind = kind
		return d
