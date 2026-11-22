extends RefCounted
## The dummy kinds tests place: each kind's file, and its number in
## snapshots and on Dummy.kind.

const DummyKinds := preload("res://shared/data/dummy_kinds.gd")

const DUMMY_KINDS: DummyKinds = preload("res://shared/data/dummy_kinds.tres")
const READY := preload("res://shared/data/dummy_kinds/ready.tres")
const TURRET := preload("res://shared/data/dummy_kinds/turret.tres")
const CHARGER := preload("res://shared/data/dummy_kinds/charger.tres")

static var ready_kind := DUMMY_KINDS.index_of(READY)
static var turret_kind := DUMMY_KINDS.index_of(TURRET)
static var charger_kind := DUMMY_KINDS.index_of(CHARGER)
