extends Node

# Dialog System for Love & Lichens
# Integrates with the Dialogue Manager addon

signal dialog_started(character_id)
signal dialog_ended(character_id)
signal dialog_choice_made(choice_id)
signal memory_unlocked(memory_tag)
signal memory_dialogue_added(character_id, dialogue_title)
signal memory_dialogue_selected(character_id, dialogue_title, memory_tag)
signal memory_option_selected(character_id, memory_tag)
signal dialogue_memory_updated(character_id, memory_tag, dialogue_title)
signal conditional_dialogue_checked(character_id, condition_result)


const scr_debug :bool = true
var debug

# Dictionary to track which dialogs have been seen
# Key: character_id, Value: array of seen dialog titles
var seen_dialogs = {}
var current_character_id = ""
var dialogue_resources = {}
var balloon_scene
var memory_system = null
var game_state
var relationship_system = null
var quest_system = null

# Memory-dialogue tracking (consolidated from memory extension)
var dialogue_memory_cache: Dictionary = {}
var conditional_dialogue_cache: Dictionary = {}
var character_memory_states: Dictionary = {}

# Add this to dialog_system.gd - replace the existing _ready() function

func _ready():
	debug = scr_debug or GameController.sys_debug
	if debug: DebugManager.print_debug_auto(self, "Dialog System initialized")
	game_state = GameState
	memory_system = MemorySystem
	if debug: DebugManager.print_debug_auto(self, "Memory system reference obtained: " + str(memory_system != null))

	# Load our custom balloon scene
	if ResourceLoader.exists(Paths.get_ui("encounter_dialogue_balloon")):
		balloon_scene = load(Paths.get_ui("encounter_dialogue_balloon"))
		if debug: DebugManager.print_debug_auto(self, "Loaded enhanced dialogue balloon scene")
	elif ResourceLoader.exists(Paths.get_ui("custom_dialogue_balloon")):
		balloon_scene = load(Paths.get_ui("custom_dialogue_balloon"))
		if debug: DebugManager.print_debug_auto(self, "Loaded custom dialogue balloon scene")
	else:
		# Load the example balloon scene as fallback
		if ResourceLoader.exists(Paths.get_ui("example_balloon")):
			balloon_scene = load(Paths.get_ui("example_balloon"))
			if debug: DebugManager.print_debug_auto(self, "Loaded example balloon scene as fallback")
		else:
			if debug: DebugManager.print_debug_auto(self, "ERROR: Could not find any dialogue balloon scene")

	# Connect to other game systems (memory extension integration)
	relationship_system = get_node_or_null("/root/RelationshipSystem")
	quest_system = get_node_or_null("/root/QuestSystem")

	# Connect to memory system signals
	if memory_system:
		if memory_system.has_signal("memory_discovered"):
			memory_system.memory_discovered.connect(_on_memory_discovered)
		if memory_system.has_signal("dialogue_option_unlocked"):
			memory_system.dialogue_option_unlocked.connect(_on_dialogue_option_unlocked)
		if debug: DebugManager.print_debug_auto(self, "Connected to memory system signals")

	# Connect to relationship system
	if relationship_system:
		if relationship_system.has_signal("relationship_changed"):
			relationship_system.relationship_changed.connect(_on_relationship_changed)

	# Initialize dialogue-memory cache
	_initialize_dialogue_memory_cache()

	# Connect to DialogueManager signals
	if DialogueManager.has_signal("dialogue_started"):
		GameState.safe_connect(DialogueManager, "dialogue_started", Callable(self, "_on_dialogue_started"))
	if DialogueManager.has_signal("dialogue_ended"):
		GameState.safe_connect(DialogueManager, "dialogue_ended", Callable(self, "_on_dialogue_ended"))
	if debug: DebugManager.print_debug_auto(self, "Connected to DialogueManager signals")

	# Get references to other systems
	await get_tree().process_frame

# Signal handlers for DialogueManager
func _on_dialogue_started(_balloon) -> void:
	if debug: DebugManager.print_debug_auto(self, "DialogueManager started dialogue with character: '" + current_character_id + "'")

func _on_dialogue_ended(_balloon) -> void:
	if debug: DebugManager.print_debug_auto(self, "=== ORIGINAL DIALOGUE_ENDED SIGNAL ===")
	if debug: DebugManager.print_debug_auto(self, "DialogueManager ended dialogue")
	if debug: DebugManager.print_debug_auto(self, "Current character ID: '" + current_character_id + "'")

	# Get the current balloons and force cleanup if any remain
	var balloons = get_tree().get_nodes_in_group("dialogue_balloon")
	if balloons.size() > 0:
		if debug: DebugManager.print_debug_auto(self, "Found " + str(balloons.size()) + " dialogue balloons to force cleanup")
		for balloon in balloons:
			if balloon.has_method("queue_free"):
				balloon.queue_free()

	# Emit the signal with the character ID
	if debug: DebugManager.print_debug_auto(self, "Emitting dialog_ended signal with character: '" + current_character_id + "'")
	dialog_ended.emit(current_character_id)
	if debug: DebugManager.print_debug_auto(self, "Dialog ended with " + current_character_id)

	# Clear the current character ID AFTER emitting the signal
	var ended_character_id = current_character_id
	current_character_id = ""

	# Make sure to properly "release" the dialogue control mode
	Engine.time_scale = 1.0
	get_tree().paused = false
	if debug: DebugManager.print_debug_auto(self, "Dialog ended with character '" + ended_character_id + "' - control released")
	if debug: DebugManager.print_debug_auto(self, "=== END ORIGINAL DIALOGUE_ENDED SIGNAL ===")

#SIMPLIFIED: Memory-based dialogue functions using registry
func unlock_memory(tag: String) -> void:
	"""Set a memory tag and notify the system - now uses registry validation"""
	
	# Validate that this is a real memory tag
	if not GameState.is_valid_memory_tag(tag):
		if debug: DebugManager.print_debug_auto(self, "WARNING: Attempting to unlock invalid memory tag: " + str(tag))
		return
	
	# Check if conditions are met
	if not GameState.can_unlock_memory(tag):
		if debug: DebugManager.print_debug_auto(self, "Cannot unlock memory tag (conditions not met): " + str(tag))
		return
	
	# Discover the memory using registry
	if GameState.discover_memory_from_registry(tag, "dialogue"):
		memory_unlocked.emit(tag)
		
		# Also notify the memory system if available
		if memory_system and memory_system.has_method("_on_memory_unlocked"):
			memory_system._on_memory_unlocked(tag)
		
		if debug: DebugManager.print_debug_auto(self, "Successfully unlocked memory: " + str(tag))

# SIMPLIFIED: Check if a tag can be unlocked using registry
func can_unlock(tag: String) -> bool:
	"""Check if a tag can be unlocked - now uses registry conditions"""
	return GameState.can_unlock_memory(tag)

# SIMPLIFIED: Get unlocked memories for a character using registry
func get_unlocked_memories_for_character(character_id: String) -> Array:
	"""Get all unlocked memory tags for a character - now uses registry"""
	var unlocked_memories = []
	
	# Check all memory tags in registry for this character
	for tag_name in GameState.memory_registry.keys():
		var metadata = GameState.memory_registry[tag_name]
		
		if metadata.get("character_id", "") == character_id and GameState.has_tag(tag_name):
			unlocked_memories.append(tag_name)
	
	return unlocked_memories

# UPDATED: Enhanced memory dialogue selection using registry
func select_memory_dialogue(character_id: String, dialogue_title: String) -> bool:
	"""Select a memory-unlocked dialogue option - now uses registry"""
	
	# Get the memory tag for this dialogue using registry
	var memory_tag = GameState.get_memory_tag_for_dialogue_from_registry(character_id, dialogue_title)
	
	if memory_tag.is_empty():
		if debug: DebugManager.print_debug_auto(self, "No memory tag found for dialogue: " + str(character_id) + " -> " + str(dialogue_title))
		return false
	
	# Check if the memory is unlocked
	if not GameState.has_tag(memory_tag):
		if debug: DebugManager.print_debug_auto(self, "Memory tag not unlocked: " + str(memory_tag))
		return false
	
	# Emit signal and start dialogue
	memory_dialogue_selected.emit(character_id, dialogue_title, memory_tag)
	return start_dialog(character_id, dialogue_title)

# ENHANCED: Memory condition checking using registry
func check_dialogue_conditions(character_id: String, dialogue_title: String) -> bool:
	"""Check if dialogue conditions are met using registry metadata"""
	
	# Get memory tag for this dialogue
	var memory_tag = GameState.get_memory_tag_for_dialogue_from_registry(character_id, dialogue_title)
	
	if memory_tag.is_empty():
		# No memory requirements
		return true
	
	# Get metadata from registry
	var metadata = GameState.get_memory_metadata(memory_tag)
	if metadata.is_empty():
		if debug: DebugManager.print_debug_auto(self, "No metadata found for memory tag: " + str(memory_tag))
		return false
	
	# Check if memory is unlocked
	if not GameState.has_tag(memory_tag):
		return false
	
	# Check additional conditions from metadata
	var condition_tags = metadata.get("condition_tags", [])
	for condition_tag in condition_tags:
		if not GameState.has_tag(condition_tag):
			if debug: DebugManager.print_debug_auto(self, "Condition not met: " + str(condition_tag))
			return false
	
	return true

# NEW: Validate memory tag before operations
func validate_memory_operation(tag_name: String, operation: String) -> bool:
	"""Validate that a memory operation is valid using registry"""
	
	if not GameState.is_valid_memory_tag(tag_name):
		if debug: DebugManager.print_debug_auto(self, "Invalid memory tag for " + str(operation) + ": " + str(tag_name))
		return false
	
	var metadata = GameState.get_memory_metadata(tag_name)
	if metadata.is_empty():
		if debug: DebugManager.print_debug_auto(self, "No metadata found for " + str(operation) + ": " + str(tag_name))
		return false
	
	return true

# UPDATED: Enhanced start_dialog function with registry support
func start_dialog(character_id, title = "start"):
	if debug: DebugManager.print_debug_auto(self, "Starting dialog with: " + str(character_id) + " at title: " + str(title))
	
	record_seen_dialog(character_id, title)
	current_character_id = character_id
	
	if debug: DebugManager.print_debug_auto(self, "DIALOG: Checking memory options for " + str(character_id))
	
	# Get memory-unlocked dialogue options using registry
	var memory_options = GameState.get_dialogue_options_from_registry(character_id)
	if debug: DebugManager.print_debug_auto(self, "DIALOG: Found " + str(memory_options.size()) + " memory-unlocked options from registry")
	
	for option in memory_options:
		if debug: DebugManager.print_debug_auto(self, "DIALOG: Memory option available: " + str(option.dialogue_title) + " (tag: " + str(option.tag) + ")")
		memory_dialogue_added.emit(character_id, option.dialogue_title)
	
	# Load the dialogue resource if not already loaded
	if not dialogue_resources.has(character_id):
		if not preload_dialogue(character_id):
			if debug: DebugManager.print_debug_auto(self, "ERROR: Failed to load dialogue for: " + str(character_id))
			return false
	
	# Emit our own signal before DialogueManager does
	dialog_started.emit(character_id)
	
	# Show the dialogue balloon
	if balloon_scene:
		var balloon = DialogueManager.show_dialogue_balloon_scene(
			balloon_scene, 
			dialogue_resources[character_id], 
			title
		)
		if debug: DebugManager.print_debug_auto(self, "Started dialogue with: " + str(character_id) + " at title: " + str(title))
		return true
	else:
		if debug: DebugManager.print_debug_auto(self, "ERROR: No balloon scene available!")
		return false

# Record that a dialog has been seen
func record_seen_dialog(character_id, dialog_title):
	if not seen_dialogs.has(character_id):
		seen_dialogs[character_id] = []

	if not dialog_title in seen_dialogs[character_id]:
		seen_dialogs[character_id].append(dialog_title)
		if debug: DebugManager.print_debug_auto(self, "Recorded seen dialog: " + character_id + " - " + dialog_title)

# Check if a dialog has been seen
func has_seen_dialog(character_id, dialog_title):
	if not seen_dialogs.has(character_id):
		return false

	return dialog_title in seen_dialogs[character_id]
	
# Check if dialog is currently active
func is_dialog_active():
	# First check our internal state
	if current_character_id != "":
		# Do a sanity check - is the actual balloon present?
		var balloons = get_tree().get_nodes_in_group("dialogue_balloon")
		if balloons.size() == 0:
			# No actual balloon found, but we think we're in dialog
			# This means our state is out of sync - fix it
			if debug: DebugManager.print_debug_auto(self, "Dialog state mismatch detected - resetting state")
			current_character_id = ""
			return false
		return true
	return false

# Get all seen dialogs for save system
func get_seen_dialogs():
	return seen_dialogs.duplicate(true)

# Set seen dialogs from save data
func set_seen_dialogs(data):
	seen_dialogs = data.duplicate(true)

# Modify the existing start_dialog function
# We need to add just one line to record seen dialogs


# Preload a dialogue resource
func preload_dialogue(character_id):
	var file_path = "res://data/dialogues/" + character_id + ".dialogue"

	if ResourceLoader.exists(file_path):
		dialogue_resources[character_id] = load(file_path)
		if debug: DebugManager.print_debug_auto(self, "Preloaded dialogue for: " + character_id)
		return true
	else:
		if debug: DebugManager.print_debug_auto(self, "ERROR: Could not find dialogue file: " + file_path)
		return false

# For backwards compatibility with existing code
func end_dialog():
	if debug: DebugManager.print_debug_auto(self, "Dialog ended manually")

	# Get the current balloons and force cleanup if any remain
	var balloons = get_tree().get_nodes_in_group("dialogue_balloon")
	if balloons.size() > 0:
		if debug: DebugManager.print_debug_auto(self, "Found " + str(balloons.size()) + " dialogue balloons to force cleanup")
		for balloon in balloons:
			if balloon.has_method("queue_free"):
				balloon.queue_free()

	dialog_ended.emit(current_character_id)

	# Clear the current character ID to indicate dialogue is no longer active
	current_character_id = ""

	# Make sure to properly "release" the dialogue control mode
	# This ensures the game knows we're no longer in dialogue
	Engine.time_scale = 1.0
	get_tree().paused = false
	if debug: DebugManager.print_debug_auto(self, "Dialog ended manually - control released")
	

# Starts a custom dialog from a string
func start_custom_dialog(dialog_content: String, title: String = "start"):
	if debug: DebugManager.print_debug_auto(self, "Starting custom dialog at " + str(title))
	
	# Use the Dialogue Manager to parse and start the dialogue
	var dialogue_resource = DialogueManager.create_resource_from_text(dialog_content)
	
	if dialogue_resource:
		# Emit our own signal before DialogueManager does
		dialog_started.emit("custom_dialog")
		
		# Show the dialogue balloon
		if balloon_scene:
			var balloon = DialogueManager.show_dialogue_balloon_scene(
				balloon_scene, 
				dialogue_resource, 
				title
			)
			return true
	
	if debug: DebugManager.print_debug_auto(self, "Failed to start custom dialog")
	return false
	
# Helper functions for memory-based dialogue


# Add a dialogue choice if a tag condition is met
func add_conditional_choice(choices: Array, condition_tag: String, text: String, target: String) -> Array:
	if can_unlock(condition_tag):
		choices.append({
			"text": text,
			"target": target
		})
	return choices

# Add to dialog_system.gd
func _on_mutated(mutation):
	if debug: DebugManager.print_debug_auto(self, "Handling mutation: " + str(mutation.name))
	
	if mutation.name == "move_character":
		# Forward the call directly to CutsceneManager
		var cutscene_manager = get_node_or_null("/root/CutsceneManager")
		if cutscene_manager:
			# Pass all arguments directly to the cutscene manager
			if mutation.arguments.size() >= 2:
				var character_id = mutation.arguments[0]
				var target = mutation.arguments[1]
				
				# Set default values for optional parameters
				var animation = "walk"
				var speed = null
				var stop_distance = 0
				var time = null
				
				# Check for additional parameters
				if mutation.arguments.size() >= 3:
					animation = mutation.arguments[2]
				if mutation.arguments.size() >= 4:
					# Try to convert to number, otherwise pass as is
					var speed_val = mutation.arguments[3]
					if speed_val is String and speed_val.is_valid_float():
						speed = float(speed_val)
					else:
						speed = speed_val
				if mutation.arguments.size() >= 5:
					# Try to convert to number, otherwise pass as is
					var stop_val = mutation.arguments[4]
					if stop_val is String and stop_val.is_valid_float():
						stop_distance = float(stop_val)
					else:
						stop_distance = stop_val
				if mutation.arguments.size() >= 6:
					# Try to convert to number, otherwise pass as is
					var time_val = mutation.arguments[5]
					if time_val is String and time_val.is_valid_float():
						time = float(time_val)
					else:
						time = time_val
				
				cutscene_manager.move_character(character_id, target, animation, speed, stop_distance, time)
			else:
				if debug: DebugManager.print_debug_auto(self, "ERROR: move_character requires at least character_id and target")
		else:
			if debug: DebugManager.print_debug_auto(self, "ERROR: CutsceneManager not found")
		return null
	
	elif mutation.name == "play_animation":
		var cutscene_manager = get_node_or_null("/root/CutsceneManager")
		if cutscene_manager and mutation.arguments.size() >= 2:
			cutscene_manager.play_animation(mutation.arguments[0], mutation.arguments[1])
		return null
	
	elif mutation.name == "wait_for_movements":
		var cutscene_manager = get_node_or_null("/root/CutsceneManager")
		if not cutscene_manager:
			if debug: DebugManager.print_debug_auto(self, "ERROR: CutsceneManager not found")
			return null
		
		# If no movements are active, return immediately
		if cutscene_manager.active_movements.size() == 0:
			return true
		
		# Return a coroutine waiting for the movement_completed signal
		return cutscene_manager.movement_completed
	
	return null

func _handle_wait_for_movements_mutation():
	var cutscene_manager = get_node_or_null("/root/CutsceneManager")
	if not cutscene_manager:
		if debug: DebugManager.print_debug_auto(self, "ERROR: CutsceneManager not found")
		return
	
	# This will pause the dialogue until all movements complete
	await cutscene_manager.movement_completed
	
	# Check if more movements are still happening
	while not cutscene_manager.wait_for_all_movements():
		await cutscene_manager.movement_completed
	
	return true

func _handle_move_character_mutation(mutation):
	var cutscene_manager = get_node_or_null("/root/CutsceneManager")
	if not cutscene_manager:
		if debug: DebugManager.print_debug_auto(self, "ERROR: CutsceneManager not found")
		return
	
	# Check for minimum required arguments
	if mutation.arguments.size() < 2:
		if debug: DebugManager.print_debug_auto(self, "ERROR: move_character requires at least character_id and target")
		return
	
	var character_id = mutation.arguments[0]
	var target = mutation.arguments[1]
	
	# Create a params dictionary for additional arguments
	var params = {}
	
	# Process pairs of parameter name and value
	for i in range(2, mutation.arguments.size(), 2):
		if i + 1 < mutation.arguments.size():
			var param_name = str(mutation.arguments[i])
			var param_value = mutation.arguments[i + 1]
			
			# Convert numeric strings to actual numbers
			if param_value is String and param_value.is_valid_float():
				param_value = float(param_value)
			
			params[param_name] = param_value
	
	# Start the movement
	cutscene_manager.move_character(character_id, target, params)

func _handle_play_animation_mutation(mutation):
	var character_id = mutation.arguments.get(0, null)
	var animation_name = mutation.arguments.get(1, null)
	
	if not character_id or not animation_name:
		if debug: DebugManager.print_debug_auto(self, "ERROR: Missing character ID or animation in play_animation mutation")
		return
	
	# Find character
	var character
	if character_id == "player":
		var game_state = get_node_or_null("/root/GameState")
		if game_state and game_state.has_method("get_player"):
			character = game_state.get_player()
	else:
		character = get_tree().get_first_node_in_group(character_id)
		if not character:
			# Try by node path
			character = get_tree().current_scene.get_node_or_null(character_id)
	
	if character:
		# Try different animation methods
		if character.has_method("play_animation"):
			character.play_animation(animation_name)
		elif character.has_node("AnimationPlayer"):
			var anim_player = character.get_node("AnimationPlayer")
			if anim_player.has_animation(animation_name):
				anim_player.play(animation_name)

# ============================================================================
# CONSOLIDATED FROM DialogMemoryExtension - Dialogue-Memory Integration
# ============================================================================

# SIMPLIFIED: Memory checking functions using registry
func has_memory(memory_tag: String) -> bool:
	"""Check if memory exists and is unlocked - validates against registry"""

	# Validate tag exists in registry
	if not GameState.is_valid_memory_tag(memory_tag):
		if debug: DebugManager.print_debug_auto(self, "Invalid memory tag: " + str(memory_tag))
		return false

	return GameState.has_tag(memory_tag)

func get_memory_value(memory_tag: String, default_value = null):
	"""Get memory value with registry validation"""

	# Validate tag exists in registry
	if not GameState.is_valid_memory_tag(memory_tag):
		if debug: DebugManager.print_debug_auto(self, "Invalid memory tag: " + str(memory_tag))
		return default_value

	return GameState.get_tag_value(memory_tag, default_value)

func set_memory(memory_tag: String, value = true):
	"""Set memory with registry validation and proper discovery"""

	# Validate tag exists in registry
	if not GameState.is_valid_memory_tag(memory_tag):
		if debug: DebugManager.print_debug_auto(self, "Cannot set invalid memory tag: " + str(memory_tag))
		return

	# Use registry-based discovery if this is a new memory
	if not GameState.has_tag(memory_tag) and value:
		GameState.discover_memory_from_registry(memory_tag, "dialogue_system")
	else:
		# Just set the tag directly
		GameState.set_tag(memory_tag, value)

func _initialize_dialogue_memory_cache():
	# Pre-cache dialogue-memory relationships for performance
	if memory_system:
		# Get available dialogue options from GameState instead of memory_system.dialogue_mapping
		var all_characters = []

		# Get all character IDs from CharacterDataLoader
		var character_loader = get_node_or_null("/root/CharacterDataLoader")
		if character_loader:
			all_characters = character_loader.characters.keys()

		# Build cache for each character
		for character_id in all_characters:
			var dialogue_options = GameState.get_available_dialogue_options(character_id)

			if not dialogue_memory_cache.has(character_id):
				dialogue_memory_cache[character_id] = {}

			for option in dialogue_options:
				var dialogue_title = option.dialogue_title
				var memory_tag = option.tag
				dialogue_memory_cache[character_id][dialogue_title] = memory_tag

				if debug: DebugManager.print_debug_auto(self, "Cached dialogue mapping: " + str(character_id) + " -> " + str(dialogue_title) + " = " + str(memory_tag))

# Core dialogue-memory functions for use in .dialogue files

func increment_memory(memory_tag: String, amount: int = 1):
	if game_state:
		var current_value = game_state.get_tag_value(memory_tag, 0)
		if typeof(current_value) == TYPE_INT or typeof(current_value) == TYPE_FLOAT:
			game_state.set_tag(memory_tag, current_value + amount)

# ENHANCED: Complex memory condition checking using registry metadata
func check_memory_condition(condition: String) -> bool:
	"""Parse and evaluate memory conditions with registry validation"""

	# Parse the condition string (same logic as before, but with validation)
	condition = condition.strip_edges()

	# Handle negation
	if condition.begins_with("!"):
		return not check_memory_condition(condition.substr(1).strip_edges())

	# Handle OR conditions
	if " || " in condition:
		var parts = condition.split(" || ")
		for part in parts:
			if check_memory_condition(part.strip_edges()):
				return true
		return false

	# Handle AND conditions
	if " && " in condition:
		var parts = condition.split(" && ")
		for part in parts:
			if not check_memory_condition(part.strip_edges()):
				return false
		return true

	# Handle comparison operations
	if " == " in condition:
		var parts = condition.split(" == ")
		if parts.size() == 2:
			var memory_tag = parts[0].strip_edges()
			if not GameState.is_valid_memory_tag(memory_tag):
				if debug: DebugManager.print_debug_auto(self, "Invalid memory tag in condition: " + str(memory_tag))
				return false
			var memory_value = get_memory_value(memory_tag)
			var compare_value = _parse_value(parts[1].strip_edges())
			return memory_value == compare_value

	# Simple boolean check with validation
	if not GameState.is_valid_memory_tag(condition):
		if debug: DebugManager.print_debug_auto(self, "Invalid memory tag in condition: " + str(condition))
		return false

	return has_memory(condition)

# SIMPLIFIED: Character memory state using registry
func get_character_memory_state(character_id: String) -> Dictionary:
	"""Get character memory state using registry data"""

	var state = {
		"discovered_memories": [],
		"available_dialogues": [],
		"relationship_level": 0,
		"memory_tags": []
	}

	# Get all memories for this character from registry
	for tag_name in GameState.memory_registry.keys():
		var metadata = GameState.memory_registry[tag_name]

		if metadata.get("character_id", "") == character_id:
			state.memory_tags.append(tag_name)

			if GameState.has_tag(tag_name):
				state.discovered_memories.append(tag_name)

				# Check for dialogue options
				var dialogue_title = metadata.get("dialogue_title", "")
				if dialogue_title != "":
					state.available_dialogues.append(dialogue_title)

	# Get relationship level if system exists
	if relationship_system:
		state.relationship_level = relationship_system.get_relationship_score(character_id)

	return state

# SIMPLIFIED: Dialogue availability using registry
func can_show_dialogue(character_id: String, dialogue_title: String) -> bool:
	"""Check if dialogue can be shown using registry conditions"""

	# Get memory tag for this dialogue from registry
	var memory_tag = GameState.get_memory_tag_for_dialogue_from_registry(character_id, dialogue_title)

	if memory_tag.is_empty():
		# No memory requirements, allow dialogue
		return true

	# Check if memory is unlocked
	if not GameState.has_tag(memory_tag):
		return false

	# Get additional requirements from registry metadata
	var metadata = GameState.get_memory_metadata(memory_tag)

	# Check relationship requirements (if specified in metadata)
	if metadata.has("min_relationship"):
		if relationship_system:
			var current_level = relationship_system.get_relationship_score(character_id)
			if current_level < metadata.min_relationship:
				return false

	# Check quest requirements (if specified in metadata)
	if metadata.has("required_quest"):
		if quest_system:
			var quest_id = metadata.required_quest
			if not quest_system.is_quest_active(quest_id) and not quest_system.is_quest_completed(quest_id):
				return false

	# Check condition tags from registry
	var condition_tags = metadata.get("condition_tags", [])
	for condition_tag in condition_tags:
		if not GameState.has_tag(condition_tag):
			return false

	return true

# SIMPLIFIED: Get memory dialogue options using registry
func get_memory_dialogue_options(character_id: String) -> Array:
	"""Get memory-driven dialogue options using registry"""
	var options = []

	# Get available dialogue options from registry
	var available_options = GameState.get_dialogue_options_from_registry(character_id)

	for option in available_options:
		if can_show_dialogue(character_id, option.dialogue_title):
			options.append({
				"title": option.dialogue_title,
				"memory_tag": option.tag,
				"display_text": _get_dialogue_display_text(character_id, option.dialogue_title),
				"description": option.description
			})

	return options

# SIMPLIFIED: Memory discovery trigger using registry
func trigger_memory_discovery(character_id: String, memory_tag: String, description: String = ""):
	"""Trigger memory discovery with registry validation"""

	# Validate memory tag
	if not GameState.is_valid_memory_tag(memory_tag):
		if debug: DebugManager.print_debug_auto(self, "Cannot trigger invalid memory tag: " + str(memory_tag))
		return

	# Use description from registry if not provided
	if description.is_empty():
		var metadata = GameState.get_memory_metadata(memory_tag)
		description = metadata.get("description", "Memory discovered")

	# Discover using registry system
	GameState.discover_memory_from_registry(memory_tag, "dialogue_trigger")

# NEW: Registry-based memory validation
func validate_memory_tags(tag_list: Array) -> Dictionary:
	"""Validate a list of memory tags against the registry"""
	var result = {
		"valid": [],
		"invalid": [],
		"warnings": []
	}

	for tag in tag_list:
		if GameState.is_valid_memory_tag(tag):
			result.valid.append(tag)
		else:
			result.invalid.append(tag)
			result.warnings.append("Invalid memory tag: " + tag)

	if debug and result.invalid.size() > 0:
		print(GameState.script_name_tag(self) + "Found invalid memory tags: ", result.invalid)

	return result

# ENHANCED: Debug functions using registry
func debug_character_memories(character_id: String):
	"""Debug character memories using registry data"""
	if not debug:
		return

	print("\n" + GameState.script_name_tag(self) + "=== CHARACTER MEMORY DEBUG (REGISTRY): ", character_id, " ===")

	var state = get_character_memory_state(character_id)

	print(GameState.script_name_tag(self) + "Total memory tags for character: ", state.memory_tags.size())
	print(GameState.script_name_tag(self) + "Discovered memories: ", state.discovered_memories.size())
	print(GameState.script_name_tag(self) + "Available dialogues: ", state.available_dialogues.size())

	print(GameState.script_name_tag(self) + "Memory tags from registry:")
	for tag in state.memory_tags:
		var metadata = GameState.get_memory_metadata(tag)
		var is_unlocked = GameState.has_tag(tag)
		print(GameState.script_name_tag(self) + "  - ", tag, " (unlocked: ", is_unlocked, ") - ", metadata.get("description", ""))

	print(GameState.script_name_tag(self) + "=================================\n")

func _evaluate_memory_condition(condition: String) -> bool:
	# Simple condition parser for memory checks
	condition = condition.strip_edges()

	# Handle negation
	if condition.begins_with("!"):
		return not _evaluate_memory_condition(condition.substr(1).strip_edges())

	# Handle OR conditions
	if " || " in condition:
		var parts = condition.split(" || ")
		for part in parts:
			if _evaluate_memory_condition(part.strip_edges()):
				return true
		return false

	# Handle AND conditions
	if " && " in condition:
		var parts = condition.split(" && ")
		for part in parts:
			if not _evaluate_memory_condition(part.strip_edges()):
				return false
		return true

	# Handle comparison operations
	if " == " in condition:
		var parts = condition.split(" == ")
		if parts.size() == 2:
			var memory_value = get_memory_value(parts[0].strip_edges())
			var compare_value = _parse_value(parts[1].strip_edges())
			return memory_value == compare_value

	if " != " in condition:
		var parts = condition.split(" != ")
		if parts.size() == 2:
			var memory_value = get_memory_value(parts[0].strip_edges())
			var compare_value = _parse_value(parts[1].strip_edges())
			return memory_value != compare_value

	if " >= " in condition:
		var parts = condition.split(" >= ")
		if parts.size() == 2:
			var memory_value = get_memory_value(parts[0].strip_edges(), 0)
			var compare_value = _parse_value(parts[1].strip_edges())
			return memory_value >= compare_value

	if " <= " in condition:
		var parts = condition.split(" <= ")
		if parts.size() == 2:
			var memory_value = get_memory_value(parts[0].strip_edges(), 0)
			var compare_value = _parse_value(parts[1].strip_edges())
			return memory_value <= compare_value

	if " > " in condition:
		var parts = condition.split(" > ")
		if parts.size() == 2:
			var memory_value = get_memory_value(parts[0].strip_edges(), 0)
			var compare_value = _parse_value(parts[1].strip_edges())
			return memory_value > compare_value

	if " < " in condition:
		var parts = condition.split(" < ")
		if parts.size() == 2:
			var memory_value = get_memory_value(parts[0].strip_edges(), 0)
			var compare_value = _parse_value(parts[1].strip_edges())
			return memory_value < compare_value

	# Simple boolean check
	return has_memory(condition)

func _parse_value(value_str: String):
	value_str = value_str.strip_edges()

	# Remove quotes for strings
	if value_str.begins_with('"') and value_str.ends_with('"'):
		return value_str.substr(1, value_str.length() - 2)

	# Parse numbers
	if value_str.is_valid_int():
		return int(value_str)
	elif value_str.is_valid_float():
		return float(value_str)

	# Parse booleans
	if value_str.to_lower() == "true":
		return true
	elif value_str.to_lower() == "false":
		return false

	return value_str

func _get_dialogue_display_text(character_id: String, dialogue_title: String) -> String:
	# Get display text for memory-unlocked dialogue options
	var character_loader = get_node_or_null("/root/CharacterDataLoader")
	if character_loader:
		var character_data = character_loader.get_character(character_id)
		if character_data and character_data.has("dialogue_display_texts"):
			var display_texts = character_data.dialogue_display_texts
			if display_texts.has(dialogue_title):
				return display_texts[dialogue_title]

	# Default display text
	return dialogue_title.replace("_", " ").capitalize()

# Memory-based dialogue triggers
func trigger_memory_dialogue(character_id: String, dialogue_title: String, memory_tag: String):
	memory_option_selected.emit(character_id, memory_tag)
	dialogue_memory_updated.emit(character_id, memory_tag, dialogue_title)

	# Update character memory state cache
	if character_memory_states.has(character_id):
		character_memory_states.erase(character_id)  # Force rebuild

# Relationship-memory integration
func check_relationship_memory(character_id: String, min_relationship: int, required_memory: String) -> bool:
	if relationship_system:
		var current_relationship = relationship_system.get_relationship_score(character_id)
		if current_relationship < min_relationship:
			return false

	return has_memory(required_memory)

func get_relationship_level(character_id: String) -> int:
	if relationship_system:
		return relationship_system.get_relationship_score(character_id)
	return 0

func get_relationship_name(character_id: String) -> String:
	if relationship_system:
		var level = relationship_system.get_relationship_score(character_id)
		return relationship_system.get_relationship_name(level)
	return "Unknown"

# Quest-memory integration
func has_active_quest(quest_id: String) -> bool:
	return quest_system.is_quest_active(quest_id) if quest_system else false

func has_completed_quest(quest_id: String) -> bool:
	return quest_system.is_quest_completed(quest_id) if quest_system else false

func check_quest_memory(quest_id: String, memory_tag: String) -> bool:
	return has_active_quest(quest_id) and has_memory(memory_tag)

# Advanced memory operations for dialogue
func unlock_memory_chain(character_id: String, chain_id: String):
	if memory_system and memory_system.has_method("create_memory_chain"):
		# This would require the memory chain data to be accessible
		var character_loader = get_node_or_null("/root/CharacterDataLoader")
		if character_loader:
			var character_data = character_loader.get_character(character_id)
			if character_data and character_data.has("memory_chains"):
				var chains = character_data.memory_chains
				if chains.has(chain_id):
					memory_system.create_memory_chain(character_id, chains[chain_id])

# Conditional dialogue caching for performance
func cache_conditional_dialogue(character_id: String, dialogue_title: String, condition: String, result: bool):
	if not conditional_dialogue_cache.has(character_id):
		conditional_dialogue_cache[character_id] = {}

	conditional_dialogue_cache[character_id][dialogue_title] = {
		"condition": condition,
		"result": result,
		"cached_time": Time.get_unix_time_from_system()
	}

func get_cached_dialogue_condition(character_id: String, dialogue_title: String) -> Dictionary:
	if conditional_dialogue_cache.has(character_id):
		if conditional_dialogue_cache[character_id].has(dialogue_title):
			var cached = conditional_dialogue_cache[character_id][dialogue_title]
			var cache_age = Time.get_unix_time_from_system() - cached.cached_time

			# Cache expires after 60 seconds
			if cache_age < 60:
				return cached

	return {}

# Signal handlers for memory integration
func _on_memory_discovered(memory_tag: String, description: String):
	if debug: DebugManager.print_debug_auto(self, "Memory discovered - " + str(memory_tag))

	# Clear relevant caches
	conditional_dialogue_cache.clear()
	character_memory_states.clear()

func _on_dialogue_option_unlocked(character_id: String, dialogue_title: String, memory_tag: String):
	if debug: DebugManager.print_debug_auto(self, "Dialogue option unlocked - " + str(character_id) + " -> " + str(dialogue_title))

	# Update cache
	if not dialogue_memory_cache.has(character_id):
		dialogue_memory_cache[character_id] = {}

	dialogue_memory_cache[character_id][dialogue_title] = memory_tag

	# Clear character memory state cache
	if character_memory_states.has(character_id):
		character_memory_states.erase(character_id)

func _on_relationship_changed(character_id: String, old_level: int, new_level: int):
	if debug: DebugManager.print_debug_auto(self, "Relationship changed - " + str(character_id) + " (" + str(old_level) + " -> " + str(new_level) + ")")

	# Clear caches for this character
	if conditional_dialogue_cache.has(character_id):
		conditional_dialogue_cache.erase(character_id)

	if character_memory_states.has(character_id):
		character_memory_states.erase(character_id)

# Utility functions for dialogue files
func format_memory_text(memory_tag: String, template: String) -> String:
	# Replace placeholders in template with memory values
	var text = template
	var memory_value = get_memory_value(memory_tag)

	text = text.replace("{memory_value}", str(memory_value))
	text = text.replace("{memory_tag}", memory_tag)

	return text

func get_memory_count(memory_prefix: String) -> int:
	# Count memories that start with a prefix
	var count = 0
	if game_state:
		for tag in game_state.tags.keys():
			if tag.begins_with(memory_prefix):
				count += 1

	return count

func debug_memory_conditions():
	if not debug:
		return

	print(GameState.script_name_tag(self) + "\n=== MEMORY CONDITIONS DEBUG ===")

	# Test various memory conditions
	var test_conditions = [
		"library_visited",
		"!quest_intro_completed",
		"memory_count >= 1"
	]

	for condition in test_conditions:
		var result = check_memory_condition(condition)
		print(GameState.script_name_tag(self) + "Condition: ", condition, " -> ", result)

	print(GameState.script_name_tag(self) + "==============================\n")
