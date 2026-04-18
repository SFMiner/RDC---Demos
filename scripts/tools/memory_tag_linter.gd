extends Node
class_name MemoryTagLinter

# Data structures to hold parsed information
var memory_tags = {}  # tag_name -> {file: "", step_id: "", description: ""}
var dialogue_tag_checks = {}  # tag_name -> [file_paths...]
var dialogue_tag_sets = {}  # tag_name -> [file_paths...]
var character_features = {}  # feature_id -> {character: "", target_id: "", memory_tag: ""}
var look_at_targets = {}  # target_id -> {file: "", step_id: "", description: ""}

# File paths
const MEMORY_DIR = "res://data/memories/"
const DIALOGUE_DIR = "res://data/dialogues/"
const CHARACTER_DIR = "res://data/characters/"
const QUEST_DIR = "res://data/quests/"
const MEMORY_SCAN_DIRS := [MEMORY_DIR, CHARACTER_DIR]
const ALL_DATA_DIRS := [MEMORY_DIR, CHARACTER_DIR, DIALOGUE_DIR, QUEST_DIR]

const scr_debug : bool = false
var debug 

func _ready():
	debug = scr_debug or GameController.sys_debug

func _run():
