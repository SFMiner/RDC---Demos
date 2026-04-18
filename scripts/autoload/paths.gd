extends Node

# Centralized path constants
# Prevents hardcoded paths throughout the codebase

const SCENES = {
	"main_menu": "res://scenes/main_menu.tscn",
	"game": "res://scenes/game.tscn",
	"church_interior": "res://scenes/world/locations/church_interior.tscn"
}

const UI = {
	"inventory_panel": "res://scenes/ui/inventory_panel.tscn",
	"quest_panel": "res://scenes/ui/quest_panel.tscn",
	"pause_menu": "res://scenes/ui/pause_menu.tscn",
	"dialogue_balloon": "res://scenes/ui/dialogue_balloon.tscn",
	"encounter_dialogue_balloon": "res://scenes/ui/dialogue_balloon/encounter_dialogue_balloon.tscn",
	"custom_dialogue_balloon": "res://scenes/ui/dialogue_balloon/dialogue_balloon.tscn",
	"example_balloon": "res://addons/dialogue_manager/example_balloon/example_balloon.tscn"
}

const DATA = {
	"items": "res://data/items/",
	"quests": "res://data/quests/",
	"dialogues": "res://data/dialogues/",
	"memories": "res://data/memories/",
	"characters": "res://data/characters/",
	"cutscenes": "res://data/cutscenes/",
	"cutscene_registry": "res://data/cutscene_registry.json",
	"generated": "res://data/generated/"
}

const SCRIPTS = {
	"player": "res://scripts/world/player.gd",
	"npc": "res://scripts/world/npc.gd"
}

const CUTSCENES = {
	"base": "res://scenes/cutscene.tscn"
}

# Helper function to get scene path
func get_scene(scene_id: String) -> String:
	if scene_id in SCENES:
		return SCENES[scene_id]
	push_warning("Unknown scene ID: " + scene_id)
	return ""

# Helper function to get UI path
func get_ui(ui_id: String) -> String:
	if ui_id in UI:
		return UI[ui_id]
	push_warning("Unknown UI ID: " + ui_id)
	return ""

# Helper function to get data directory
func get_data_dir(data_type: String) -> String:
	if data_type in DATA:
		return DATA[data_type]
	push_warning("Unknown data type: " + data_type)
	return ""

# Helper function to get cutscene path
func get_cutscene(cutscene_id: String) -> String:
	if cutscene_id in CUTSCENES:
		return CUTSCENES[cutscene_id]
	push_warning("Unknown cutscene ID: " + cutscene_id)
	return ""
