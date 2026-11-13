extends RefCounted
## The dummy kinds tests place: each kind's file, and its number in
## snapshots and on World.Dummy.kind.

const DummyKinds := preload("res://shared/data/dummy_kinds.gd")

const DUMMY_KINDS: DummyKinds = preload("res://shared/data/dummy_kinds.tres")
const READY := preload("res://shared/data/dummy_kinds/ready.tres")
const START := preload("res://shared/data/dummy_kinds/start.tres")
const ENEMY := preload("res://shared/data/dummy_kinds/enemy.tres")

static var ready_kind := DUMMY_KINDS.index_of(READY)
static var start_kind := DUMMY_KINDS.index_of(START)
static var enemy_kind := DUMMY_KINDS.index_of(ENEMY)
