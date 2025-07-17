extends Control

# Info
@export_group("Settings")
@export_dir var travel_to_scene: String
@export var testing_locally = false

@onready var main_menu = $main
@onready var searching_text = $main/searching_text
@onready var game_list = $main/ScrollContainer/list

@onready var room_menu = $room
@onready var room_list = $room/room

@onready var host_menu = $host

@onready var join_menu = $join
@onready var error_text = $error_text
@onready var error_animator = $error_text/AnimationPlayer

@onready var settings_menu = $settings
@onready var game_name = $settings/game_name
@onready var max_players = $settings/max_players
@onready var time = $settings/time
@onready var start_button = $host/start_button

var cache = "user://connected_players.dat"
var peer = ENetMultiplayerPeer.new()
var udp_listener = UDPServer.new()  # Listens for broadcasts
var udp_sender = PacketPeerUDP.new()  # Sends broadcasts
var is_host = false
var connected_players = []
var saved_games = {}
var server_port = 0  # Store the server's port
var data : Dictionary = {}

var desk_address = "255.255.255.255"

# Server Management
func _ready():
	# Lobby set-up
	remove_all_game_buttons()
	
	# Server browser list set-up
	if testing_locally:
		desk_address = "127.0.0.1"
	else:
		desk_address = "255.255.255.255"
	udp_listener.listen(8989)  # Listen for incoming broadcasts on port 8989
	udp_sender.set_broadcast_enabled(true)  # Enable UDP broadcast
	
	# Signals set-up
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(_delta):
	if is_host:
		var packet_data = data.duplicate()
		packet_data["game_name"] = game_name.text
		packet_data["max_players"] = max_players.value
		packet_data["players_amount"] = connected_players.size()
		var packet = var_to_bytes(packet_data)
		udp_sender.set_dest_address(desk_address, 8989)  # Set target address and port
		udp_sender.put_packet(packet)  # Now send the packet
		
	udp_listener.poll()
		
	if udp_listener.is_connection_available() and not is_host:
		var peer = udp_listener.take_connection()
		var ip = peer.get_packet_ip()
		var data = bytes_to_var(peer.get_packet())
		if data.has("port"):
			var port = data.port
			var game_info = ip + ":" + str(port)  # Store IP:Port format
			
			if not saved_games.has(game_info):
				add_game_button(data, ip)
				saved_games[game_info] = 2
			else:
				update_game_button(data, ip)
				saved_games[game_info] = 2
				
	if game_list.get_child_count() > 0:
		searching_text.hide()
	else:
		searching_text.show()

# Signals for Server and Players
# Runs on other players once with the new player id
# and runs on the new player with the other players ids
func _on_player_connected(id):
	if multiplayer.is_server():
		test_if_allowed_on_server(id)
	
	connected_players.append(id)
	add_room_player(id)
	
	if multiplayer.is_server():
		start_button.show()

func test_if_allowed_on_server(id):
	if connected_players.size() == max_players.value:
		rpc_id(id, "process_kick", "Error: Full Room", id)

@rpc("authority", "call_remote", "reliable", 0)
func process_kick(reason, my_id):
	show_join_error(reason)
	rpc_id(1, "processed_kick", my_id)

@rpc("any_peer", "call_remote", "reliable", 0)
func processed_kick(id):
	multiplayer.multiplayer_peer.disconnect_peer(id)

func _on_player_disconnected(id):
	connected_players.erase(id)
	remove_room_player(id)
	
	if multiplayer.is_server():
		if connected_players.size() < 2:
			start_button.hide()

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	remove_all_room_players()
	connected_players.clear()
	show_main_menu()

# Lobby & Players Management
func _on_game_pressed(ip: String, port: int) -> void:
	show_join_menu()
	join(ip, port)

func _on_host_button_pressed():
	show_host_menu()
	host()

func _on_settings_button_pressed() -> void:
	show_settings_menu()

func _on_start_button_pressed():
	start()

func show_join_error(text):
	show_main_menu()
	error_text.text = text
	if text == "Error: Full Room":
		error_animator.play("full")
	elif text == "Error: Invalid IP Address":
		error_animator.play("invalid")

func _on_back_button_pressed():
	leave()
	show_main_menu()

func _on_settings_back_button_pressed() -> void:
	show_host_menu()

func _on_timer_timeout() -> void:
	for key in saved_games.keys():
		saved_games[key] -= 1
		if saved_games[key] <= 0:
			remove_game_button(key)
			saved_games.erase(key)

# Server Functions
func host():
	server_port = find_open_port(5000, 6)  # Find an available port
	if server_port != -1:
		peer.create_server(server_port, 6)
		multiplayer.multiplayer_peer = peer
		is_host = true
		data["port"] = server_port
		connected_players.append(1)
		add_room_player(1)
		show_host_menu()

func find_open_port(start_port: int, max_attempts: int) -> int:
	for i in range(max_attempts):
		var port = start_port + i
		if is_port_available(port):
			return port
	return -1  # No open ports found

func is_port_available(port: int) -> bool:
	var test_peer = ENetMultiplayerPeer.new()
	var result = test_peer.create_server(port, 1)
	if result == OK:
		test_peer.close()
		return true  # Port is free
	return false  # Port is in use

func join(ip: String, port: int):
	peer.create_client(ip, port)
	multiplayer.multiplayer_peer = peer
	connected_players.append(multiplayer.get_unique_id())
	add_room_player(multiplayer.get_unique_id())

# Lobby & Player Functions
func add_game_button(data: Dictionary, ip: String):
	# Add a game button to the list
	var game_button = load("res://addons/lan_multiplayer/scenes/game_button.tscn").instantiate()
	game_button.get_node("max_players").text = str(data.players_amount) + "/" + str(int(data.max_players))
	game_button.get_node("game_name").text = data.game_name
	game_button.ip = ip
	game_button.port = data.port
	game_button.info = ip + ":" + str(data.port)
	game_button.chose.connect(_on_game_pressed)
	game_list.add_child(game_button)

func update_game_button(data: Dictionary, ip: String):
	for game_button in game_list.get_children():
		if game_button.info == (ip + ":" + str(data.port)):
			game_button.get_node("max_players").text = str(data.players_amount) + "/" + str(int(data.max_players))
			game_button.get_node("game_name").text = data.game_name

func remove_game_button(info: String):
	for game_button in game_list.get_children():
		if game_button.info == info:
			game_button.queue_free()

func remove_all_game_buttons():
	for game_button in game_list.get_children():
		game_button.queue_free()

func add_room_player(id):
	var room_player = preload("res://addons/lan_multiplayer/scenes/room_player.tscn").instantiate()
	room_player.name = str(id)
	room_list.add_child(room_player)

func remove_room_player(id):
	if room_list.get_node_or_null(str(id)):
		room_list.get_node(str(id)).queue_free()

func remove_all_room_players():
	for i in connected_players.size():
		remove_room_player(connected_players[i])

func start():
	rpc("start_scene", connected_players, $settings/time.value)

func save(connected_players, time):
	var file = FileAccess.open(cache, FileAccess.WRITE)
	file.store_var(connected_players)
	file.store_var(time)

@rpc("authority", "call_local", "reliable", 0)
func start_scene(connected_players, time):
	save(connected_players, time)
	get_tree().change_scene_to_file(travel_to_scene)

func leave():
	multiplayer.multiplayer_peer.close()
	is_host = false
	remove_all_room_players()
	connected_players.clear()

# Visual Functions
func hide_all_menus():
	main_menu.hide()
	searching_text.show()
	
	room_menu.hide()
	
	host_menu.hide()
	
	join_menu.hide()
	settings_menu.hide()

func show_main_menu():
	hide_all_menus()
	main_menu.show()

func show_main_menu_with_list():
	show_main_menu()
	searching_text.hide()

func show_host_menu():
	hide_all_menus()
	room_menu.show()
	host_menu.show()
	
	searching_text.hide()

func show_host_menu_with_start_button():
	show_host_menu()
	start_button.show()

func show_join_menu():
	hide_all_menus()
	room_menu.show()
	join_menu.show()

func show_settings_menu():
	hide_all_menus()
	settings_menu.show()
