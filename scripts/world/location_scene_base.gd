class_name LocationSceneBase
extends Node2D

const location_scene : bool = true
var debug : bool = false
var location_id : String = ""

var visit_areas : Dictionary = {}
var all_areas_visited : bool = false
var cutscene_triggers : Dictionary = {}

var camera_limit_right  : float = 1200.0
var camera_limit_bottom : float = 800.0
var camera_limit_left   : float = 20.0
var camera_limit_top    : float = 20.0
var zoom_factor         : float = 1.5

@onready var z_objects = $Node2D/z_Objects
@onready var player = z_objects.get_node_or_null("Player")

func _ready() -> void:
	debug = GameController.sys_debug
	_on_scene_ready()
	if debug: DebugManager.print_debug_auto(self, location_id + " scene initialized")
	setup_player()
	setup_items()
	initialize_systems()
	setup_visit_areas()
	GameState.safe_connect(CutsceneManager, "caught_up", Callable(self, "_on_npc_caught_up"))

	await get_tree().create_timer(0.2).timeout
	var quest_system := get_node_or_null("/root/QuestSystem")
	if quest_system and quest_system.has_method("on_location_entered") and location_id != "":
		quest_system.on_location_entered(location_id)
		if debug: DebugManager.print_debug_auto(self, "Notified quest system of location: " + location_id)
	_on_scene_post_ready()

## Override to set location_id, camera limits, cutscene_triggers, and any
## scene-specific init that must run before common setup.
func _on_scene_ready() -> void:
	pass

## Override to run logic after the 0.2s settle delay (e.g. auto-start a cutscene).
func _on_scene_post_ready() -> void:
	pass

func setup_player() -> void:
	if not player:
		DebugManager.print_error_auto(self, "Player not found in scene")
		return
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var event := InputEventKey.new()
		event.keycode = KEY_E
		InputMap.action_add_event("interact", event)

func setup_items() -> void:
	pass

func initialize_systems() -> void:
	if debug and not get_node_or_null("/root/DialogSystem"):
		DebugManager.print_warning_auto(self, "Dialog System not found")

func setup_visit_areas() -> void:
	var areas := get_tree().get_nodes_in_group("visitable_area")
	if debug: DebugManager.print_debug_auto(self, "Found " + str(areas.size()) + " visitable areas")
	for area in areas:
		visit_areas[area.name] = {"visited": false, "area": area}
		if not area.body_entered.is_connected(_on_visit_area_entered):
			area.body_entered.connect(_on_visit_area_entered.bind(area.name))

func _on_visit_area_entered(body: Node2D, area_name: String) -> void:
	if not body.is_in_group("player"):
		return
	if visit_areas.has(area_name) and visit_areas[area_name].visited:
		return
	if visit_areas.has(area_name):
		visit_areas[area_name].visited = true
	if cutscene_triggers.has(area_name):
		var cutscene_id : String = cutscene_triggers[area_name]
		if debug: DebugManager.print_debug_auto(self, "Triggering cutscene: " + cutscene_id)
		CutsceneManager.start_cutscene(cutscene_id)

func _on_npc_caught_up(npc: Node2D, target_id: String) -> void:
	if debug: DebugManager.print_debug_auto(self, str(npc.name) + " caught up to " + target_id)
	var target_npc : Node2D = GameState.get_npc_by_id(target_id)
	if target_npc:
		if "follow_target" in target_npc:
			target_npc.follow_target = null
		if "velocity" in target_npc:
			target_npc.velocity = Vector2.ZERO
		if target_npc.has_node("NavigationAgent2D"):
			target_npc.get_node("NavigationAgent2D").target_position = target_npc.global_position
	if is_instance_valid(npc) and npc.has_method("interact"):
		DialogSystem.start_dialog(npc, "start")
		npc.interact()
