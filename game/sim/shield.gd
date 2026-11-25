extends "res://sim/body.gd"
## A player's raised shield: a thin box against the facing side of its
## holder's hurtbox, turning with its facing. A shot or dummy touching it is
## blocked.

const Player := preload("res://sim/player.gd")
const ActionGuard := preload("res://sim/action_guard.gd")

## The input action that raised it: letting go of that lowers it.
var input_index := 0

# Weak, since its holder keeps it: a cycle of references is never freed.
var _holder: WeakRef


func _init(holder: Player, guard: ActionGuard, index: int) -> void:
	_holder = weakref(holder)
	input_index = index
	var box := RectangleShape2D.new()
	box.size = Vector2(guard.thickness_px, guard.length_px)
	collider = box


## Its outer side lies along the holder's hurtbox edge on the facing side.
func collider_transform() -> Transform2D:
	var holder: Player = _holder.get_ref()
	var facing := Direction.to_vector(holder.facing)
	var reach := absf(holder.collider.get_rect().size.dot(facing)) / 2
	var thickness := (collider as RectangleShape2D).size.x
	return Transform2D(facing.angle(), holder.pos + facing * (reach - thickness / 2))
