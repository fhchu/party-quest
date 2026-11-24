extends Resource
## Every item, in a fixed order: an item's place in it is the number the
## lobby state sends for it. A build's server and client load the same
## list, so the order can change between builds; saved data uses IDs.

const Item := preload("res://shared/data/item.gd")

@export var items: Array[Item] = []


## The number the lobby state sends for the item named [param id]; -1 if
## none is.
func index_of_id(id: String) -> int:
	for i in items.size():
		if items[i].id == id:
			return i
	return -1
