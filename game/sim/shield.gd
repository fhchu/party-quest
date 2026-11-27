extends "res://sim/body.gd"
## A player's raised shield: a thin box against the facing side of its
## holder's hurtbox, turning with its facing. A shot or unit touching it is
## blocked.

const Player := preload("res://sim/player.gd")

# Weak, since its holder keeps it: a cycle of references is never freed.
var _holder: WeakRef


## [param size] is its thickness, then its length along the holder's side,
## in px.
func _init(holder: WeakRef, size: Vector2) -> void:
	_holder = holder
	var box := RectangleShape2D.new()
	box.size = size
	collider = box


## Its outer side lies along the holder's hurtbox edge on the facing side.
func collider_transform() -> Transform2D:
	var holder: Player = _holder.get_ref()
	var facing := Direction.to_vector(holder.facing)
	var reach := absf(holder.collider.get_rect().size.dot(facing)) / 2
	var thickness := (collider as RectangleShape2D).size.x
	return Transform2D(facing.angle(), holder.pos + facing * (reach - thickness / 2))
