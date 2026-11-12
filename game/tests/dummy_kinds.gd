extends RefCounted
## The dummy kinds tests place, by their names in balance.json.

const DataLoader := preload("res://shared/data_loader.gd")

static var ready_kind := DataLoader.dummy_kind("ready")
static var start_kind := DataLoader.dummy_kind("start")
static var enemy_kind := DataLoader.dummy_kind("enemy")
