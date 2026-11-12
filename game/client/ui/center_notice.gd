extends Control
## One line in the middle of the screen: connecting, reconnecting, why the
## server turned this player away, or the run's outcome. Hidden when empty.

@onready var _text: Label = %Text


func show_text(text: String) -> void:
	visible = text != ""
	_text.text = text
