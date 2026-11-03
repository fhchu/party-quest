extends Node
## Entry point: runs the game server with [code]-- --server[/code] or in a
## dedicated_server export, otherwise the client.

const Args := preload("res://util/args.gd")
const Net := preload("res://net/net.gd")
const Protocol := preload("res://net/protocol.gd")
const Server := preload("res://server/server.gd")
const Client := preload("res://client/client.gd")


func _ready() -> void:
	Engine.physics_ticks_per_second = Protocol.TICK_RATE
	var args := Args.parse()

	# RPCs only route if both sides have Net at the same node path.
	var net := Net.new()
	net.name = "Net"
	add_child(net)

	if args.has("server") or OS.has_feature("dedicated_server"):
		Engine.max_fps = Protocol.TICK_RATE
		var server := Server.new()
		server.net = net
		add_child(server)
		var port := int(args.get("port", OS.get_environment("PORT")))
		var err := server.start(port if port > 0 else Protocol.GAME_PORT,
				args.get("bind", "127.0.0.1"))
		if err != OK:
			push_error("server failed to start: %s" % error_string(err))
			get_tree().quit(1)
	else:
		var client := Client.new()
		client.net = net
		client.args = args
		add_child(client)
