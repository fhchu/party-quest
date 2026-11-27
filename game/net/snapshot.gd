extends RefCounted
## One tick of the world as clients see it. WorldSnapshot makes it from the
## world's state; snapshot_codec.gd packs it to fit one datagram.

## How many bits [member door_bits] may use: a wall each. Must hold
## shared/direction.gd's Cardinal; tests/net/snapshot_codec_test.gd checks.
const DOOR_BIT_COUNT := 4
## The most a unit's [member Unit.ticks_since_struck] says: the largest
## value of its u8 field in snapshot_codec.gd. Anything older, or never, reads
## as this.
const STRUCK_LONG_AGO := 0xff
## [member run_ticks_left] when there's no timer to show: the largest value
## of its u16 field in snapshot_codec.gd, since 0 means time is up.
const NO_TIMER := 0xffff
## The most a [member Player.slot_ticks] entry says: the largest value of its
## u8 field in snapshot_codec.gd. A longer-held action reads as this.
const SLOT_TICKS_MAX := 0xff

var tick := 0
## Left on the run's timer; [constant NO_TIMER] outside a run or for a run
## without one.
var run_ticks_left := NO_TIMER
## Which layout it's from (WorldState.layout_number). A new number means positions
## jump instead of sliding there: a new world, or the party entered another
## room.
var layout_number := 0
## The walls of the party's room that have doors, one bit per wall as
## shared/room_shape.gd's [code]door_bits()[/code] packs them.
var door_bits := 0
## Whether the party's room is cleared, which opens its doors.
var room_cleared := false
## Seeds how the party's room's floor is drawn (RoomState.graphics_seed).
var graphics_seed := 0
var players: Array[Player] = []
var units: Array[Unit] = []
var projectiles: Array[Projectile] = []
## How many bytes it arrived in; 0 if it wasn't unpacked from the wire.
var packed_size := 0


class Player:
	## The seat number.
	var id := 0
	var pos := Vector2.ZERO
	var facing := Vector2.RIGHT
	## For each item slot, ticks since its action became active, counting the
	## first as 1, up to [constant SLOT_TICKS_MAX]; 0 while idle or empty.
	var slot_ticks := PackedByteArray()
	var connected := true
	var health := 0
	## Can't be hurt for now: they were hurt a moment ago.
	var invulnerable := false


class Unit:
	## Unique within its world.
	var id := 0
	var pos := Vector2.ZERO
	var facing := Vector2.DOWN
	## Ticks from a swing last touching it to the snapshot's tick, at most
	## [constant STRUCK_LONG_AGO].
	var ticks_since_struck := STRUCK_LONG_AGO
	## Its number in shared/data/units.tres.
	var unit_type := 0
	## While its aim is locked for a charge, the ticks until it charges;
	## else 0.
	var charge_windup_ticks_left := 0.0


class Projectile:
	## Unique within its world, among units and projectiles both.
	var id := 0
	var pos := Vector2.ZERO
	## In px.
	var radius := 0.0
