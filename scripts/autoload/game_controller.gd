extends Node

# Game Controller acts as the central coordinator for all game systems
# It initializes and connects all other systems

#inventory item use signals
signal turn_completed
signal day_advanced
signal location_changed(old_location, new_location)

const sys_debug : bool = false
const scr_debug : bool = true
var debug 
var active_scene
var player : CharacterBody2D

# Current scene tracking
var current_scene_node
var current_scene_path = ""
var current_location = ""

# System references
var inventory_panel
var inventory_panel_scene
var inventory_system
var relationship_system
var dialog_system
var quest_system
var save_load_system
var notification_system

# Quest system
var quest_panel
var quest_panel_scene

# UI references
var pause_menu
var pause_menu_scene # Will be loaded in _ready

#time tracking
var current_turn = 0
var current_day = 1
var turns_per_day = 8

# Dictionary to store unlocked areas
# Key: area_id, Value: true
var unlocked_areas = {}

# Dictionary to store acquired knowledge
# Key: knowledge_id, Value: true
var knowledge_base = {}

func _ready():
	debug = sys_debug or scr_debug
	if debug: DebugManager.print_debug_auto(self, "Game Controller initialized")
	quest_system = QuestSystem
	var time_system = get_node_or_null("/root/TimeSystem")
	if time_system:
		GameState.safe_connect(time_system, "day_changed", Callable(self, "_on_day_changed"))
		GameState.safe_connect(time_system, "time_of_day_changed", Callable(self, "_on_time_of_day_changed"))
		if debug: DebugManager.print_debug_auto(self, "Connected to TimeSystem signals")
	# Get reference to the current scene node
	current_scene_node = get_node_or_null("/root/Game/CurrentScene")
	if not current_scene_node:
		var root = get_tree().root
		current_scene_node = root.get_child(root.get_child_count() - 1)
		if debug: DebugManager.print_debug_auto(self, "Using root as current scene container")

	# Get references to other systems
	# These should be added as autoloads in the project settings
	inventory_system = InventorySystem
#	relationship_system = RelationshipSystem
	dialog_system = DialogSystem
	save_load_system = SaveLoadSystem
	notification_system = get_node_or_null("/root/NotificationSystem")

	_ensure_input_actions()

	# Try to preload the pause menu scene
	var pause_path = Paths.get_ui("pause_menu")
	if ResourceLoader.exists(pause_path):
		pause_menu_scene = load(pause_path)

	# Try to preload the inventory panel scene
	var inventory_path = Paths.get_ui("inventory_panel")
	if ResourceLoader.exists(inventory_path):
		inventory_panel_scene = load(inventory_path)
	else:
		if debug: DebugManager.print_debug_auto(self, "Could not find inventory_panel.tscn - will need to create it")

	# Try to preload the quest panel scene
	var quest_path = Paths.get_ui("quest_panel")
	if ResourceLoader.exists(quest_path):
		quest_panel_scene = load(quest_path)
	else:
		if debug: DebugManager.print_debug_auto(self, "Could not find quest_panel.tscn - will need to create it")

	# check for "toggle_quest_journal" input
#	if InputMap.has_action("toggle_quest_panel"):
#		InputMap.add_action("toggle_quest_panel")
#		event.keycode = KEY_J
#		InputMap.action_add_event("toggle_quest_panel", e#Avent)
#		if debug: DebugManager.print_debug_auto(self, "Added 'toggle_quest_panel' action with J key")
	GameState.get_current_npcs()
	# By default, go to main menu
	call_deferred("change_scene", Paths.get_scene("main_menu"))
	player = GameState.get_player()

func _on_day_changed(old_day, new_day):
	if debug: DebugManager.print_debug_auto(self, str("Day changed from %d to %d" % [old_day) + str(new_day]))
	day_advanced.emit()

	# Additional day change logic here

func _on_time_of_day_changed(old_time, new_time):
	if debug: DebugManager.print_debug_auto(self, "Time of day changed")
	turn_completed.emit()


# Modified _unhandled_input function for game_controller.gd
func _ensure_input_actions():
	# Define all required actions with default keys
	var required_actions = {
		"interact": [KEY_E, KEY_SPACE],
		"ui_up": [KEY_W, KEY_UP],
		"ui_down": [KEY_S, KEY_DOWN],
		"ui_left": [KEY_A, KEY_LEFT],
		"ui_right": [KEY_D, KEY_RIGHT],
		"toggle_inventory": [KEY_I],
		"toggle_quest_journal": [KEY_J],
		"pause": [KEY_ESCAPE]
	}

	# Special actions with modifiers
	var save_action_keys = [KEY_S]
	var save_requires_ctrl = true

	# Process standard actions
	for action in required_actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key in required_actions[action]:
				var event = InputEventKey.new()
				event.keycode = key
				InputMap.action_add_event(action, event)
			DebugManager.print_debug_auto(self, "Added action: " + action)

	# Process save_game action with Ctrl modifier
	if not InputMap.has_action("save_game"):
		InputMap.add_action("save_game")
		for key in save_action_keys:
			var event = InputEventKey.new()
			event.keycode = key
			event.ctrl_pressed = save_requires_ctrl
			InputMap.action_add_event("save_game", event)
		DebugManager.print_debug_auto(self, "Added action: save_game (Ctrl+S)")

func _unhandled_input(event):
	# Save game with Ctrl+S
	if InputMap.has_action("save_game") and event.is_action_pressed("save_game"):
		if debug: DebugManager.print_debug_auto(self, "Save game action detected - quick saving")
		quick_save()
		get_viewport().set_input_as_handled()
		return

	# UI Cancel (usually Escape key)
	if event.is_action_pressed("ui_cancel"):
		if debug: DebugManager.print_debug_auto(self, "UI cancel action detected - checking for open panels")

		# Check for any open panels in priority order
		var panel_closed = false

		# 1. First check if any inventory panel is open
		if inventory_panel and inventory_panel.visible:
			if debug: DebugManager.print_debug_auto(self, "Inventory panel is open, closing it")
			inventory_panel.visible = false
			get_tree().paused = false
			panel_closed = true
			get_viewport().set_input_as_handled()

		# 2. Check for quest panel
		quest_panel = get_node_or_null("/root/QuestPanel")
		if not panel_closed and quest_panel and quest_panel.visible:
			if debug: DebugManager.print_debug_auto(self, "Quest panel is open, closing it")
			quest_panel.visible = false
			get_tree().paused = false
			panel_closed = true
			get_viewport().set_input_as_handled()

		# 3. Also check canvas layers for UI panels
		if not panel_closed:
			var ui_layers = get_tree().get_nodes_in_group("ui_layer")
			for layer in ui_layers:
				# Check for quest panel in this layer
				var quest_panel_in_layer = layer.get_node_or_null("QuestPanel")
				if quest_panel_in_layer and quest_panel_in_layer.visible:
					if debug: DebugManager.print_debug_auto(self, "Quest panel found in UI layer, closing it")
					quest_panel_in_layer.visible = false
					get_tree().paused = false
					panel_closed = true
					get_viewport().set_input_as_handled()
					break

				# Check for other panels that might be open
				for child in layer.get_children():
					if child is Control and child.visible and child.name.ends_with("Panel"):
						if debug: DebugManager.print_debug_auto(self, "UI panel found: " + child.name + ", closing it")
						child.visible = false
						get_tree().paused = false
						panel_closed = true
						get_viewport().set_input_as_handled()
						break

				if panel_closed:
					break

		# 4. Finally, if no panels were closed, toggle the pause menu
		if not panel_closed:
			if debug: DebugManager.print_debug_auto(self, "No panels to close, toggling pause menu")
			toggle_pause_menu()
			get_viewport().set_input_as_handled()

	# Toggle inventory
	if InputMap.has_action("toggle_inventory") and event.is_action_pressed("toggle_inventory"):
		if debug: DebugManager.print_debug_auto(self, "Toggle inventory action detected")
		toggle_inventory()
		get_viewport().set_input_as_handled()


	# Toggle quest journal
	if InputMap.has_action("toggle_quest_journal") and event.is_action_pressed("toggle_quest_journal"):
		if debug: DebugManager.print_debug_auto(self, "Toggle quest journal action detected")
		toggle_quest_panel()
		get_viewport().set_input_as_handled()

	if event is InputEventKey and event.keycode == KEY_K and event.pressed and not event.echo:
		debug_complete_quest_objective("intro_quest", "talk", "professor_moss")
		if debug: DebugManager.print_debug_auto(self, "DEBUG: Manually triggered professor_moss talk objective")


# Start a new game
func start_new_game():
	var game_state = get_node_or_null("/root/GameState")
	if game_state:
		game_state.start_new_game()

# Load a game
func load_game(slot):
	var game_state = get_node_or_null("/root/GameState")
	if game_state:
		game_state.load_game(slot)
	else:
		# Fallback to old method
		if save_load_system:
			save_load_system.load_game(slot)
	player = get_tree().get_first_node_in_group("player")


# Save a game
func save_game(slot):
	var game_state = get_node_or_null("/root/GameState")
	if game_state:
		game_state.save_game(slot)
	else:
		# Fallback to old method
		if save_load_system:
			save_load_system.save_game(slot)

	
func quick_save():
	save_game(0)

	# Display a notification
	if notification_system and notification_system.has_method("show_notification"):
		notification_system.show_notification("Game saved to Quick Save slot")


func toggle_pause_menu():
	# Skip if dialog is active - use our new sanity-checked method
	if dialog_system and dialog_system.has_method("is_dialog_active") and dialog_system.is_dialog_active():
		if debug: DebugManager.print_debug_auto(self, "Dialog active, not pausing")
		return

	# Debug info to check current path
	if debug: DebugManager.print_debug_auto(self, "Current scene path: " + current_scene_path)

	# Check if we're in a gameplay scene (not the main menu)
	# We need to be more careful with how we determine this
	var is_main_menu = current_scene_path.find("main_menu") != -1

	# Extra check - see if we can find player in the scene
	player = get_tree().get_first_node_in_group("player")

	# Even if current_scene_path says we're in main menu, if there's a player, we're in gameplay
	if is_main_menu and player:
		is_main_menu = false
		if debug: DebugManager.print_debug_auto(self, "Fixed scene detection - we're actually in gameplay")

	if is_main_menu:
		if debug: DebugManager.print_debug_auto(self, "In main menu, not pausing")
		return

	if pause_menu:
		# Menu exists, just toggle visibility
		pause_menu.visible = !pause_menu.visible
		get_tree().paused = pause_menu.visible
		if debug: DebugManager.print_debug_auto(self, "Toggling pause menu visibility: " + str(pause_menu.visible))
	else:
		# Create the pause menu
		if pause_menu_scene:
			if debug: DebugManager.print_debug_auto(self, "Creating pause menu")

			# Create a CanvasLayer for the pause menu to ensure it's on top
			var canvas = CanvasLayer.new()
			canvas.layer = 100  # High layer number to be on top
			canvas.add_to_group("ui_layer")
			get_tree().root.add_child(canvas)

			pause_menu = pause_menu_scene.instantiate()
			canvas.add_child(pause_menu)

			GameState.safe_connect(pause_menu, "resume_game", Callable(self, "_on_resume_game"))
			GameState.safe_connect(pause_menu, "save_game", Callable(self, "_on_save_game"))
			GameState.safe_connect(pause_menu, "load_game", Callable(self, "_on_load_game"))
			GameState.safe_connect(pause_menu, "quit_to_menu", Callable(self, "_on_quit_to_menu"))
			get_tree().paused = true
			if debug: DebugManager.print_debug_auto(self, "Pause menu created and game paused")
		else:
			if debug: DebugManager.print_debug_auto(self, "Pause menu scene not found or not loaded!")
			# Try to load it now
			if ResourceLoader.exists(Paths.get_ui("pause_menu")):
				pause_menu_scene = load(Paths.get_ui("pause_menu"))
				if debug: DebugManager.print_debug_auto(self, "Loaded pause menu scene, try pressing Escape again")
			else:
				if debug: DebugManager.print_debug_auto(self, "Could not find pause_menu.tscn")

func _on_resume_game():
	if pause_menu:
		pause_menu.visible = false
		get_tree().paused = false

func _on_save_game(slot):
	save_game(slot)
	if pause_menu:
		pause_menu.visible = false
		get_tree().paused = false

func _on_load_game(slot):
	load_game(slot)
	if pause_menu:
		pause_menu.visible = false
		get_tree().paused = false

func _on_quit_to_menu():
	if pause_menu:
		pause_menu.queue_free()
		pause_menu = null
		get_tree().paused = false
	change_scene(Paths.get_scene("main_menu"))


func change_scene(new_scene_path):
	if debug: DebugManager.print_debug_auto(self, "Changing scene to: " + new_scene_path)
	var current_scene = GameState.get_current_scene()

	var old_location = current_location
	var location_id = new_scene_path.get_file().get_basename()
	current_location = location_id

	# Show loading label if needed
	var loading_label
	if get_node_or_null("/root/Game"):
		loading_label = get_node_or_null("/root/Game/LoadingLabel")
	else:
		loading_label = null

	if loading_label:
		loading_label.visible = true

	# Using the main scene structure with a CurrentScene node
	if get_node_or_null("/root/Game/CurrentScene"):
		var current_scene_container = get_node("/root/Game/CurrentScene")

		# Free the current scene if it exists
		if current_scene_container.get_child_count() > 0:
			for child in current_scene_container.get_children():
				current_scene_container.remove_child(child)
				child.queue_free()

		# Load the new scene
		var scene_resource = load(new_scene_path)
		if scene_resource:
			var scene_instance = scene_resource.instantiate()
			current_scene_container.add_child(scene_instance)
			active_scene = scene_instance
			current_scene_path = new_scene_path
			if debug: DebugManager.print_debug_auto(self, "Scene changed to: " + new_scene_path)
			GameState.set_current_scene(scene_instance)
			if debug: DebugManager.print_debug_auto(self, "location_scene in scene_instance)" + str("location_scene" in scene_instance))
		else:
			if debug: DebugManager.print_debug_auto(self, "Failed to load scene: " + new_scene_path)
	else:
		# Use the standard Godot scene changing approach
		var error = get_tree().change_scene_to_file(new_scene_path)
		if error == OK:
			current_scene_path = new_scene_path
			if debug: DebugManager.print_debug_auto(self, "Scene changed to: " + new_scene_path)
		else:
			if debug: DebugManager.print_debug_auto(self, "Failed to load scene: " + new_scene_path + " Error code: " + str(error))

	# Hide loading label
	if loading_label:
		loading_label.visible = false

	# Notify about location change
	if old_location != current_location:
		location_changed.emit(old_location, current_location)

		# Notify quest system about the location
		quest_system = get_node_or_null("/root/QuestSystem")
		if quest_system and quest_system.has_method("on_location_entered"):
			quest_system.call_deferred("on_location_entered", current_location)

	var scene = GameState.get_current_scene()
	if "location_scene" in scene:
		player = GameState.get_player()
		if player:
			player.set_camera_limits()


	
# Enhanced scene change method that preserves player state and handles spawn points
func change_location(new_scene_path, spawn_point="default"):
	if debug: DebugManager.print_debug_auto(self, "DEBUG: Changing location to: " + new_scene_path + " with spawn point: " + spawn_point)

	# Save current player state if available
	var current_player = get_tree().get_first_node_in_group("player")
	var player_state = {}

	if current_player:
		var player_health
		if "health" in current_player:
			player_health = current_player.get("health")
		else:
			player_health= null
		var player_last_direction
		if "last_direction" in current_player:
			player_last_direction = current_player.get("last_direction")
		else:
			player_last_direction = null
		# Save core player properties
		player_state = {
			"position": current_player.position,
			"health": player_health,
			"last_direction": player_last_direction
		}

		if debug: DebugManager.print_debug_auto(self, "DEBUG: Saved player state: " + str(player_state))
	else:
		if debug: DebugManager.print_debug_auto(self, "DEBUG: No player found in current scene to save state")

	# Extract location name for debugging
	var location_name = new_scene_path.get_file().get_basename()
	if debug: DebugManager.print_debug_auto(self, "DEBUG: Transitioning to location: " + location_name)

	# Use basic scene change
	change_scene(new_scene_path)

	# Wait a frame to ensure scene is fully loaded
	if debug: DebugManager.print_debug_auto(self, "DEBUG: Waiting for scene to load fully...")
	await get_tree().process_frame
	if debug: DebugManager.print_debug_auto(self, "DEBUG: Scene processed, looking for player and spawn points")

	# Find the player in the new scene
	var new_player = get_tree().get_first_node_in_group("player")
	if not new_player:
		if debug: DebugManager.print_debug_auto(self, "DEBUG: ERROR: Could not find player in new scene!")
		return
	else:
		if debug: DebugManager.print_debug_auto(self, "DEBUG: Found new player at position: " + str(new_player.position))

	# Find spawn point in new scene
	if debug: DebugManager.print_debug_auto(self, "DEBUG: Looking for spawn point: " + spawn_point)
	var spawn_position = _find_spawn_point(spawn_point)
	if debug: DebugManager.print_debug_auto(self, "DEBUG: Spawn position result: " + str(spawn_position))

	# Apply saved player state
	if spawn_position != Vector2.ZERO:
		# Use spawn point if found and valid
		if debug: DebugManager.print_debug_auto(self, "DEBUG: Moving player to spawn position: " + str(spawn_position))
		new_player.global_position = spawn_position  # Using global_position instead of position
		if debug: DebugManager.print_debug_auto(self, "DEBUG: Player position after setting: " + str(new_player.global_position))
	elif not player_state.is_empty():
		# Transfer player properties
		if debug: DebugManager.print_debug_auto(self, "DEBUG: No spawn point found. Using saved player state to position player")
		new_player.position = player_state.position
		if debug: DebugManager.print_debug_auto(self, "DEBUG: Player position after setting from saved state: " + str(new_player.position))

		if player_state.last_direction != null:
			new_player.last_direction = player_state.last_direction
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Restored player direction: " + str(new_player.last_direction))

		if player_state.health != null and "health" in new_player:
			new_player.health = player_state.health
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Restored player health: " + str(new_player.health))
	else:
		if debug: DebugManager.print_debug_auto(self, "DEBUG: WARNING: No spawn point found and no player state to restore!")

	# Update game state
	var game_state = get_node_or_null("/root/GameState")
	if game_state:
		game_state.game_data.current_location = new_scene_path.get_file().get_basename()
		game_state.game_data.player_position = new_player.position

		if "last_direction" in new_player:
			game_state.game_data.player_direction = new_player.last_direction

		if debug: DebugManager.print_debug_auto(self, "DEBUG: Updated game state with new location and player position")
	else:
		if debug: DebugManager.print_debug_auto(self, "DEBUG: Game state not found, could not update persistent data")

# Helper function to find a spawn point in the current scene
func _find_spawn_point(spawn_point_name):
	if debug: DebugManager.print_debug_auto(self, "DEBUG: Looking for spawn point: " + spawn_point_name)

	# Print current scene path for debugging
	if debug: DebugManager.print_debug_auto(self, "DEBUG: Current scene path: " + current_scene_path)

	# First look for a dedicated spawn point node
	var spawn_points = get_tree().get_nodes_in_group("spawn_point")
	if debug: DebugManager.print_debug_auto(self, "DEBUG: Found " + str(spawn_points.size()) + " spawn points in the scene")

	# Debug: print all spawn points
	for i in range(spawn_points.size()):
		var point = spawn_points[i]
		if debug: DebugManager.print_debug_auto(self, "DEBUG: Spawn point " + str(i) + ": name=" + point.name + ", position=" + str(point.global_position))

		# Handle properties if they exist
		if point.get("spawn_id") != null:
			if debug: DebugManager.print_debug_auto(self, "DEBUG: ... has spawn_id property: " + str(point.get("spawn_id")))
		if point.get("is_default") != null:
			DebugManager.print_debug_auto(self, "DEBUG: ... is_default: " + str(point.get("is_default")))

	# Look for matching spawn point by name first
	for point in spawn_points:
		if point.name == spawn_point_name:
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Found spawn point by name: " + point.name + " at position " + str(point.global_position))
			return point.global_position

	# Then look for matching spawn point by spawn_id
	for point in spawn_points:
		# Try to get the spawn_id property safely
		var id = point.get("spawn_id")
		if id != null and id == spawn_point_name:
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Found spawn point by spawn_id: " + str(id) + " at position " + str(point.global_position))
			return point.global_position

	# Look for default spawn point if we're looking for "default"
	if spawn_point_name == "default":
		for point in spawn_points:
			# Try to get the is_default property safely
			if point.get("is_default") == true:
				if debug: DebugManager.print_debug_auto(self, "DEBUG: Found default spawn point: " + point.name + " at position " + str(point.global_position))
				return point.global_position

	# If no dedicated spawn point is found, look for a location transition with this name
	var transitions = get_tree().get_nodes_in_group("interactable")
	if debug: DebugManager.print_debug_auto(self, "DEBUG: Found " + str(transitions.size()) + " interactable objects that could be transitions")

	# Debug: print all transitions
	for i in range(transitions.size()):
		var transition = transitions[i]
		if debug: DebugManager.print_debug_auto(self, "DEBUG: Transition " + str(i) + ": name=" + transition.name)

	# Check for matching transition
	for transition in transitions:
		if transition.name == spawn_point_name:
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Found transition point with matching name: " + transition.name + " at position " + str(transition.global_position))
			return transition.global_position

	# Return zero vector if no spawn point is found
	if debug: DebugManager.print_debug_auto(self, "DEBUG: Could not find any spawn point matching: " + spawn_point_name)

	# If there are any spawn points, use the first one as fallback
	if spawn_points.size() > 0:
		if debug: DebugManager.print_debug_auto(self, "DEBUG: Using first available spawn point as fallback: " + spawn_points[0].name + " at position " + str(spawn_points[0].global_position))
		return spawn_points[0].global_position

	if debug: DebugManager.print_debug_auto(self, "DEBUG: No fallback spawn points available, returning Vector2.ZERO")
	return Vector2.ZERO

# Advance the game turn
func advance_turn():
	var game_state = get_node_or_null("/root/GameState")
	if game_state:
		game_state.advance_turn()
	else:
		# Legacy implementation
		if has_meta("current_turn"):
			current_turn = get("current_turn")
		else:
			current_turn = 0

		if has_meta("current_day"):
			current_day = get("current_day")
		else:
			current_day = 1

		if has_meta("turns_per_day"):
			turns_per_day = get("turns_per_day")
		else:
			turns_per_day = 8

		current_turn += 1

		if current_turn >= turns_per_day:
			current_day += 1
			current_turn = 0
			day_advanced.emit()

		turn_completed.emit()

		# Store updated values
		set_meta("current_turn", current_turn)
		set_meta("current_day", current_day)

# Method to unlock areas (called by ItemEffectsSystem)
func unlock_area(area_id):
	# Create a dictionary to store unlocked areas if it doesn't exist
	if not get("unlocked_areas"):
		set("unlocked_areas", {})

	# Unlock the area
	unlocked_areas[area_id] = true
	if debug: DebugManager.print_debug_auto(self, "Area unlocked: " + area_id)

	# You might want to update UI or trigger other events here
	# For example, show a notification to the player

# Method to add knowledge (called by ItemEffectsSystem)
func add_knowledge(knowledge_id):
	# Create a dictionary to store knowledge if it doesn't exist
	if not get("knowledge_base"):
		set("knowledge_base", {})

	# Add knowledge to the knowledge base
	knowledge_base[knowledge_id] = true
	if debug: DebugManager.print_debug_auto(self, "Knowledge added: " + knowledge_id)

	# You might want to update UI or trigger other events here
	# For example, show a notification to the player


func create_test_items():
	# This function can be called when testing or setting up a new game
	var current_scene = get_tree().current_scene

	# Load our pickup script
	var pickup_script = load("res://scripts/pickups/pickup_item.gd")
	if not pickup_script:
		if debug: DebugManager.print_debug_auto(self, "ERROR: Could not load pickup_item.gd")
		return

	# Create a few test items - now just using the ids
	var items = [
		{
			"id": "energy_drink",
			"position": Vector2(700, 400),
			"amount": 1
		}
	]
	var custom_data
	for item in items:
		# Create a minimal custom_data with just amount
		if "amount" in item:
			custom_data = { "amount": item.amount }
		else:
			custom_data = null

		# Now we don't need to pass full item data - it will be loaded from templates
		pickup_script.create_in_world(current_scene, item.position, item.id, custom_data)

func is_area_unlocked(area_id):
	return area_id in unlocked_areas and unlocked_areas[area_id]

func has_knowledge(knowledge_id):
	return knowledge_id in knowledge_base and knowledge_base[knowledge_id]

# game_controller.gd
func toggle_inventory():
	if debug: DebugManager.print_debug_auto(self, "Toggle inventory action detected")

	# Skip if dialog is active
	if dialog_system and dialog_system.has_method("is_dialog_active") and dialog_system.is_dialog_active():
		if debug: DebugManager.print_debug_auto(self, "Dialog active, not showing inventory")
		return

	# Try to find existing inventory panel
	inventory_panel = get_node_or_null("/root/InventoryPanel")

	if not inventory_panel:
		# Check if it's in a CanvasLayer
		var canvas_layers = get_tree().get_nodes_in_group("ui_layer")
		for layer in canvas_layers:
			inventory_panel = layer.get_node_or_null("InventoryPanel")
			if inventory_panel:
				break

	# If still not found, instantiate it
	if not inventory_panel:
		var scene_path = Paths.get_ui("inventory_panel")
		if ResourceLoader.exists(scene_path):
			var scene = load(scene_path)
			if scene:
				# Create a CanvasLayer for the panel
				var canvas = CanvasLayer.new()
				canvas.layer = 100
				canvas.add_to_group("ui_layer")
				get_tree().root.add_child(canvas)

				inventory_panel = scene.instantiate()
				canvas.add_child(inventory_panel)
				inventory_panel.process_mode = Node.PROCESS_MODE_ALWAYS

				if debug: DebugManager.print_debug_auto(self, "Inventory panel created")
			else:
				if debug: DebugManager.print_debug_auto(self, "Failed to load inventory panel scene")
				return
		else:
			if debug: DebugManager.print_debug_auto(self, "Inventory panel scene not found at path: " + scene_path)
			return

	# Toggle visibility through the panel's function
	if inventory_panel.has_method("toggle_visibility"):
		if debug: DebugManager.print_debug_auto(self, "Calling inventory panel's toggle_visibility method")
		inventory_panel.toggle_visibility()
	else:
		# Fallback to direct property toggle
		inventory_panel.visible = !inventory_panel.visible
		get_tree().paused = inventory_panel.visible
		if debug: DebugManager.print_debug_auto(self, "Directly toggled inventory panel visibility: " + str(inventory_panel.visible))




func on_location_entered(location_id):
	if quest_system:
		quest_system.on_location_entered(location_id)
		if debug: DebugManager.print_debug_auto(self, "Location entered: " + location_id)

func debug_complete_quest_objective(quest_id, objective_type, target_id):
	if quest_system:
		if objective_type == "visit":
			quest_system.on_location_entered(target_id)
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Triggered location objective: " + target_id)
		elif objective_type == "talk":
			quest_system._check_talk_objectives(target_id)
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Triggered talk objective with: " + target_id)
		elif objective_type == "custom":
			quest_system.complete_custom_objective(quest_id, target_id)
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Completed custom objective: " + target_id)
		else:
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Unknown objective type: " + objective_type)
	else:
		if debug: DebugManager.print_debug_auto(self, "ERROR: QuestSystem not found")
	

# Add this new function to toggle quest journal
# Consolidated function in game_controller.gd
func toggle_quest_panel():
	if debug: DebugManager.print_debug_auto(self, "DEBUG: toggle_quest_panel called with J key")

	# Always search for panel dynamically - don't store reference
	quest_panel = null
	var parent_canvas = null

	# Check canvas layers first
	if debug: DebugManager.print_debug_auto(self, "DEBUG: Looking in canvas layers")
	var canvas_layers = get_tree().get_nodes_in_group("ui_layer")
	if debug: DebugManager.print_debug_auto(self, "DEBUG: Found " + str(canvas_layers.size()) + " canvas layers")

	for layer in canvas_layers:
		var panel = layer.get_node_or_null("QuestPanel")
		if panel:
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Found quest panel in canvas layer")
			quest_panel = panel
			parent_canvas = layer
			break

	# Look at root if not found in canvas layers
	if not quest_panel:
		quest_panel = get_node_or_null("/root/QuestPanel")
		if quest_panel:
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Found quest panel at /root/QuestPanel")

	# Create if not found anywhere
	if not quest_panel:
		if debug: DebugManager.print_debug_auto(self, "DEBUG: Creating new quest panel")
		var scene_path = Paths.get_ui("quest_panel")
		if ResourceLoader.exists(scene_path):
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Quest panel resource exists")
			var scene = load(scene_path)
			if scene:
				# Create a CanvasLayer
				var canvas = CanvasLayer.new()
				canvas.layer = 100
				canvas.add_to_group("ui_layer")
				get_tree().root.add_child(canvas)

				quest_panel = scene.instantiate()
				canvas.add_child(quest_panel)
				parent_canvas = canvas
				if debug: DebugManager.print_debug_auto(self, "DEBUG: Quest panel created and added to scene")
			else:
				if debug: DebugManager.print_debug_auto(self, "DEBUG: Failed to load quest panel scene")
				return
		else:
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Quest panel scene not found")
			return

	# Force process mode and toggle visibility
	if quest_panel:
		if debug: DebugManager.print_debug_auto(self, "DEBUG: Setting quest panel process mode")
		quest_panel.process_mode = Node.PROCESS_MODE_ALWAYS

		if parent_canvas:
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Parent canvas found, setting layer to 100")
			parent_canvas.layer = 100

		if quest_panel.visible:
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Quest panel was visible, hiding")
			quest_panel.visible = false
			get_tree().paused = false
		else:
			if debug: DebugManager.print_debug_auto(self, "DEBUG: Quest panel was hidden, showing")
			quest_panel.visible = true
			quest_panel.z_index = 100 # Force z-index to be high
			get_tree().paused = true

			# Force refresh the content
			if quest_panel.has_method("refresh_all_lists"):
				DebugManager.print_debug_auto(self, "DEBUG: Calling refresh_all_lists")
				quest_panel.refresh_all_lists()
	else:
		DebugManager.print_debug_auto(self, "DEBUG: Quest panel is null after all attempts")

func waiting():
	# Toggle visibility through the panel's function
	if quest_panel.has_method("toggle_visibility"):
		if debug: DebugManager.print_debug_auto(self, "Calling quest panel's toggle_visibility method")
		quest_panel.toggle_visibility()
	else:
		# Fallback to direct property toggle
		quest_panel.visible = !quest_panel.visible
		get_tree().paused = quest_panel.visible
		if debug: DebugManager.print_debug_auto(self, "Directly toggled quest panel visibility: " + str(quest_panel.visible))
