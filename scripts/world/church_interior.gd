extends Node2D

# Church Interior scene script
const location_scene : bool = true

const scr_debug : bool = false
var debug

var visit_areas = {}
var all_areas_visited = false
var bailey_follow : bool = true
# Maps area names (from the "visitable_area" group) to cutscene IDs.
# The cutscene must have a matching cs_<id>.json in data/cutscenes/church_interior/.
var cutscene_triggers : Dictionary = {
	"CutsceneTrigger": "church_intro"
}

var camera_limit_right  = 1200
var camera_limit_bottom = 800
var camera_limit_left   = 20
var camera_limit_top    = 20
var zoom_factor         = 1.5

@onready var z_objects = $Node2D/z_Objects
@onready var player    = z_objects.get_node_or_null("Player")

func _ready():
	const _fname = "_ready"
	debug = scr_debug or GameController.sys_debug

	if debug: print(GameState.script_name_tag(self, _fname) + "Church Interior scene initialized")
	
	setup_player()
	setup_items()
	initialize_systems()
	setup_visit_areas()

	await get_tree().create_timer(0.2).timeout
	var quest_system = get_node_or_null("/root/QuestSystem")
	if quest_system and quest_system.has_method("on_location_entered"):
		quest_system.on_location_entered("church_interior")
		if debug: print(GameState.script_name_tag(self, _fname) + "Notified quest system of location: church_interior")

func setup_player():
	const _fname = "setup_player"
	if player:
		if debug: print(GameState.script_name_tag(self, _fname) + "Player found in scene")
		if not InputMap.has_action("interact"):
			InputMap.add_action("interact")
			var event = InputEventKey.new()
			event.keycode = KEY_E
			InputMap.action_add_event("interact", event)
	else:
		if debug: print(GameState.script_name_tag(self, _fname) + "ERROR: Player not found in scene!")

func setup_visit_areas():
	const _fname = "setup_visit_areas"
	var areas = get_tree().get_nodes_in_group("visitable_area")
	if debug: print(GameState.script_name_tag(self, _fname) + "Found " + str(areas.size()) + " visitable areas")

	for area in areas:
		visit_areas[area.name] = { "visited": false, "area": area }
		if not area.body_entered.is_connected(_on_visit_area_entered):
			area.body_entered.connect(_on_visit_area_entered.bind(area.name))

func setup_items():
	pass

func initialize_systems():
	const _fname = "initialize_systems"
	var dialog_system = get_node_or_null("/root/DialogSystem")
	if dialog_system:
		if debug: print(GameState.script_name_tag(self, _fname) + "Dialog System found")
	else:
		if debug: print(GameState.script_name_tag(self, _fname) + "WARNING: Dialog System not found")

func _on_visit_area_entered(body, area_name: String):
	const _fname = "_on_visit_area_entered"
	if not body.is_in_group("player"):
		return

	if debug: print(GameState.script_name_tag(self, _fname) + "Player entered area: " + area_name)

	# One-time guard — don't re-trigger an area the player has already visited
	if visit_areas.has(area_name) and visit_areas[area_name].visited:
		return
	if visit_areas.has(area_name):
		visit_areas[area_name].visited = true

	# Fire cutscene if this area has one mapped
	if cutscene_triggers.has(area_name):
		var cutscene_id : String = cutscene_triggers[area_name]
		if debug: print(GameState.script_name_tag(self, _fname) + "Triggering cutscene: " + cutscene_id)
		CutsceneManager.start_cutscene(cutscene_id)
