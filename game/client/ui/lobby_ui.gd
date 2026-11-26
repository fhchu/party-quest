extends Control
## In-game UI while in the lobby: the party bar along the bottom, the key
## prompts above it, your gold top left, and top right the run timer with
## your fps and ping under it. Each keeps its place whether shown or not.
## Drawn from a GameView only.

const GameView := preload("res://client/game_view.gd")
const PlayerCard := preload("res://client/ui/player_card.gd")
const KeyPrompts := preload("res://client/ui/key_prompts.gd")
const TouchControls := preload("res://client/ui/touch_controls.gd")

# What the action keys say over the level select.
static var _select_caption := _caption(GameView.SELECT_TEXT)
static var _back_caption := _caption(GameView.BACK_TEXT)

@onready var _gold: Label = %Gold
@onready var _timer: Label = %Timer
@onready var _fps: Label = %Fps
@onready var _ping: Label = %Ping
@onready var _prompts: KeyPrompts = %Prompts
@onready var _touch_controls: TouchControls = %TouchControls
var _cards: Array[PlayerCard] = []


static func _caption(text: String) -> GameView.ItemSlot:
	var out := GameView.ItemSlot.new()
	out.display_name = text
	return out


func _ready() -> void:
	_cards.assign(%PartyBar.get_children())
	var party_bar: Control = %PartyBar
	party_bar.item_rect_changed.connect(_put_back_over_party_bar)
	_put_back_over_party_bar()


func show_state(view: GameView) -> void:
	visible = view.in_lobby
	if not visible:
		return
	_gold.text = view.gold_text
	_timer.text = view.timer_text
	_fps.text = view.fps_text
	_ping.text = view.ping_text
	var prompts := view.prompts
	var slot_1 := view.item_slot(0)
	var slot_2 := view.item_slot(1)
	if view.level_select_open:
		slot_1 = _select_caption
		slot_2 = _back_caption
	_prompts.show_prompts(prompts.show_move_keys,
			prompts.action_prompt == GameView.ActionPrompt.KEYS, slot_1, slot_2)
	_touch_controls.show_buttons(prompts.action_prompt == GameView.ActionPrompt.BUTTONS,
			slot_1, slot_2, view.level_select_open)
	for i in _cards.size():
		var id := i + 1
		_cards[i].show_card(id, view.card(id))


## Touch Back sits in the bottom-left corner, just above the party bar.
func _put_back_over_party_bar() -> void:
	_touch_controls.set_back_floor((%PartyBar as Control).get_global_rect().position.y)
