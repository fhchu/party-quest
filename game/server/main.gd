extends Node
## The game server's entry point:
## [code]godot --headless --path game res://server/main.tscn[/code].

const Net := preload("res://net/net.gd")
const Server := preload("res://server/server.gd")


func _ready() -> void:
	Engine.physics_ticks_per_second = GameTime.TICK_RATE
	# The server draws nothing, so frames beyond one per tick only burn CPU.
	Engine.max_fps = GameTime.TICK_RATE
	# The server polls the network itself, right before each tick.
	get_tree().set_multiplayer_poll_enabled(false)
	var server := Server.new()
	server.net = Net.add_to(self)
	add_child(server)
	var err := server.start()
	if err != OK:
		push_error("server failed to start: %s" % error_string(err))
		get_tree().quit(1)
