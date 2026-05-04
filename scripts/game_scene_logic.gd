extends Node

# Main logic for the game.tscn scene.
# This script can interact with the GameController autoload globally (e.g., GameController.some_method())
# and manage the child nodes of game.tscn.
const scr_debug : bool = false
var debug 

func _ready():
	debug = scr_debug or GameController.sys_debug
	if debug: print("game.tscn main logic ready.")
	var reset_button = get_node_or_null("CanvasLayer/Button")
	if reset_button:
		reset_button.pressed.connect(_on_reset_button_pressed)

func _on_reset_button_pressed() -> void:
	# Ensure tree is unpaused before tearing down
	get_tree().paused = false

	# Kill any active dialogue balloons
	for balloon in get_tree().get_nodes_in_group("dialogue_balloon"):
		balloon.queue_free()
	var dialog_system = get_node_or_null("/root/DialogSystem")
	if dialog_system:
		dialog_system.current_character_id = ""

	# Stop any running cutscene and clear movement state
	var cutscene_manager = get_node_or_null("/root/CutsceneManager")
	if cutscene_manager:
		cutscene_manager.cleanup_active_cutscene()
		cutscene_manager.active_movements.clear()
		cutscene_manager.movement_queue.clear()

	GameState.start_new_game()
