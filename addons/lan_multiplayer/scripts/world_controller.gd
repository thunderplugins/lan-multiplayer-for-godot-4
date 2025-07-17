extends CanvasLayer

#Functions for you: show_leaderboard(), hide_leaderboard(), 
#show_timer(), hide_timer(), is_host(), func_and_sync().

@export_group("Settings")
@export var player_scene: PackedScene
@export var spawn_path: NodePath
@export var spawn_position: Vector2
@export var function_syncs: Array[FunctionSync]

var players_connected = false
var connected_players_amount = 0

var cache = "user://connected_players.dat"
var connected_players = []
var time = 0

#Server & Players
signal all_players_joined ## Server and players receive this signal.
signal time_ended ## Server and players receive this signal.

#Players
signal host_left ## Players receive this signal.

func _enter_tree():
	#AUTHORITY
	set_multiplayer_authority(multiplayer.get_unique_id())

func _ready():
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	start()
	
	#AUTHORITY
	set_multiplayer_authority(multiplayer.get_unique_id())
	
	# Wait to continue...

@rpc("any_peer", "call_local", "reliable", 0)
func _continue_ready():
	#TIMER
	if time != 0:
		$timer.text = str(time) + "s"
		$timer/Timer.start()
	
	if not is_multiplayer_authority():
		for i in function_syncs.size():
			var node = get_node(function_syncs[i].node)
			if node.has_method("_process"):
				node.call_deferred("set_process", false)
			if node.has_method("_physics_process"):
				node.call_deferred("set_physics_process", false)
	else:
		for i in get_node(spawn_path).get_children():
			if i.get_node_or_null("player_controller"):
				i.get_node("player_controller")._continue_ready()
				
	set_process(false)
	call_deferred("emit_signal", "all_players_joined")

func _on_player_disconnected(id):
	connected_players.erase(id)
	remove_player(id)
	remove_room_player(id)

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	remove_all_players()
	remove_all_room_players()
	emit_signal("host_left")

#SERVER TOOLS
func is_host():
	return multiplayer.is_server()

#PLAYER TOOLS
func _process(_delta: float) -> void:
	if multiplayer.is_server():
		if connected_players_amount == connected_players.size():
			rpc("_continue_ready")
		else:
			rpc("check_processing")
			# Host's checking if clients have their players initialized

@rpc("any_peer", "call_local", "reliable", 0)
func check_processing():
	if !players_connected:
		var x = 0
		for i in function_syncs.size():
			if get_node(function_syncs[i].node).players_connected:
				x += 1
		if function_syncs.size() == x:
			players_connected = true
			rpc_id(1, "processed")
			# A client's/host's saying that has their players initialized

@rpc("any_peer", "call_local", "reliable", 0)
func processed():
	connected_players_amount += 1

	for i in function_syncs.size():
		if get_node(function_syncs[i].node).players_conneced:
			rpc("processed")
		if get_node(function_syncs[i].node).has_method("_physics_process"):
			get_node(function_syncs[i].node).call_deferred("set_physics_process", false)
	call_deferred("emit_signal", "all_players_joined")

func start():
	if FileAccess.file_exists(cache):
		var file = FileAccess.open(cache, FileAccess.READ)
		connected_players = file.get_var()
		time = file.get_var() * 60
	for id in connected_players.size():
		add_player(connected_players[id])
		add_room_player(connected_players[id])

func add_player(id):
	var player = player_scene.instantiate()
	player.name = str(id)
	if get_node(spawn_path).has_method("get_position"):
		player.position = spawn_position
	host_left.connect(player.get_node("player_controller")._on_server_disconnected)
	get_node(spawn_path).call_deferred("add_child", player)

func remove_all_players():
	for id in connected_players.size():
		remove_player(connected_players[id])

func remove_player(id):
	if get_node(spawn_path).get_node_or_null(str(id)):
		get_node(spawn_path).get_node(str(id)).queue_free()

#SYNC FUNCTIONS

#FUNCTIONS SYNC
func func_and_sync(function_name, v1=null, v2=null, v3=null, v4=null, v5=null, v6=null, v7=null, v8=null):
	if get_parent().is_multiplayer_authority():
		rpc("function", function_name, v1, v2, v3, v4, v5, v6, v7, v8)

@rpc("any_peer", "call_local", "reliable", 0)
func function(function_name, v1=null, v2=null, v3=null, v4=null, v5=null, v6=null, v7=null, v8=null):
	var array = []
	for i in [v1, v2, v3, v4, v5, v6, v7, v8]:
		if i != null:
			array.append(i)
	for i in function_syncs.size():
		for j in function_syncs[i].functions.size():
			if function_syncs[i].functions[j] == function_name:
				get_node(function_syncs[i].node).callv(function_name, array)

#LEADERBOARD
func show_leaderboard():
	$leaderboard.show()

func hide_leaderboard():
	$leaderboard.hide()

func add_room_player(id):
	var room_player = preload("res://addons/lan_multiplayer/scenes/room_player.tscn").instantiate()
	room_player.name = str(id)
	$leaderboard/room.add_child(room_player)

func remove_room_player(id):
	if $leaderboard/room.get_node_or_null(str(id)):
		$leaderboard/room.get_node(str(id)).queue_free()

func remove_all_room_players():
	for i in connected_players.size():
		remove_room_player(connected_players[i])

#TIMER
func show_timer():
	$timer.show()

func hide_timer():
	$timer.hide()

func _on_timer_timeout():
	time-=1
	$timer.text = str(time) + "s"
	if time<=0:
		$timer/Timer.stop()
		emit_signal("time_ended")
		$timer.hide()
