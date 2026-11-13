extends Resource
## Every dummy kind, in a fixed order: a kind's place in it is the number
## snapshots send for it.

const DummyKind := preload("res://shared/data/dummy_kind.gd")

@export var kinds: Array[DummyKind] = []


## [param kind]'s number in snapshots.
func index_of(kind: DummyKind) -> int:
	return kinds.find(kind)
