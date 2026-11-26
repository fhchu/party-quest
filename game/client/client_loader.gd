extends RefCounted
## Reads the game's data in shared/ and hands the client plain values. Tick
## math isn't data: scripts that need it use GameTime themselves.
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
const DUMMY_KINDS: DummyKinds = preload("res://shared/data/dummy_kinds.tres")
const ITEMS: Items = preload("res://shared/data/items.tres")
const GOLD: Item = preload("res://shared/data/items/item_gold.tres")
## Where each [member Item.icon_file] is.
const ITEM_ICON_DIR := "res://client/assets/textures/"

static var player_hurtbox: Shape2D = BALANCE.player_hurtbox
static var player_max_health: int = BALANCE.player_max_health
## Gold's number in the lobby state's inventories.
static var gold_index: int = ITEMS.index_of_id(GOLD.id)
## How to show each item, by its number in lobby states.
static var item_looks: Array[ItemLook] = _make_item_looks()
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


static func _make_item_looks() -> Array[ItemLook]:
	var out: Array[ItemLook] = []
	for item: Item in ITEMS.items:
		var look := ItemLook.new()
		look.display_name = item.display_name
		look.icon = _load_item_icon(item.icon_file)
		var sword := item as ItemSword
		if sword:
			look.swing = SwingLook.new(sword)
		out.append(look)
	return out


## Null for no icon: none named, or a clone without the art.
static func _load_item_icon(file: String) -> Texture2D:
	var path := ITEM_ICON_DIR + file
	if file.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path)


static func _make_dummy_looks() -> Array[DummyLook]:
	var out: Array[DummyLook] = []
	for kind: DummyKind in DUMMY_KINDS.kinds:
		var look := DummyLook.new()
		look.hurtbox = kind.hurtbox_or_default()
		look.color = kind.color
		look.label = kind.label
		look.ready_label = kind.ready_label
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


## What the client needs to show one item.
class ItemLook:
	var display_name: String
	## Null for none.
	var icon: Texture2D
	## Null for an item that doesn't swing.
	var swing: SwingLook


## How to draw a sword's swing.
class SwingLook:
	## How far ahead of a player the swing starts, in px.
	var offset: float
	var ticks: int
	## The active slice, as a pie slice pointing along +x.
	var pieces: Array[PackedVector2Array]
	var _arc: float
	var _slices: int

	func _init(sword: ItemSword) -> void:
		offset = sword.swing_offset
		ticks = GameTime.ticks(sword.swing_active_sec)
		_arc = sword.swing_arc()
		_slices = sword.swing_slices
		pieces = SwingShape.pieces(sword.swing_radius, _arc / _slices)

	## The slice's turn from the facing, in radians, on tick [param tick] of
	## the swing, counting the first as 1.
	func turn(tick: int) -> float:
		return SwingShape.slice_turn(_arc, _slices, tick - 1, ticks)


## What the client needs to draw one dummy kind.
class DummyLook:
	## Centered on the dummy and turned with its facing, in px.
	var hurtbox: Shape2D
	var color: Color
	## Empty for none.
	var label: String
	## Shown instead of [member label] while your own seat is ready; empty
	## for always [member label].
	var ready_label: String
	## 0 for none.
	var nose_size: float
	## 0 for a kind that doesn't charge.
	var charge_length := 0.0
	var charge_lock_sec := 0.0
