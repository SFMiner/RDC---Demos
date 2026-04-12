extends Node2D

# Campus Quad scene script
# Initializes the level and manages scene-specific logic
const location_scene :bool = true

const scr_debug :bool = false
var debug
var scene_item_num : int = 0
var visit_areas = {}
var all_areas_visited = false
var camera_limit_right = 3050	
var camera_limit_bottom = 3050
var camera_limit_left = 0
var camera_limit_top = 0
var zoom_factor = 1
@onready var player = GameState.get_player()
@onready var camera = get_node_or_null("Camerad2D")
@onready var z_objects = get_node_or_null("Node2D/z_Objects") 
@onready var professor_moss = z_objects.get_node_or_null("ProfessorMoss")

func _ready():
	const _fname : String = "_ready"
	var debug_label = $Node2D/CanvasLayer/GameInfo
	debug = scr_debug or GameController.sys_debug 
	GameState.set_current_scene(self)
	if debug: print(GameState.script_name_tag(self) + "loaded scene")
	player = GameState.get_player()
	GameState.set_tag("left_dorm")
	if debug:
		if debug_label:
			if player and player.interactable_object:
				debug_label.text = "Love & Lichens - Demo\nUse WASD or arrow keys to move\nPress E or Space to interact with NPCs\n\nCan interact with: " + player.interactable_object.name
			else:
				debug_label.text = "Love & Lichens - Demo\nUse WASD or arrow keys to move\nPress E or Space to interact with NPCs\n\nNo interactable object nearby"
				

	print(GameState.script_name_tag(self) + "Campus Quad scene initialized")
	# Set up the scene components
	setup_player()
	setup_npcs()
	setup_items()
	
	# Initialize necessary systems
	initialize_systems()
	
	# Find and set up visitable areas
	setup_visit_areas()
	
	# Notify quest system that player is in campus quad
	await get_tree().create_timer(0.2).timeout
	var quest_system = get_node_or_null("/root/QuestSystem")
	if quest_system and quest_system.has_method("on_location_entered"):
		quest_system.on_location_entered("campus_quad")
		if debug:print(GameState.script_name_tag(self) + "Notified quest system of location: campus_quad")


func setup_player():
	if player:
		if debug: print(GameState.script_name_tag(self) + "Player found in scene")
		# Make sure the player's input settings are correct
		if not InputMap.has_action("interact"):
			print(GameState.script_name_tag(self) + "Adding 'interact' action to InputMap")
			InputMap.add_action("interact")
			var event = InputEventKey.new()
			event.keycode = KEY_E
			InputMap.action_add_event("interact", event)
		else:
			if debug: print(GameState.script_name_tag(self) + "'interact' action already exists in InputMap")
	else:
		if debug: print(GameState.script_name_tag(self) + "ERROR: Player not found in scene!")

func setup_visit_areas():
	# Find all Area2D nodes in the "visitable_area" group
	var areas = get_tree().get_nodes_in_group("visitable_area")
	if debug: print(GameState.script_name_tag(self) + "Found " + str(areas.size()) + " visitable areas in the scene")
	
	# Set up tracking for each area
	for area in areas:
		# Store the area in our tracking dict
		visit_areas[area.name] = {
			"visited": false,
			"area": area
		}
		
		# Connect the body_entered signal if not already connected
		if not area.body_entered.is_connected(_on_visit_area_entered):
			area.body_entered.connect(_on_visit_area_entered.bind(area.name))

func setup_npcs():
	# Setup Professor Moss
	if professor_moss:
		if debug: print(GameState.script_name_tag(self) + "Professor Moss found in scene")
		# Ensure Professor Moss has the correct collision settings
		if professor_moss.get_collision_layer() != 2:
			if debug: print(GameState.script_name_tag(self) + "Setting Professor Moss collision layer to 2")
			professor_moss.set_collision_layer(2)
	else:
		if debug: print(GameState.script_name_tag(self) + "ERROR: Professor Moss not found in scene!")
	
	# Find and setup all NPCs
	var npcs = get_tree().get_nodes_in_group("interactable")
	if debug: print(GameState.script_name_tag(self) + "Found ", npcs.size(), " interactable NPCs in scene")

func setup_items():
	pass
	#var interactables = get_tree().get_nodes_in_group("interactable")
	# Placeholder for interactable setup
				 
func initialize_systems():
	# Get references to necessary systems
	var dialog_system = get_node_or_null("/root/DialogSystem")
	var relationship_system = get_node_or_null("/root/RelationshipSystem")
	
	if dialog_system:
		if debug: print(GameState.script_name_tag(self) + "Dialog System found")
	else:
		if debug: print(GameState.script_name_tag(self) + "WARNING: Dialog System not found! Adding a temporary one.")
		var new_dialog_system = Node.new()
		new_dialog_system.name = "DialogSystem"
		new_dialog_system.set_script(load("res://scripts/systems/dialog_system.gd"))
		get_tree().root.add_child(new_dialog_system)
	
	if relationship_system:
		if debug: print(GameState.script_name_tag(self) + "Relationship System found")
		
		# Initialize relationship with Professor Moss if needed
		if not relationship_system.relationships.has("professor_moss"):
			if debug: print(GameState.script_name_tag(self) + "Initializing relationship with Professor Moss")
			relationship_system.initialize_relationship("professor_moss", "Professor Moss")
	else:
		if debug: print(GameState.script_name_tag(self) + "WARNING: Relationship System not found")

func _on_visit_area_entered(body, area_name):
	if not body.is_in_group("player"):
		return
		
	if debug: print(GameState.script_name_tag(self) + "Player entered area: " + area_name)
	
	# Mark as visited
	if visit_areas.has(area_name):
		# If already visited, no need to process again
		if visit_areas[area_name].visited:
			if debug: print(GameState.script_name_tag(self) + "Area already visited: " + area_name)
			return
			
		visit_areas[area_name].visited = true
		if debug: print(GameState.script_name_tag(self) + "Marked area as visited: " + area_name)
		
		# Change visual indicator to show it's been visited
		var area = visit_areas[area_name].area
		var indicator = area.find_child("VisualIndicator") # Name your ColorRect or Sprite2D this
		if indicator:
			if indicator is ColorRect:
				indicator.color = Color(0.0, 1.0, 0.0, 0.5) # Change to green
			elif indicator is Sprite2D:
				indicator.modulate = Color(0.0, 1.0, 0.0, 0.5)
		
		# Check if we've visited all areas
		var all_visited = check_all_areas_visited()
		if debug: print(GameState.script_name_tag(self) + "All areas visited: ", all_visited)
		
		# Notify quest system
		var quest_system = get_node_or_null("/root/QuestSystem")
		if quest_system:
			if quest_system.has_method("on_area_visited"):
				if debug: print(GameState.script_name_tag(self) + "Calling quest_system.on_area_visited with ", area_name, " and campus_quad")
				quest_system.on_area_visited(area_name, "campus_quad")
				
			# If all areas visited, also notify for a complete exploration
			if all_visited and quest_system.has_method("on_area_exploration_completed"):
				if debug: print(GameState.script_name_tag(self) + "Calling quest_system.on_area_exploration_completed with campus_quad")
				quest_system.on_area_exploration_completed("campus_quad")

func check_all_areas_visited():
	# Return early if we already know all areas are visited
	if all_areas_visited:
		return true
		
	for area_name in visit_areas:
		if not visit_areas[area_name].visited:
			return false
	
	# If we get here, all areas have been visited
	all_areas_visited = true
	if debug: print(GameState.script_name_tag(self) + "All areas in campus quad have been visited!")
	return true
	
