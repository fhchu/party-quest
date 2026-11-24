extends Resource
## A player's account data: what they own and what sits in their two item
## slots. The server loads it and keeps it on their seat; a character in
## the world gets only the parts it uses.

## A slot with no item in it.
const EMPTY_SLOT := ""

## Item ID to how many they own. An item they own none of has no entry.
@export var inventory: Dictionary[String, int] = {}
## Two item IDs, or EMPTY_SLOT: the first is used by the use_item_1 action,
## the second by use_item_2. Every item in a slot is in [member inventory].
@export var slot_items: Array[String] = []


func quantity_of(id: String) -> int:
	return inventory.get(id, 0)


## [param quantity] is above 0.
func add_item(id: String, quantity: int) -> void:
	assert(quantity > 0)
	inventory[id] = quantity_of(id) + quantity


## [param quantity] is above 0 and at most what they own. Taking the last
## one empties any slot it's in.
func remove_item(id: String, quantity: int) -> void:
	assert(quantity > 0 and quantity <= quantity_of(id))
	inventory[id] -= quantity
	if inventory[id] > 0:
		return
	inventory.erase(id)
	for i in slot_items.size():
		if slot_items[i] == id:
			slot_items[i] = EMPTY_SLOT
