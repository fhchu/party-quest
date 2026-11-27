extends RefCounted
## The unit types tests place: each unit type's file, and its number in
## snapshots and on Unit.unit_type.

const Units := preload("res://shared/data/units.gd")

const UNITS: Units = preload("res://shared/data/units.tres")
const READY := preload("res://shared/data/units/unit_ready_dummy.tres")
const TURRET := preload("res://shared/data/units/unit_turret.tres")
const CHARGER := preload("res://shared/data/units/unit_charger.tres")

static var ready_type := UNITS.index_of(READY)
static var turret_type := UNITS.index_of(TURRET)
static var charger_type := UNITS.index_of(CHARGER)
