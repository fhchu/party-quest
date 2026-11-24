extends RefCounted
## Reads the game's data in shared/ and hands the client plain values. Tick
## math isn't data: scripts that need it use shared/game_time.gd themselves.
## Everything is read once, when this script loads.

const Balance := preload("res://shared/data/balance.gd")
const ItemSword := preload("res://shared/data/items/item_sword.gd")
const DummyKind := preload("res://shared/data/dummy_kind.gd")
const DummyKinds := preload("res://shared/data/dummy_kinds.gd")
const Item := preload("res://shared/data/item.gd")
const Items := preload("res://shared/data/items.gd")
const RoomShape := preload("res://shared/room_shape.gd")
const SwingShape := preload("res://shared/swing_shape.gd")

const BALANCE: Balance = preload("res://shared/data/balance.tres")
const SWORD: ItemSword = preload("res://shared/data/items/sword.tres")
const DUMMY_KINDS: DummyKinds = preload("res://shared/data/dummy_kinds.tres")
const ITEMS: Items = preload("res://shared/data/items.tres")
const GOLD: Item = preload("res://shared/data/items/gold.tres")

static var player_hurtbox: Shape2D = BALANCE.player_hurtbox
static var player_max_health: int = BALANCE.player_max_health
## Gold's number in the lobby state's inventories.
static var gold_index: int = ITEMS.index_of_id(GOLD.id)
## How far ahead of a player its swing starts, in px.
static var swing_offset: float = SWORD.swing_offset
static var swing_ticks := GameTime.ticks(SWORD.swing_active_sec)
## The swing's active slice, as a pie slice pointing along +x.
static var swing_pieces: Array[PackedVector2Array] = SwingShape.pieces(
		SWORD.swing_radius, SWORD.swing_arc() / SWORD.swing_slices)
## Inside the walls, in px.
static var floor_area := RoomShape.floor_area()
## How to draw each dummy kind, by its number in snapshots.
static var dummy_looks: Array[DummyLook] = _make_dummy_looks()
## Walls and doors for each set of door bits a snapshot can send.
static var _walls: Array[Array] = _by_door_bits(RoomShape.walls)
static var _doors: Array[Array] = _by_door_bits(_doors_on)


## The walls of a room whose doors are [param door_bits].
static func walls(door_bits: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	out.assign(_walls[door_bits])
	return out


## The doors of a room whose doors are [param door_bits].
static func doors(door_bits: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	out.assign(_doors[door_bits])
	return out


## The swing's turn, in radians, with [param ticks_left] of it left.
static func swing_turn(ticks_left: int) -> float:
	return SwingShape.slice_turn(SWORD.swing_arc(), SWORD.swing_slices,
			swing_ticks - ticks_left, swing_ticks)


static func _make_dummy_looks() -> Array[DummyLook]:
	var out: Array[DummyLook] = []
	for kind: DummyKind in DUMMY_KINDS.kinds:
		var look := DummyLook.new()
		look.hurtbox = kind.hurtbox_or_default()
		look.color = kind.color
		look.label = kind.label
		look.nose_size = kind.nose_size
		var charge := kind.charge()
		if charge:
			look.charge_length = charge.length
			# Rounded to whole ticks, as the server times it.
			look.charge_lock_sec = GameTime.seconds(GameTime.ticks(charge.aim_lock_sec))
		out.append(look)
	return out


## [param make] called with each set of door sides, indexed by their bits.
static func _by_door_bits(make: Callable) -> Array[Array]:
	var out: Array[Array] = []
	for bits in 1 << Direction.Cardinal.size():
		out.append(make.call(RoomShape.sides_in(bits)))
	return out


static func _doors_on(sides: Array[Direction.Cardinal]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for side in sides:
		out.append(RoomShape.door(side))
	return out


## What the client needs to draw one dummy kind.
class DummyLook:
	## Centered on the dummy and turned with its facing, in px.
	var hurtbox: Shape2D
	var color: Color
	## Empty for none.
	var label: String
	## 0 for none.
	var nose_size: float
	## 0 for a kind that doesn't charge.
	var charge_length := 0.0
	var charge_lock_sec := 0.0
