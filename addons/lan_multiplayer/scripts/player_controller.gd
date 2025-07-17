extends Node

#Functions for you: func_and_sync()

@export_group("Settings")
@export var camera_path: NodePath
@export var property_syncs: Array[PropertySync]
@export var function_syncs: Array[FunctionSync]

#AUTHORITY AND CONNECTION CONTROL
func _enter_tree():
	get_parent().set_multiplayer_authority(get_parent().name.to_int())

func _ready():
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	set_process(false)
	
	# Wait to continue...

func _continue_ready():
	if not get_parent().is_multiplayer_authority():
		for i in property_syncs.size():
			var node = get_node(property_syncs[i].node)
			if node.has_method("_process"):
				node.call_deferred("set_process", false)
			if node.has_method("_physics_process"):
				node.call_deferred("set_physics_process", false)
		for i in function_syncs.size():
			var node = get_node(function_syncs[i].node)
			if node.has_method("_process"):
				node.call_deferred("set_process", false)
			if node.has_method("_physics_process"):
				node.call_deferred("set_physics_process", false)
		if get_node_or_null(camera_path):
			get_node_or_null(camera_path).queue_free()
			
	set_process(true)

func _on_server_disconnected():
	set_process(false)

#PROPERTIES SYNC
func _process(_delta):
	if get_parent().is_multiplayer_authority():
		for property_sync in property_syncs:
			for property in property_sync.properties:
				rpc("unreliable", property_sync.node, property, get_node(property_sync.node)[property])
		var camera = get_node_or_null(camera_path)
		if camera:
			if not camera.enabled:
				camera.enabled = true

@rpc("any_peer", "call_remote", "unreliable", 1)
func unreliable(node_path, property, value):
	get_node(node_path)[property] = value

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
