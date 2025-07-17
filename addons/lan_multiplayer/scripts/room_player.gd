extends Label

var player_name = "Player" # Substitute with Global/File variable.

func _ready() -> void:
	if get_parent().get_parent().name == "leaderboard":
		set_process(false)
		$player_controller.func_and_sync("update_name", player_name)

func _process(_delta: float) -> void:
	if $player_controller.func_and_sync("update_name", player_name):
		set_process(false)

func update_name(string: String) -> void:
	text = string
