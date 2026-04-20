# cutscene_manager.gd - Fixed version
extends Node

signal movement_started(character_id, target)
signal movement_completed(character_id)
signal all_movements_completed

const scr_debug : bool = true
var debug

# Dictionary to track active movements
var active_movements = {}

var movement_queue = {}  # Dictionary of character_id -> Array of movement commands
var processing_movement_queue = false

# Dictionary to store prepared cutscenes
var stored_cutscenes: Dictionary = {}
var active_cutscene: Node = null

var active_cutscene_npcs: Array[Node] = []
# Tracks follows that should emit caught_up when within range: npc_id -> {npc, target, target_id, distance}
var _signal_follow_targets: Dictionary = {}
var active_cutscene_props: Array[Node] = []
var cutscene_markers: Dictionary = {}  # Runtime-created markers
var cutscene_camera: Camera2D = null   # Spawned during camera moves; null when player cam is active

# Signal for cutscene events
signal cutscene_started(cutscene_id)
signal cutscene_finished(cutscene_id)
signal caught_up(npc: Node2D, target_id: String)

func _ready():
	const _fname : String = "_ready"
	print(GameState.script_name_tag(self, _fname) + "CutsceneManager initialized and ready!")
	debug = scr_debug or GameController.sys_debug
	
	_load_cutscene_registry()

# Dictionary to cache loaded cutscene scenes
var cutscene_scene_cache: Dictionary = {}



# Enhanced cutscene starting function - replaces the existing start_cutscene
func start_cutscene(cutscene_id: String) -> bool:
	const _fname : String = "start_cutscene"
	"""Start a cutscene by ID - pure data-driven approach"""
	if not can_trigger_cutscene(cutscene_id):
		if debug: print(GameState.script_name_tag(self, _fname) + "Cannot trigger cutscene: ", cutscene_id)
		return false
	
	var cutscene_data = get_cutscene_data(cutscene_id)
	if cutscene_data.is_empty():
		if debug: print(GameState.script_name_tag(self, _fname) + "Cutscene data not found: ", cutscene_id)
		return false
	
	# Clean up any existing cutscene
	cleanup_active_cutscene()
	
	# Create runtime markers from JSON data
	_create_runtime_markers(cutscene_data)
	
	# Spawn NPCs and props
	_spawn_cutscene_npcs(cutscene_data)
	_spawn_cutscene_props(cutscene_data)
	
	# Move player to starting position if specified
	var player_start_marker = cutscene_data.get("player_start_marker", "")
	if player_start_marker != "":
		_move_player_to_marker(player_start_marker)
	
	# Start the main cutscene dialogue
	_start_cutscene_dialogue(cutscene_data)
	
	# Mark as seen and unlock tags
	GameState.set_tag("cutscene_seen_" + cutscene_id)
	var unlocks = cutscene_data.get("unlocks", [])
	for unlock_tag in unlocks:
		GameState.set_tag(unlock_tag)
	
	cutscene_started.emit(cutscene_id)
	if debug: print(GameState.script_name_tag(self, _fname) + "Started cutscene: ", cutscene_id)
	return true

func _create_runtime_markers(cutscene_data: Dictionary):
	const _fname : String = "_create_runtime_markers"
	"""Create temporary marker nodes from JSON position data"""
	var marker_positions = cutscene_data.get("marker_positions", {})
	cutscene_markers.clear()
	
	var current_scene = get_tree().current_scene
	
	for marker_name in marker_positions:
		var pos_data = marker_positions[marker_name]
		var position = Vector2(pos_data.get("x", 0), pos_data.get("y", 0))
		
		# Create a simple Node2D marker
		var marker = Node2D.new()
		marker.name = marker_name + "_runtime"
		marker.position = position
		marker.add_to_group("marker")
		
		# Add to scene temporarily
		current_scene.add_child(marker)
		
		# Store reference
		cutscene_markers[marker_name] = marker
		
		if debug: print(GameState.script_name_tag(self, _fname) + "Created runtime marker: ", marker_name, " at ", position)

func _spawn_cutscene_npcs(cutscene_data: Dictionary):
	const _fname : String = "_spawn_cutscene_npcs"
	"""Spawn NPCs from cutscene data"""
	var npcs_data = cutscene_data.get("npcs", [])

	for npc_data in npcs_data:
		_spawn_single_npc(npc_data)

func _spawn_single_npc(npc_data: Dictionary):
	const _fname : String = "_spawn_single_npc"
	if debug: print(GameState.script_name_tag(self, _fname) + "function_called")
	"""Spawn a single NPC from data"""
	var scene_path = npc_data.get("scene_path", "")
	if scene_path == "":
		return
		
	# Load the NPC scene
	var npc_scene = load(scene_path)
	if not npc_scene:
		print(GameState.script_name_tag(self, _fname) + "Failed to load NPC scene: ", scene_path)
		return
	
	# Instance the NPC
	var npc_instance = npc_scene.instantiate()
	npc_instance.z_as_relative = false
	var npc_id = npc_data.get("id", npc_data.get("npc_id", ""))
	npc_instance.name = npc_id
	
	# Set character properties
	var character_id = npc_data.get("character_id", npc_id)
	if "character_id" in npc_instance:
		npc_instance.character_id = character_id
	
	var character_name = npc_data.get("character_name", character_id.capitalize())
	if "character_name" in npc_instance:
		npc_instance.character_name = character_name
	if debug: print(GameState.script_name_tag(self, _fname) + "npc_instance.character_name = " + character_name)

	
	var parent_layer = npc_data.get("parent")
	var parent_node = GameState.get_layer(parent_layer)
	if debug: print(GameState.script_name_tag(self, _fname) + "parent_layer = " + parent_layer)


	# Set character scale to match scene
	if debug: print(GameState.script_name_tag(self, _fname) + parent_node.name + " scale = " + str(parent_node.scale))
	var npc_scale = GameState.get_player().scale / parent_node.scale  / parent_node.get_parent().scale # Calculate character scale based on parent node
	npc_instance.scale = npc_scale
	if debug: print(GameState.script_name_tag(self, _fname) + "Set character scale to: ", npc_scale)
	
	
	# Set dialogue properties
	var dialogue_file = npc_data.get("dialogue_file", "")
	if dialogue_file != "" and "dialogue_file" in npc_instance:
		npc_instance.dialogue_file = dialogue_file
	
	var dialogue_title = npc_data.get("dialogue_title", npc_data.get("initial_dialogue_title", ""))
	if dialogue_title != "" and "initial_dialogue_title" in npc_instance:
		npc_instance.initial_dialogue_title = dialogue_title
	
	# Set position from marker or direct coordinates
	var spawn_pos = _get_spawn_position(npc_data)
	npc_instance.global_position = spawn_pos /  parent_node.scale  / parent_node.get_parent().scale 
	
	# Set direction and animation
	var direction = npc_data.get("direction", npc_data.get("initial_direction"))
	if npc_instance.has_method("set_direction"):
		npc_instance.set_direction(direction)
	elif "direction" in npc_instance:
		npc_instance.direction = direction
	
	var initial_animation = npc_data.get("initial_animation")
	if "initial_animation" in npc_instance:
		npc_instance.initial_animation = initial_animation


	# Add to scene and groups
	parent_node.add_child(npc_instance)
	npc_instance.add_to_group("npc")
	
	# Track for cleanup
	active_cutscene_npcs.append(npc_instance)
	
	npc_instance.set_animation(initial_animation)
	
	if debug: print(GameState.script_name_tag(self, _fname) + "Spawned NPC: ", npc_id, " at ", spawn_pos)
	
	

func _spawn_cutscene_props(cutscene_data: Dictionary):
	const _fname : String = "_spawn_cutscene_props"
	"""Spawn props from cutscene data"""
	var props_data = cutscene_data.get("props", [])
	
	# Find z_Objects container
	var z_objects = _find_z_objects_container()
	if not z_objects:
		return
	
	for prop_data in props_data:
		_spawn_single_prop(prop_data, z_objects)

func _spawn_single_prop(prop_data: Dictionary, z_objects: Node):
	const _fname : String = "_spawn_single_prop"
	"""Spawn a single prop from data"""
	var scene_path = prop_data.get("scene_path", "")
	if scene_path == "":
		return
	
	# Load the prop scene
	var prop_scene = load(scene_path)
	if not prop_scene:
		print(GameState.script_name_tag(self) + "Failed to load prop scene: ", scene_path)
		return
	
	# Instance the prop
	var prop_instance = prop_scene.instantiate()
	var prop_id = prop_data.get("id", prop_data.get("prop_id", ""))
	prop_instance.name = prop_id
	
	# Set position
	var spawn_pos = _get_spawn_position(prop_data)
	prop_instance.global_position = spawn_pos
	
	# Add to scene
	z_objects.add_child(prop_instance)
	
	# Track for cleanup
	active_cutscene_props.append(prop_instance)
	
	if debug: print(GameState.script_name_tag(self) + "Spawned prop: ", prop_id, " at ", spawn_pos)

func _get_spawn_position(spawn_data: Dictionary) -> Vector2:
	const _fname : String = "_get_spawn_position"
	"""Get spawn position from marker name or direct coordinates"""
	var marker_name = spawn_data.get("marker", spawn_data.get("spawn_marker", ""))
	
	if marker_name != "":
		# Use marker position
		if cutscene_markers.has(marker_name):
			return cutscene_markers[marker_name].global_position
		else:
			print(GameState.script_name_tag(self) + "WARNING: Marker not found: ", marker_name)
	
	# Fall back to direct position
	var pos_data = spawn_data.get("position", spawn_data.get("spawn_position", {}))
	if pos_data is Dictionary:
		return Vector2(pos_data.get("x", 0), pos_data.get("y", 0))
	elif pos_data is Array and pos_data.size() >= 2:
		return Vector2(pos_data[0], pos_data[1])
	
	return Vector2.ZERO

func _move_player_to_marker(marker_name: String):
	const _fname : String = "_move_player_to_marker"
	"""Move player to specified marker position"""
	if cutscene_markers.has(marker_name):
		var player = GameState.get_player()
		if player:
			player.global_position = cutscene_markers[marker_name].global_position
			if debug: print(GameState.script_name_tag(self) + "Moved player to marker: ", marker_name)

func _start_cutscene_dialogue(cutscene_data: Dictionary):
	const _fname : String = "_start_cutscene_dialogue"
	"""Start the main cutscene dialogue"""
	var dialog_file = cutscene_data.get("dialog_file", "")
	if dialog_file == "":
		if debug: print(GameState.script_name_tag(self) + "No dialog file specified")
		return
	
	var dialog_system = get_node_or_null("/root/DialogSystem")
	if not dialog_system:
		print(GameState.script_name_tag(self) + "DialogSystem not found")
		return
	
	# Set reference to this cutscene
	active_cutscene = self  # This manager becomes the active cutscene controller
	
	# Start dialogue with optional title
	var dialog_title = cutscene_data.get("dialog_title", "")
	if dialog_title != "":
		dialog_system.start_dialog(dialog_file, dialog_title)
	else:
		dialog_system.start_dialog(dialog_file)
	
	# Connect to dialogue finished signal if available
	if dialog_system.has_signal("dialog_finished"):
		if not dialog_system.dialog_finished.is_connected(_on_cutscene_dialogue_finished):
			dialog_system.dialog_finished.connect(_on_cutscene_dialogue_finished)

func _find_z_objects_container() -> Node:
	const _fname : String = "_find_z_objects_container"
	"""Find the z_Objects container in the current scene"""
	var current_scene = get_tree().current_scene
	
	# Look for z_Objects directly
	var z_objects = current_scene.find_child("z_Objects", true, false)
	if z_objects:
		return z_objects
	
	# Look for Node2D with z_Objects child
	var main_node = current_scene.find_child("Node2D", true, false)
	if main_node:
		z_objects = main_node.find_child("z_Objects", true, false)
		if z_objects:
			return z_objects
	
	# Create z_Objects if it doesn't exist
	if main_node:
		z_objects = Node2D.new()
		z_objects.name = "z_Objects"
		z_objects.y_sort_enabled = true
		main_node.add_child(z_objects)
		if debug: print(GameState.script_name_tag(self) + "Created z_Objects container")
		return z_objects
	
	return null

func _on_cutscene_dialogue_finished():
	const _fname : String = "_on_cutscene_dialogue_finished"
	"""Called when cutscene dialogue ends"""
	if debug: print(GameState.script_name_tag(self) + "Cutscene dialogue finished")
	
	# Clean up temporary elements
	cleanup_active_cutscene()
	
	cutscene_finished.emit("")

func cleanup_active_cutscene():
	const _fname : String = "cleanup_active_cutscene"
	"""Clean up the currently active cutscene"""
	# Remove temporary NPCs
	for npc in active_cutscene_npcs:
		if is_instance_valid(npc):
			var is_temporary = true  # Default to temporary for runtime-spawned NPCs
			# You could store this info during spawning if needed
			if is_temporary:
				npc.queue_free()
	
	active_cutscene_npcs.clear()
	
	# Remove temporary props
	for prop in active_cutscene_props:
		if is_instance_valid(prop):
			prop.queue_free()
	
	active_cutscene_props.clear()
	
	# Remove runtime markers
	for marker_name in cutscene_markers:
		var marker = cutscene_markers[marker_name]
		if is_instance_valid(marker):
			marker.queue_free()
	
	cutscene_markers.clear()
	
	# Update GameState
	GameState.set_current_npcs()
	GameState.set_current_markers()
	
	active_cutscene = null

	# Restore player camera if a cutscene camera was left active
	if is_instance_valid(cutscene_camera):
		camera_restore(0.0)

	if debug: print(GameState.script_name_tag(self) + "Cutscene cleanup complete")

# Enhanced trigger function for easy calling
func trigger_cutscene_in_location(cutscene_id: String, location: String) -> bool:
	const _fname : String = "trigger_cutscene_in_location"
	"""Trigger a cutscene, but only if we're in the right location"""
	var cutscene_data = get_cutscene_data(cutscene_id)
	var required_location = cutscene_data.get("location", "")
	
	if required_location != "" and required_location != location:
		if debug: print(GameState.script_name_tag(self) + "Cutscene ", cutscene_id, " not triggered - wrong location (need: ", required_location, ", current: ", location, ")")
		return false
	
	return start_cutscene(cutscene_id)


func _physics_process(delta):
	const _fname : String = "_physics_process"
	# Check signal-follow arrivals
	var arrived : Array = []
	for npc_id in _signal_follow_targets:
		var data : Dictionary = _signal_follow_targets[npc_id]
		var npc : Node2D = data.npc
		var target : Node2D = data.target
		if not is_instance_valid(npc) or not is_instance_valid(target):
			arrived.append(npc_id)
			continue
		if npc.global_position.distance_to(target.global_position) <= data.distance:
			arrived.append(npc_id)
			caught_up.emit(npc, data.target_id)
			if debug: print(GameState.script_name_tag(self, _fname) + npc_id + " caught up to " + data.target_id)
	for npc_id in arrived:
		_signal_follow_targets.erase(npc_id)

	# Process ongoing movements
	var completed_movements = []
	
	for character_id in active_movements:
		var movement_data = active_movements[character_id]
		var character = movement_data.character
		
		if not is_instance_valid(character):
			# Try to re-fetch the character before giving up
			var refetched = GameState.get_player() if character_id == "player" else GameState.get_npc_by_id(character_id)
			if refetched and is_instance_valid(refetched):
				push_warning("CutsceneManager._physics_process: re-fetched stale reference for " + character_id)
				movement_data["character"] = refetched
				character = refetched
			else:
				push_warning("CutsceneManager._physics_process: character invalid and cannot re-fetch: " + character_id)
				completed_movements.append(character_id)
				continue
			
		# Process movement
		var finished = _process_movement(character_id, movement_data, delta)
		if finished:
			if debug: print(GameState.script_name_tag(self) + "Movement completed for: ", character_id)
			# Zero velocity so the character doesn't drift
			if "velocity" in character:
				character.velocity = Vector2.ZERO
			# Reset nav agent target to current position so is_navigation_finished()
			# returns true — prevents NPC _physics_process from overriding animations
			if character.has_node("NavigationAgent2D"):
				character.get_node("NavigationAgent2D").target_position = character.global_position
			# Release cutscene movement control back to the NPC
			if "is_cutscene_controlled" in character:
				character.is_cutscene_controlled = false
				if character.has_meta("pre_cutscene_collision_mask"):
					character.collision_mask = character.get_meta("pre_cutscene_collision_mask")
					character.remove_meta("pre_cutscene_collision_mask")
			completed_movements.append(character_id)
			movement_completed.emit(character_id)
	
	# Clean up completed movements
	for character_id in completed_movements:
		active_movements.erase(character_id)
	if not completed_movements.is_empty() and active_movements.is_empty():
		all_movements_completed.emit()

func _process_movement(character_id, movement_data, delta):
	const _fname : String = "_process_movement"
	var character = movement_data.character
	var target_position = movement_data.target_position
	var speed = movement_data.speed

	# Calculate direction and distance
	var direction = (target_position - character.global_position).normalized()
	var distance = character.global_position.distance_to(target_position)

	# Check if we're done
	var stop_distance = movement_data.get("stop_distance", 10.0)
	if distance <= stop_distance:
		if debug: print(GameState.script_name_tag(self, _fname) + "Reached destination")
		if "is_running" in character:
			character.is_running = false
		return true
	# Diagnostic: log first-frame movement attempt so we can confirm it's being processed
#	if debug: print(GameState.script_name_tag(self, _fname) + character_id + " moving: dist=" + str(distance) + " target=" + str(target_position) + " pos=" + str(character.global_position))

	var animation = movement_data.get("animation", "walk")

	if movement_data.get("use_navigation", false):
		# Drive the character along the nav agent path
		var nav_agent : NavigationAgent2D = character.get_node_or_null("NavigationAgent2D")
		if nav_agent and not nav_agent.is_navigation_finished():
			var next_pos : Vector2 = nav_agent.get_next_path_position()
			var nav_dir : Vector2 = character.global_position.direction_to(next_pos)
			character.velocity = nav_dir * speed
			character.move_and_slide()
			_update_animation(character, nav_dir, animation)
			return false

		# Nav agent has no path (no nav mesh, or finished early) — fall back to direct
		movement_data["use_navigation"] = false
		if debug: print(GameState.script_name_tag(self, _fname) + "Nav unavailable, switching to direct: ", character_id)

	# Direct line movement (no nav mesh, or player)
	if character.has_method("move_and_slide"):
		character.velocity = direction * speed
		character.move_and_slide()
	else:
		character.global_position += direction * speed * delta
	_update_animation(character, direction, animation)

	return false

func _update_animation(character, direction, animation_type):
	const _fname : String = "_update_animation"
	# Set the character's animation based on the movement direction
	var dir_string : String = ""
	if direction is Vector2:
		if abs(direction.x) > abs(direction.y):
			dir_string = "right" if direction.x > 0 else "left"
		else:
			dir_string = "down" if direction.y > 0 else "up"
	elif direction is String:
		dir_string = direction

	if character.has_method("play_animation"):
		character.play_animation(animation_type, dir_string)
	elif character.has_node("AnimationPlayer"):
		# Direct animation control
		var anim_player = character.get_node("AnimationPlayer")
		
		# Determine direction suffix
		var dir_suffix = ""
		if abs(direction.x) > abs(direction.y):
			dir_suffix = "_right" if direction.x > 0 else "_left"
		else:
			dir_suffix = "_down" if direction.y > 0 else "_up"
		
		# Try to play the animation
		var anim_name = animation_type + dir_suffix
		if anim_player.has_animation(anim_name):
			anim_player.play(anim_name)
		elif anim_player.has_animation(animation_type):
			anim_player.play(animation_type)

func move_character(character_id, target, animation="walk", speed=100, stop_distance=0, time=null, use_nav: bool = false):
	const _fname : String = "move_character"
	print(GameState.script_name_tag(self) + "MOVE CHARACTER CALLED: ", character_id, " to ", target)
	
	# Find the character node using GameState
	var character
	var game_state = GameState  # Direct reference to autoload
	
	if character_id == "player":
		character = game_state.get_player()
	else:
		character = game_state.get_npc_by_id(character_id)
	
	if not character:
		if debug: print(GameState.script_name_tag(self) + "ERROR: Character not found: ", character_id)
		return false
	
	if debug: print(GameState.script_name_tag(self) + "Found character: ", character)
	
	# Calculate target position
	var target_position = _determine_target_position(target)
	
	if target_position == Vector2.ZERO:
		if debug: print(GameState.script_name_tag(self) + "ERROR: Could not determine target position")
		return false
	
	if debug: print(GameState.script_name_tag(self) + "Target position: ", target_position)
	
	# Calculate speed
	var actual_speed = speed
	if time != null and time > 0:
		var distance = character.global_position.distance_to(target_position)
		actual_speed = distance / float(time)
	
	# Set up movement data
	var movement_data = {
		"character": character,
		"target_position": target_position,
		"speed": actual_speed,
		"animation": animation,
		"stop_distance": float(stop_distance),
		"use_navigation": use_nav
	}
	
	# Start the movement
	active_movements[character_id] = movement_data
	print(GameState.script_name_tag(self) + "Movement started for: ", character_id, " with data: ", movement_data)
	movement_started.emit(character_id, target_position)
	
	return true

func _determine_target_position(target):
	const _fname : String = "_determine_target_position"
	# Calculate target position based on different input types
	var game_state = GameState  # Direct reference to autoload
	
	if target is Vector2:
		return target
		
	if target is String:
		# If target is "player", find player position
		if target == "player":
			var player = game_state.get_player()
			return player.global_position if player else Vector2.ZERO

		# Check runtime cutscene markers first (keyed by plain name e.g. "P1")
		if cutscene_markers.has(target):
			return cutscene_markers[target].global_position

		# Check if target is another character
		var target_char = game_state.get_npc_by_id(target)
		if target_char:
			return target_char.global_position

		# Check if it's a scene-placed marker
		var marker = game_state.get_marker_by_id(target)
		if marker:
			return marker.global_position
	
	elif target is Node2D:
		return target.global_position
	
	# If we can't determine the position, return zero vector
	return Vector2.ZERO

func play_animation(character_id, animation_name, wait: bool = false):
	const _fname : String = "play_animation"
	if debug: print(GameState.script_name_tag(self) + "PLAY ANIMATION CALLED: ", character_id, " animation: ", animation_name)

	# Find the character node using GameState
	var character
	var game_state = GameState  # Direct reference to autoload

	if character_id == "player":
		character = game_state.get_player()
	else:
		var npcs = GameState.get_current_npcs()
		if debug: print(GameState.script_name_tag(self) + "Current NPCs:" + str(npcs))
		character = game_state.get_npc_by_id(character_id)

	if not character:
		if debug: print(GameState.script_name_tag(self) + "ERROR: Character not found for animation: ", character_id)
		return false

	if debug: print(GameState.script_name_tag(self) + "Found character for animation: ", character)

	# Try different animation methods
	if character.has_method("play_animation"):
		character.play_animation(animation_name)
		if debug: print(GameState.script_name_tag(self) + "Called play_animation method")
	elif character.has_method("set_animation"):
		character.set_animation(animation_name, Vector2.ZERO)
		if debug: print(GameState.script_name_tag(self) + "Called set_animation method")
	elif character.has_node("AnimationPlayer"):
		var anim_player = character.get_node("AnimationPlayer")
		if anim_player.has_animation(animation_name):
			anim_player.play(animation_name)
			if debug: print(GameState.script_name_tag(self) + "Played animation through AnimationPlayer")
		else:
			if debug: print(GameState.script_name_tag(self) + "Animation not found in AnimationPlayer: ", animation_name)

	# If wait=true, return the AnimationPlayer's animation_finished signal so
	# the dialogue can await it before moving to the next line.
	# Never await a looping animation — it never fires animation_finished.
	if wait:
		var ap : AnimationPlayer = character.get_node_or_null("AnimationPlayer")
		if ap:
			var current_anim : StringName = ap.current_animation
			if ap.get_animation(current_anim).loop_mode != Animation.LOOP_NONE:
				if debug: print(GameState.script_name_tag(self) + "Skipping wait — animation loops: ", animation_name)
				return true
			if debug: print(GameState.script_name_tag(self) + "Waiting for animation to finish: ", animation_name)
			return ap.animation_finished
		else:
			if debug: print(GameState.script_name_tag(self) + "No AnimationPlayer found for wait on: ", character_id)
	return true
	
	# Create a simple visual effect for simple sprites
	# Fixed: Use create_tween() method properly
	var tween = get_tree().create_tween()
	if animation_name == "jump" or animation_name == "jump_down":
		tween.tween_property(character, "position:y", character.position.y - 20, 0.2)
		tween.tween_property(character, "position:y", character.position.y, 0.2)
		if debug: print(GameState.script_name_tag(self) + "Created simple jump tween animation")
	else:
		tween.tween_property(character, "modulate", Color(1.5, 1.5, 1.5), 0.2)
		tween.tween_property(character, "modulate", Color(1, 1, 1), 0.2)
		if debug: print(GameState.script_name_tag(self) + "Created simple highlight tween animation")
	
	return true

func trigger_location_animation(anim_name: String) -> void:
	const _fname : String = "trigger_location_animation"
	var scene : Node = GameState.get_current_scene()
	if not scene:
		if debug: print(GameState.script_name_tag(self, _fname) + "No current scene found")
		return
	var ap : AnimationPlayer = scene.get_node_or_null("AnimationPlayer")
	if not ap:
		if debug: print(GameState.script_name_tag(self, _fname) + "No AnimationPlayer in current scene — skipping: " + anim_name)
		return
	if not ap.has_animation(anim_name):
		if debug: print(GameState.script_name_tag(self, _fname) + "Animation not found in scene: " + anim_name)
		return
	if debug: print(GameState.script_name_tag(self, _fname) + "Playing scene animation: " + anim_name)
	ap.play(anim_name)

func wait(seconds: float) -> Signal:
	const _fname : String = "wait"
	if debug: print(GameState.script_name_tag(self, _fname) + "Waiting for " + str(seconds) + " seconds")
	return get_tree().create_timer(seconds).timeout

func wait_for_movements():
	const _fname : String = "wait_for_movements"
	if debug: print(GameState.script_name_tag(self) + "Wait for movements called, active movements: ", active_movements.size())
	
	# If no movements, return immediately
	if active_movements.size() == 0:
		return true
	
	# Return the signal to await — fires when the last active movement finishes
	return all_movements_completed

func move_character_to_marker(character_id, marker_id, run=false):
	const _fname : String = "move_character_to_marker"
	if debug: print(GameState.script_name_tag(self) + "Moving character ", character_id, " to marker ", marker_id)
	
	# Find the character
	var character
	if character_id == "player":
		character = GameState.get_player()
	else:
		character = GameState.get_npc_by_id(character_id)
		
	if not character:
		if debug: print(GameState.script_name_tag(self) + "ERROR: Character not found: ", character_id)
		return false
	
	# Find the marker
	var marker = GameState.get_marker_by_id(marker_id)
	if not marker:
		if debug: print(GameState.script_name_tag(self) + "ERROR: Marker not found: ", marker_id)
		return false
	
	# Get target position
	var target_position = marker.global_position
	
	# Set up movement data
	var movement_data = {
		"character": character,
		"target": marker_id,  
		"target_position": target_position,  # Add this to match what _process_movement expects
		"speed": character.base_speed * (1.5 if run else 1.0),
		"animation": "run" if run else "walk",
		"stop_distance": 10.0,
		"is_navigating": true
	}
	
	# Start navigation
	var navigation_manager = get_node_or_null("/root/NavigationManager")
	if navigation_manager:
		navigation_manager.navigate_character(character, target_position, run)
	
	# Add to active movements
	active_movements[character_id] = movement_data
	
	# Emit signal
	movement_started.emit(character_id, marker_id)
	return true


func move_to(character_id: String, marker_id: String, mode: String = "walk", wait: bool = true):
	const _fname : String = "move_to"
	var actor
	if character_id == "player":
		actor = GameState.get_player()
	else:
		actor = GameState.get_npc_by_id(character_id)

	var target_pos : Vector2 = _determine_target_position(marker_id)

	if not actor:
		push_error("CutsceneManager.move_to: actor not found. id=" + character_id)
		return
	if target_pos == Vector2.ZERO:
		push_error("CutsceneManager.move_to: marker resolved to ZERO. marker=" + marker_id
			+ "  cutscene_markers has it: " + str(cutscene_markers.has(marker_id)))
		return

	# Set animation state before physics loop takes over
	if "is_running" in actor:
		actor.is_running = (mode == "run")

	# Clear follow behaviour and hand full movement control to CutsceneManager
	if "follow_target" in actor:
		actor.follow_target = null
	if "is_cutscene_controlled" in actor:
		actor.is_cutscene_controlled = true
		# Store collision mask and disable it so the NPC passes through the player
		if "collision_mask" in actor:
			actor.set_meta("pre_cutscene_collision_mask", actor.collision_mask)
			actor.collision_mask = 0

	# Use nav agent for NPCs so they path around obstacles; direct for player
	# (player physics is blocked during cutscenes so nav path is never consumed).
	var use_nav : bool = character_id != "player" and actor.get_node_or_null("NavigationAgent2D") != null
	if use_nav:
		# Point the nav agent at the target — CutsceneManager's _physics_process
		# will consume get_next_path_position() each frame (npc.gd is suspended).
		actor.get_node("NavigationAgent2D").target_position = target_pos

	var speed_mult : float = 2.0 if mode == "run" else 1.0
	var moved : bool = move_character(character_id, target_pos, mode,
		actor.base_speed * speed_mult, 10.0, null, use_nav)

	# move_character does a second get_npc_by_id lookup which can fail even when
	# we already have a valid actor reference.  Fall back to adding directly.
	if not moved:
		push_warning("CutsceneManager.move_to: move_character failed for '"
			+ character_id + "' — adding movement directly from actor reference")
		var movement_data : Dictionary = {
			"character": actor,
			"target_position": target_pos,
			"speed": actor.base_speed * speed_mult,
			"animation": mode,
			"stop_distance": 10.0,
			"use_navigation": use_nav
		}
		active_movements[character_id] = movement_data
		movement_started.emit(character_id, target_pos)

	if debug: print(GameState.script_name_tag(self, _fname) + "Moving " + character_id + " to " + marker_id + " [" + mode + "]")

	if wait:
		return movement_completed


## Start multiple movements simultaneously and wait for all to finish.
## character_ids and marker_ids are comma-separated strings, e.g.:
##   do CutsceneManager.move_group("guard1,guard2", "G1,G2", "walk")
func move_group(character_ids: String, marker_ids: String, mode: String = "walk"):
	const _fname : String = "move_group"
	var chars : PackedStringArray = character_ids.split(",")
	var markers : PackedStringArray = marker_ids.split(",")
	for i in range(min(chars.size(), markers.size())):
		move_to(chars[i].strip_edges(), markers[i].strip_edges(), mode, false)
	if active_movements.is_empty():
		return true
	return all_movements_completed


# ---------------------------------------------------------------------------
# Camera control
# ---------------------------------------------------------------------------

## Move the camera away from the player to focus on a target.
## target: Vector2, marker name string, or character_id string.
## duration: tween time in seconds (0 = instant).
## Returns a Signal you can await in a .dialogue do-statement.
func camera_move_to(target, duration: float = 1.0):
	const _fname : String = "camera_move_to"

	var player : Node2D = GameState.get_player()
	if not player:
		push_error("CutsceneManager.camera_move_to: player not found")
		return

	var player_cam : Camera2D = player.get_node_or_null("Camera2D")
	if not player_cam:
		push_error("CutsceneManager.camera_move_to: Camera2D not found on player")
		return

	# Resolve target position
	var dest : Vector2 = _determine_target_position(target)
	if dest == Vector2.ZERO:
		push_error("CutsceneManager.camera_move_to: could not resolve target: " + str(target))
		return

	# Spawn cutscene camera if not already active
	if not is_instance_valid(cutscene_camera):
		cutscene_camera = Camera2D.new()
		cutscene_camera.name = "CutsceneCamera"
		cutscene_camera.zoom         = player_cam.zoom
		cutscene_camera.limit_left   = player_cam.limit_left
		cutscene_camera.limit_right  = player_cam.limit_right
		cutscene_camera.limit_top    = player_cam.limit_top
		cutscene_camera.limit_bottom = player_cam.limit_bottom
		cutscene_camera.position_smoothing_enabled = false
		# Add to tree FIRST — global_position only works after the node is in the tree
		get_tree().current_scene.add_child(cutscene_camera)
		cutscene_camera.global_position = player_cam.get_screen_center_position()

	# Disable the player cam so it cannot compete
	player_cam.enabled = false
	cutscene_camera.enabled = true
	cutscene_camera.make_current()

	if debug: print(GameState.script_name_tag(self, _fname) + "Camera moving to: ", dest, " duration=", duration)

	if duration <= 0.0:
		cutscene_camera.global_position = dest
		return

	var tween : Tween = get_tree().create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(cutscene_camera, "global_position", dest, duration)
	return tween.finished


## Tween the cutscene camera back to the player camera position, then restore
## the player camera as current and free the cutscene camera.
## duration: tween time in seconds (0 = instant restore).
func camera_restore(duration: float = 0.5):
	const _fname : String = "camera_restore"

	if not is_instance_valid(cutscene_camera):
		if debug: print(GameState.script_name_tag(self, _fname) + "No cutscene camera to restore")
		return

	var player : Node2D = GameState.get_player()
	var player_cam : Camera2D = player.get_node_or_null("Camera2D") if player else null

	var _do_restore := func():
		if player_cam:
			player_cam.enabled = true
			player_cam.make_current()
		if is_instance_valid(cutscene_camera):
			cutscene_camera.queue_free()
			cutscene_camera = null
		if debug: print(GameState.script_name_tag(self, _fname) + "Player camera restored")

	if duration <= 0.0 or not player_cam:
		_do_restore.call()
		return

	if debug: print(GameState.script_name_tag(self, _fname) + "Restoring camera over ", duration, "s")

	var dest : Vector2 = player_cam.get_screen_center_position()
	var tween : Tween = get_tree().create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(cutscene_camera, "global_position", dest, duration)
	tween.tween_callback(_do_restore)
	return tween.finished


# ---------------------------------------------------------------------------
# Follow control
# ---------------------------------------------------------------------------

## Make an NPC follow a target. target_id: "player", another NPC id, or "" to stop.
## signal_stopped: if true, emits caught_up(npc_id, target_id) once within distance.
func set_npc_follow(npc_id: String, target_id: String, distance: float = 64.0, signal_stopped: bool = false):
	const _fname : String = "set_npc_follow"
	var npc : Node2D = GameState.get_npc_by_id(npc_id)
	if not npc:
		push_error("CutsceneManager.set_npc_follow: NPC not found: " + npc_id)
		return
	var target : Node2D = null
	if target_id == "player":
		target = GameState.get_player()
	elif target_id != "":
		target = GameState.get_npc_by_id(target_id)
	if "follow_target" in npc:
		npc.follow_target = target
	if "follow_distance" in npc:
		npc.follow_distance = distance
	if signal_stopped and target:
		print("setting _signal_follow_targets")
		_signal_follow_targets[npc_id] = {
			"npc": npc,
			"target": target,
			"target_id": target_id,
			"distance": distance
		}
	if debug: print(GameState.script_name_tag(self, _fname) + npc_id + " following: " + target_id)

## Stop an NPC from following.
func stop_npc_follow(npc_id: String):
	const _fname : String = "stop_npc_follow"
	var npc : Node2D = GameState.get_npc_by_id(npc_id)
	if not npc:
		return
	if "follow_target" in npc:
		npc.follow_target = null
	if debug: print(GameState.script_name_tag(self, _fname) + npc_id + " follow stopped")


func _on_navigation_completed(character):
	# Find which character completed navigation
	var character_id = ""
	for id in active_movements.keys():
		if active_movements[id].character == character:
			character_id = id
			break
	
	if character_id.is_empty():
		return
	
	# Mark movement as complete
	if debug: print(GameState.script_name_tag(self) + "Character ", character_id, " completed navigation")
	
	# Remove from active movements
	active_movements.erase(character_id)
	
	# Emit completion signal
	movement_completed.emit(character_id)

func queue_movement(character_id, marker_id, run=false):
	if not movement_queue.has(character_id):
		movement_queue[character_id] = []
	
	movement_queue[character_id].append({
		"marker_id": marker_id,
		"run": run
	})
	
	# Start processing the queue if not already processing
	if processing_movement_queue:
		call_deferred("_process_movement_queue")



# Cutscene Registry System
# Enhanced _load_cutscene_registry function - replace the existing one
func _load_cutscene_registry():
	"""Load cutscene registry from individual files in the cutscenes directory"""
	var cutscenes_dir = Paths.get_data_dir("cutscenes")
	stored_cutscenes.clear()
	
	if not DirAccess.dir_exists_absolute(cutscenes_dir):
		if debug: print(GameState.script_name_tag(self) + "Cutscenes directory not found: ", cutscenes_dir)
		_create_default_registry()
		return
	
	_scan_cutscene_directory(cutscenes_dir)
	
	if debug: print(GameState.script_name_tag(self) + "Loaded ", stored_cutscenes.size(), " cutscenes from individual files")
	
	
func _scan_cutscene_directory(dir_path: String):
	"""Recursively scan directory for cutscene files"""
	var dir = DirAccess.open(dir_path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		var full_path = dir_path + file_name
		
		if dir.current_is_dir():
			# Recursively scan subdirectories
			_scan_cutscene_directory(full_path + "/")
		elif file_name.begins_with("cs_") and file_name.ends_with(".json"):
			# Load cutscene file
			_load_cutscene_file(full_path, file_name)
		
		file_name = dir.get_next()
	
	#print(GameState.script_name_tag(self) + "stored_cutscenes: ", stored_cutscenes)

func _load_cutscene_file(file_path: String, file_name: String):
	"""Load a single cutscene file"""
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print(GameState.script_name_tag(self) + "Failed to open cutscene file: ", file_path)
		return
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print(GameState.script_name_tag(self) + "Failed to parse cutscene JSON: ", file_path, " - ", json.get_error_message())
		return
	
	var cutscene_data = json.data
	if not cutscene_data is Dictionary:
		print(GameState.script_name_tag(self) + "Cutscene file is not a valid dictionary: ", file_path)
		return
	
	# Extract cutscene_id from file name or data
	var cutscene_id = cutscene_data.get("cutscene_id", "")
	if cutscene_id == "":
		# Extract from filename: cs_dorm_intro.json -> dorm_intro
		cutscene_id = file_name.trim_prefix("cs_").trim_suffix(".json")
		cutscene_data["cutscene_id"] = cutscene_id
	
	# Store in registry
	stored_cutscenes[cutscene_id] = cutscene_data
	
	if debug: print(GameState.script_name_tag(self) + "Loaded cutscene: ", cutscene_id, " from ", file_path)

func save_cutscene(cutscene_id: String, cutscene_data: Dictionary):
	"""Save a cutscene to its individual file"""
	var location = cutscene_data.get("location", "unknown")
	var file_path = Paths.get_data_dir("cutscenes") + location + "/cs_" + cutscene_id + ".json"
	
	# Ensure directory exists
	var dir_path = file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.open("res://").make_dir_recursive(dir_path)
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		print(GameState.script_name_tag(self) + "Failed to save cutscene file: ", file_path)
		return false
	
	var json_string = JSON.stringify(cutscene_data, "\t")
	file.store_string(json_string)
	file.close()
	
	# Update in-memory registry
	stored_cutscenes[cutscene_id] = cutscene_data
	
	if debug: print(GameState.script_name_tag(self) + "Saved cutscene: ", cutscene_id, " to ", file_path)
	return true

func _create_default_registry():
	"""Create a default cutscene registry"""
	var default_cutscenes = {
		"lab_meeting": {
			"scene_path": Paths.get_cutscene("lab_meeting"),
			"dialog_file": "lab_meeting_dialogue",
			"location": "research_lab",
			"description": "Meeting with the research team",
			"triggers": ["research_started"],
			"unlocks": ["met_research_team"]
		}
	}
	
	stored_cutscenes = default_cutscenes
	save_cutscene_registry()

func save_cutscene_registry():
	"""Save the current cutscene registry to file"""
	var registry_path = Paths.get_data_dir("cutscene_registry")
	
	# Ensure directory exists
	if not DirAccess.dir_exists_absolute("res://data/"):
		DirAccess.open("res://").make_dir("data")
	
	var file = FileAccess.open(registry_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(stored_cutscenes, "\t")
		file.store_string(json_string)
		file.close()
		if debug: print(GameState.script_name_tag(self) + "Saved cutscene registry")

# Cutscene Management Functions
func register_cutscene(cutscene_id: String, cutscene_data: Dictionary):
	"""Register a new cutscene in the system"""
	stored_cutscenes[cutscene_id] = cutscene_data
	save_cutscene_registry()
	if debug: print(GameState.script_name_tag(self) + "Registered cutscene: ", cutscene_id)

func get_cutscene_data(cutscene_id: String) -> Dictionary:
	"""Get cutscene data by ID"""
	return stored_cutscenes.get(cutscene_id, {})

func cutscene_exists(cutscene_id: String) -> bool:
	"""Check if a cutscene exists in the registry"""
	return cutscene_id in stored_cutscenes

func get_cutscenes_for_location(location: String) -> Array:
	"""Get all cutscenes available for a specific location"""
	var location_cutscenes = []
	for cutscene_id in stored_cutscenes:
		var data = stored_cutscenes[cutscene_id]
		if data.get("location", "") == location:
			location_cutscenes.append(cutscene_id)
	return location_cutscenes

func can_trigger_cutscene(cutscene_id: String) -> bool:
	"""Check if a cutscene can be triggered based on game state"""
	var cutscene_data = get_cutscene_data(cutscene_id)
	if cutscene_data.is_empty():
		return false
	
	# Check trigger conditions
	var triggers = cutscene_data.get("triggers", [])
	for trigger in triggers:
		if not GameState.is_known(trigger):
			return false
	
	# Check if already seen (if it's a one-time cutscene)
	var one_time = cutscene_data.get("one_time", true)
	if one_time and GameState.is_known("cutscene_seen_" + cutscene_id):
		return false
	
	return true



func _get_cached_cutscene_scene(scene_path: String) -> PackedScene:
	"""Get a cutscene scene from cache or load it"""
	if scene_path in cutscene_scene_cache:
		return cutscene_scene_cache[scene_path]
	
	if ResourceLoader.exists(scene_path):
		var scene = load(scene_path)
		cutscene_scene_cache[scene_path] = scene
		return scene
	
	return null

func _on_cutscene_finished(cutscene_id: String):
	"""Called when a cutscene finishes"""
	if debug: print(GameState.script_name_tag(self) + "Cutscene finished: ", cutscene_id)
	
	# Clean up active cutscene
	if is_instance_valid(active_cutscene):
		active_cutscene.queue_free()
		active_cutscene = null
	
	cutscene_finished.emit(cutscene_id)

func stop_active_cutscene():
	"""Stop the currently active cutscene"""
	if is_instance_valid(active_cutscene):
		if active_cutscene.has_method("cleanup_cutscene"):
			active_cutscene.cleanup_cutscene()
		active_cutscene.queue_free()
		active_cutscene = null

# Auto-trigger system
func check_location_cutscenes(location: String):
	"""Check and potentially trigger cutscenes for a location"""
	var location_cutscenes = get_cutscenes_for_location(location)
	
	for cutscene_id in location_cutscenes:
		var cutscene_data = get_cutscene_data(cutscene_id)
		var auto_trigger = cutscene_data.get("auto_trigger", false)
		
		if auto_trigger and can_trigger_cutscene(cutscene_id):
			if debug: print(GameState.script_name_tag(self) + "Auto-triggering cutscene: ", cutscene_id)
			start_cutscene(cutscene_id)
			break  # Only trigger one auto cutscene at a time

# Helper function for dialogue system
func trigger_cutscene_by_dialogue(cutscene_id: String):
	"""Trigger a cutscene from dialogue mutation"""
	return start_cutscene(cutscene_id)

# Development/Debug functions
func list_all_cutscenes() -> Array:
	"""Get list of all registered cutscenes"""
	return stored_cutscenes.keys()

func validate_cutscene_registry() -> Dictionary:
	"""Validate all cutscenes in the registry"""
	var validation_results = {}
	
	for cutscene_id in stored_cutscenes:
		var cutscene_data = stored_cutscenes[cutscene_id]
		var errors = []
		
		# Check scene path
		var scene_path = cutscene_data.get("scene_path", "")
		if scene_path == "":
			errors.append("Missing scene_path")
		elif not ResourceLoader.exists(scene_path):
			errors.append("Scene file not found: " + scene_path)
		
		# Check dialog file
		var dialog_file = cutscene_data.get("dialog_file", "")
		if dialog_file == "":
			errors.append("Missing dialog_file")
		elif not ResourceLoader.exists("res://dialogue/" + dialog_file + ".dialogue"):
			errors.append("Dialog file not found: " + dialog_file)
		
		validation_results[cutscene_id] = {
			"valid": errors.is_empty(),
			"errors": errors
		}
	
	return validation_results

func clear_cutscene_cache():
	"""Clear the cutscene scene cache"""
	cutscene_scene_cache.clear()
	if debug: print(GameState.script_name_tag(self) + "Cleared cutscene cache")

# Quick setup functions for common cutscene patterns
func create_simple_cutscene(cutscene_id: String, location: String, dialog_file: String, triggers: Array = [], unlocks: Array = []):
	"""Quick function to create a simple cutscene entry"""
	var cutscene_data = {
		"scene_path": "res://scenes/cutscenes/" + cutscene_id + "_cutscene.tscn",  # Dynamic path, not in Paths registry
		"dialog_file": dialog_file,
		"location": location,
		"description": "Auto-generated cutscene",
		"triggers": triggers,
		"unlocks": unlocks,
		"one_time": true,
		"auto_trigger": false
	}
	
	register_cutscene(cutscene_id, cutscene_data)
	return cutscene_data
	

# Cutscene Execution Functions
func start_cutscene_original(cutscene_id: String) -> bool:
	"""Start a cutscene by ID - creates a cutscene controller in the current scene"""
	if not can_trigger_cutscene(cutscene_id):
		if debug: print(GameState.script_name_tag(self) + "Cannot trigger cutscene: ", cutscene_id)
		return false
	
	var cutscene_data = get_cutscene_data(cutscene_id)
	if cutscene_data.is_empty():
		if debug: print(GameState.script_name_tag(self) + "Cutscene data not found: ", cutscene_id)
		return false
	
	# Create a cutscene controller node directly in the current scene
	var cutscene_scene = load(Paths.get_cutscene("base"))
	if not cutscene_scene:
		if debug: print(GameState.script_name_tag(self) + "Failed to load base cutscene scene")
		return false
	
	# Instance the cutscene controller
	active_cutscene = cutscene_scene.instantiate()
	active_cutscene.cutscene_id = cutscene_id
	
	# Add to current scene
	var current_scene = get_tree().current_scene
	current_scene.add_child(active_cutscene)
	
	# Connect signals
	if active_cutscene.has_signal("cutscene_finished"):
		active_cutscene.cutscene_finished.connect(_on_cutscene_finished.bind(cutscene_id))
	
	# The cutscene will auto-load its data and start
	# (since it loads data in _ready() based on cutscene_id)
	
	# Mark as seen
	GameState.unlock_tag("cutscene_seen_" + cutscene_id)
	
	# Unlock tags
	var unlocks = cutscene_data.get("unlocks", [])
	for unlock_tag in unlocks:
		GameState.unlock_tag(unlock_tag)
	
	cutscene_started.emit(cutscene_id)
	if debug: print(GameState.script_name_tag(self) + "Started cutscene: ", cutscene_id)
	return true

func face_to(actor, target):
	const _fname = "face_to"
	if debug: print(GameState.script_name_tag(self, _fname) + "function called")
	var cur_actor : CharacterBase
	var cur_target
	if actor is CharacterBase:
		cur_actor = actor
	else:
		if actor == "player":
			cur_actor = GameState.get_player()
		else:
			cur_actor = GameState.get_npc_by_id(actor)
	if typeof(target) == typeof(Vector2(1.2,2.3)):
		cur_target = Node2D.new()
		cur_target.set_global_position(target)
	elif typeof(target) == typeof("target"):
		if target == "player":
			cur_target = GameState.get_player()
		else:
			cur_target = GameState.get_npc_by_id(actor)
	else:
		cur_target = target

	cur_actor.face_target(cur_target)
		
		
		
