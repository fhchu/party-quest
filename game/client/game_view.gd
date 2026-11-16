extends RefCounted
## Everything the screen shows: the world to draw, and what the lobby UI and
## the center notice say, already worked out. ClientState builds it each
## frame; GameRenderer only reads it, so the gallery and tests can build one
## by hand without a network.

const Snapshot := preload("res://net/snapshot.gd")
const GameView := preload("res://client/game_view.gd")

# PLACEHOLDER (design): the wording.
const CONNECTING_TEXT := "Connecting..."
const RECONNECTING_TEXT := "Attempting to reconnect..."
# Must match noBrotliText in relay/static.go, so players get one message
# whichever check fails.
const UNSUPPORTED_BROWSER_TEXT := (
		"Your browser is incompatible. Try using an updated version of Google Chrome.")
const WON_TEXT := "Victory"
const LOST_TEXT := "Defeat"
const READY_TEXT := "ready"
const NOT_READY_TEXT := "not ready"
const SPECTATING_TEXT := "spectating"
## PLACEHOLDER (design): how long without any input before the key prompts
## come back. Untuned.
const PROMPT_IDLE_SEC := 5.0

## The world to draw; null before the first snapshot.
var view: Snapshot
## Your seat; 0 before the server names it.
var my_id := 0
## In town with someone not ready, so its door is shut and says why.
var waiting_for_ready := false
## Whether the lobby UI shows: from the first lobby state until turned away.
var in_lobby := false
## The line in the middle of the screen; empty for none.
var notice := ""
## Both groups of key prompts show and hide together.
var show_prompts := false
## Empty until lobbies have codes.
var lobby_code := ""
## The run's time left; empty outside a run.
var timer_text := ""
## One per occupied seat.
var cards: Array[Card] = []


## A screen that shows only [param text], in the middle.
static func only_notice(text: String) -> GameView:
	var out := GameView.new()
	out.notice = text
	return out


## Seat [param id]'s card, or null for an empty seat.
func card(id: int) -> Card:
	for c in cards:
		if c.id == id:
			return c
	return null


## One seat in the party bar.
class Card:
	var id := 0
	## Under the name: ready or not, spectating, or empty.
	var status_text := ""
	var health := 0
	var max_health := 0
	## Its bar is green.
	var ready := false
	## Its icon is dimmed under "d/c".
	var disconnected := false
