extends Control
## In-game UI while in the lobby: the party bar along the bottom, the key
## prompts above it, your gold top left, and top right the run timer with
## your fps and ping under it. Each keeps its place whether shown or not.
## Drawn from a GameView only.

const GameView := preload("res://client/game_view.gd")
const PlayerCard := preload("res://client/ui/player_card.gd")
const KeyPrompts := preload("res://client/ui/key_prompts.gd")
const TouchControls := preload("res://client/ui/touch_controls.gd")

@onready var _gold: Label = %Gold
@onready var _timer: Label = %Timer
@onready var _fps: Label = %Fps
@onready var _ping: Label = %Ping
@onready var _prompts: KeyPrompts = %Prompts
@onready var _touch_controls: TouchControls = %TouchControls
var _cards: Array[PlayerCard] = []


func _ready() -> void:
	_cards.assign(%PartyBar.get_children())


func show_state(view: GameView) -> void:
	visible = view.in_lobby
	if not visible:
		return
	_gold.text = view.gold_text
	_timer.text = view.timer_text
	_fps.text = view.fps_text
	_ping.text = view.ping_text
	var prompts := view.prompts
	_prompts.show_prompts(
			prompts.show_move_keys, prompts.action_prompt == GameView.ActionPrompt.KEYS)
	_touch_controls.show_buttons(prompts.action_prompt == GameView.ActionPrompt.BUTTONS)
	# The attack button uses item slot 1.
	var first: GameView.ItemSlot = null if view.item_slots.is_empty() else view.item_slots[0]
	_touch_controls.show_attack_icon(first.icon if first else null)
	for i in _cards.size():
		var id := i + 1
		_cards[i].show_card(id, view.card(id))
