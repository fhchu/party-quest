extends Node
## The client's entry point and the project's main scene. The game server
## starts from server/main.tscn.

const Options := preload("res://util/options.gd")
const Net := preload("res://net/net.gd")
const Protocol := preload("res://net/protocol.gd")
const Client := preload("res://client/client.gd")


func _ready() -> void:
	Engine.physics_ticks_per_second = Protocol.TICK_RATE
	var client := Client.new()
	client.net = Net.add_to(self)
	client.options = Options.new(Options.read())
	add_child(client)
