extends Node
## The game server's entry point:
## [code]godot --headless --path game res://server/main.tscn[/code].

const GameTime := preload("res://shared/game_time.gd")
const Options := preload("res://util/options.gd")
const Net := preload("res://net/net.gd")
const Protocol := preload("res://net/protocol.gd")
const Server := preload("res://server/server.gd")


func _ready() -> void:
	Engine.physics_ticks_per_second = GameTime.TICK_RATE
	# The server draws nothing, so frames beyond one per tick only burn CPU.
	Engine.max_fps = GameTime.TICK_RATE
	var options := Options.new(Options.read())
	var server := Server.new()
	server.net = Net.add_to(self)
	server.exit_when_empty = options.exit_when_empty
	add_child(server)
	# PORT is what cloud hosts set.
	var port := options.port if options.port else int(OS.get_environment("PORT"))
	var err := server.start(port if port > 0 else Protocol.GAME_PORT,
			options.bind if options.bind else Server.DEFAULT_BIND)
	if err != OK:
		push_error("server failed to start: %s" % error_string(err))
		get_tree().quit(1)
