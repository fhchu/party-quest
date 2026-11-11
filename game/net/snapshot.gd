extends RefCounted
## One tick of the world as clients see it. The server makes it from the
## World; snapshot_codec.gd packs it to fit one datagram.

## The most a dummy's [member Dummy.ticks_since_struck] says: the largest
## value of its u8 field in snapshot_codec.gd. Anything older, or never, reads
## as this.
const STRUCK_LONG_AGO := 0xff

var tick := 0
## Left on the run timer; 0 outside a run.
var run_ticks_left := 0
## Which world it's from (Lobby.world_number). A new number means the lobby
## changed phase and everything was replaced.
var world_number := 0
var players: Array[Player] = []
var dummies: Array[Dummy] = []
var projectiles: Array[Projectile] = []
## How many bytes it arrived in; 0 if it wasn't unpacked from the wire.
var packed_size := 0


## Null if no player has [param id].
func find_player(id: int) -> Player:
	for p in players:
		if p.id == id:
			return p
	return null


## Null if no dummy has [param id].
func find_dummy(id: int) -> Dummy:
	for d in dummies:
		if d.id == id:
			return d
	return null


## Null if no projectile has [param id].
func find_projectile(id: int) -> Projectile:
	for s in projectiles:
		if s.id == id:
			return s
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
	## Can't be hurt for now: they were hurt a moment ago.
	var invulnerable := false

	## At 0 health: out of the fight until the run ends.
	func is_downed() -> bool:
		return health == 0

	func copy() -> Player:
		var p := Player.new()
		p.id = id
		p.pos = pos
		p.facing = facing
		p.swing_ticks = swing_ticks
		p.connected = connected
		p.health = health
		p.invulnerable = invulnerable
		return p


class Dummy:
	## Unique within its world (Snapshot.world_number).
	var id := 0
	var pos := Vector2.ZERO
	## Any direction, not only World.DIRECTIONS.
	var facing := Vector2.DOWN
	## Ticks from a swing last touching it to the snapshot's tick, at most
	## [constant STRUCK_LONG_AGO]. Negative in a blended view when the hit
	## comes after the moment drawn.
	var ticks_since_struck := STRUCK_LONG_AGO
	## A World.Kind. An int, since world.gd already depends on this script.
	var kind := 0

	func copy() -> Dummy:
		var d := Dummy.new()
		d.id = id
		d.pos = pos
		d.facing = facing
		d.ticks_since_struck = ticks_since_struck
		d.kind = kind
		return d


class Projectile:
	## Unique within its world (Snapshot.world_number), among dummies and
	## projectiles both.
	var id := 0
	var pos := Vector2.ZERO
	## In px.
	var radius := 0.0

	func copy() -> Projectile:
		var s := Projectile.new()
		s.id = id
		s.pos = pos
		s.radius = radius
		return s
