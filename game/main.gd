extends Node
## Entry point: runs the game server with [code]-- --server[/code] or in a
## dedicated_server export, otherwise the client.

const Options := preload("res://util/options.gd")
const Net := preload("res://net/net.gd")
const Protocol := preload("res://net/protocol.gd")
const Server := preload("res://server/server.gd")
const Client := preload("res://client/client.gd")


func _ready() -> void:
	Engine.physics_ticks_per_second = Protocol.TICK_RATE
	var options := Options.new(Options.read())

	# RPCs only route if both sides have Net at the same node path.
	var net := Net.new()
	net.name = "Net"
	add_child(net)

	if options.server or OS.has_feature("dedicated_server"):
		# The server draws nothing, so frames beyond one per tick only burn CPU.
		Engine.max_fps = Protocol.TICK_RATE
		var server := Server.new()
		server.net = net
		server.exit_when_empty = options.exit_when_empty
		server.dev = options.dev
		add_child(server)
		# PORT is what cloud hosts set.
		var port := options.port if options.port else int(OS.get_environment("PORT"))
		var err := server.start(port if port > 0 else Protocol.GAME_PORT,
				options.bind if options.bind else Server.DEFAULT_BIND)
		if err != OK:
			push_error("server failed to start: %s" % error_string(err))
			get_tree().quit(1)
	else:
		var client := Client.new()
		client.net = net
		client.options = options
		add_child(client)
