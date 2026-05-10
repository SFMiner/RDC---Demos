class_name DialogueBalloon extends CanvasLayer
## A basic dialogue balloon for use with Dialogue Manager.

## The action to use for advancing the dialogue
@export var next_action: StringName = &"ui_accept"

## The action to use to skip typing the dialogue
@export var skip_action: StringName = &"ui_cancel"

## The dialogue resource
var resource: DialogueResource
## Temporary game states
var temporary_game_states: Array = []

## See if we are waiting for the player
var is_waiting_for_input: bool = false

## See if we are running a long mutation and should hide the balloon
var will_hide_balloon: bool = false

## A dictionary to store any ephemeral variables
var locals: Dictionary = {}

var _locale: String = TranslationServer.get_locale()

## The current line
var dialogue_line: DialogueLine:
	set(value):
		if value:
			dialogue_line = value
			apply_dialogue_line()
		else:
			# The dialogue has finished so close the balloon
			queue_free()
	get:
		return dialogue_line

## A cooldown timer for delaying the balloon hide when encountering a mutation.
var mutation_cooldown: Timer = Timer.new()

## The base balloon anchor
@onready var balloon: Control = %Balloon

## The label showing the name of the currently speaking character
@onready var character_label: RichTextLabel = %CharacterLabel

## The label showing the currently spoken dialogue
@onready var dialogue_label: DialogueLabel = %DialogueLabel

## The menu of responses
@onready var responses_menu: DialogueResponsesMenu = %ResponsesMenu

# Character font and styling dictionaries
var character_fonts = {}
var character_colors = {}
var character_font_sizes = {}

# Store references to loaded fonts to avoid reloading
var loaded_fonts = {}

const scr_debug :bool = false
var debug

const BALLOON_WIDTH  : float = 320.0
const BALLOON_MARGIN : float = 16.0

var _current_speaker : Node2D = null  # set during font application, used for positioning

func _ready() -> void:
	var _fname = "_ready"
	debug = scr_debug or GameController.sys_debug
	balloon.hide()
	DialogueManager.mutated.connect(_on_mutated)

	# If the responses menu doesn't have a next action set, use this one
	if responses_menu.next_action.is_empty():
		responses_menu.next_action = next_action

	# Set up default font as fallback
	var default_font_path = "res://assets/fonts/System/FantasticBoogaloo-GDlq.ttf"
	if ResourceLoader.exists(default_font_path):
		loaded_fonts["Default"] = load(default_font_path)
	
	mutation_cooldown.timeout.connect(_on_mutation_cooldown_timeout)
	add_child(mutation_cooldown)


# Enhanced character name extraction and font application
func _on_dialogue_line_started(dialogue_line: DialogueLine):
	var _fname = "_on_dialogue_line_started"
	
	# Extract character name with multiple fallback methods
	var character_name = ""
	
	# Method 1: Use dialogue_line.character if available
	if dialogue_line.character and not dialogue_line.character.is_empty():
		character_name = dialogue_line.character
		if debug: print(GameState.script_name_tag(self, _fname) + "Character from dialogue_line.character: '", character_name, "'")
	
	# Method 2: Extract from dialogue text if character field is empty
	if character_name.is_empty() and ":" in dialogue_line.text:
		character_name = dialogue_line.text.split(":")[0].strip_edges()
		if debug: print(GameState.script_name_tag(self, _fname) + "Character extracted from text: '", character_name, "'")
	
	# Method 3: Use current character ID from dialog system as fallback
	if character_name.is_empty():
		var dialog_system = get_node_or_null("/root/DialogSystem")
		if dialog_system and dialog_system.current_character_id != "":
			character_name = dialog_system.current_character_id
			if debug: print(GameState.script_name_tag(self, _fname) + "Character from dialog system: '", character_name, "'")
	
	if character_name.is_empty():
		character_name = "Default"
		if debug: print(GameState.script_name_tag(self, _fname) + "No character found, using Default")
	
	# Apply the appropriate font
	apply_font_for_character(character_name)

# Enhanced font application with better character matching
func apply_font_for_character(character_name: String):
	var _fname = "apply_font_for_character"
	if not dialogue_label:
		if debug: print(GameState.script_name_tag(self, _fname) + "No dialogue label available")
		return

	var character_id = character_name.to_lower().replace(" ","_")

	# Handle character name aliases
	if character_id == "inquisitor" or character_id == "inquisitor_malachai":
		character_id = "malachai"

	if debug: print(GameState.script_name_tag(self, _fname) + "Applying font for character: '", character_name, "' with character_id '" + character_id + "'")

	var character = GameState.get_npc_by_id(character_id)
	if not is_instance_valid(character):
		# Speaker is not an NPC — check if it's the player character
		var player = GameState.get_player()
		if is_instance_valid(player):
			var pid : String = player.character_id if "character_id" in player else ""
			if pid == character_id or character_id == "player":
				character = player
	_current_speaker = character  # store for balloon positioning

	# Default values
	var font_to_use = loaded_fonts.get("Default")
	var font_bold_to_use : Font = null
	var font_italic_to_use : Font = null
	var font_bold_italic_to_use : Font = null
	var color_to_use = Color(1, 1, 1, 1)  # Default white
	var font_size = 25  # Default font size

	if character and "font_path" in character:
		# NPC node with font properties directly on it
		if character.font_path:
			font_to_use = load(character.font_path)
		if "font_bold_path" in character and character.font_bold_path:
			font_bold_to_use = load(character.font_bold_path)
		if "font_italic_path" in character and character.font_italic_path:
			font_italic_to_use = load(character.font_italic_path)
		if "font_bold_italic_path" in character and character.font_bold_italic_path:
			font_bold_italic_to_use = load(character.font_bold_italic_path)
		if character.font_color:
			color_to_use = character.font_color
		if character.font_size:
			font_size = 25 + character.font_size
	else:
		# Fallback: no live NPC found (player-character lines, or speaker name doesn't
		# match the NPC's character_id). Try loading directly from the character data file.
		if debug: print(GameState.script_name_tag(self, _fname) + "No NPC found for '" + character_id + "' — trying character data file fallback")
		var data_path = "res://data/characters/" + character_id + ".json"
		if ResourceLoader.exists(data_path):
			var file_text = FileAccess.get_file_as_string(data_path)
			var json = JSON.new()
			if json.parse(file_text) == OK:
				var data : Dictionary = json.get_data()
				var fp   : String = data.get("font_path", "")
				var fbp  : String = data.get("font_bold_path", "")
				var fip  : String = data.get("font_italic_path", "")
				var fbip : String = data.get("font_bold_italic_path", "")
				var fc   : String = data.get("font_color", "")
				var fs   : int    = data.get("font_size", 0)
				if fp   != "" and ResourceLoader.exists(fp):   font_to_use            = load(fp)
				if fbp  != "" and ResourceLoader.exists(fbp):  font_bold_to_use       = load(fbp)
				if fip  != "" and ResourceLoader.exists(fip):  font_italic_to_use     = load(fip)
				if fbip != "" and ResourceLoader.exists(fbip): font_bold_italic_to_use = load(fbip)
				if fc != "":
					color_to_use = Color(fc)
				if fs != 0:
					font_size = 25 + fs
				if debug: print(GameState.script_name_tag(self, _fname) + "Loaded character data from file for: " + character_id)
			else:
				if debug: print(GameState.script_name_tag(self, _fname) + "Failed to parse character data file for: " + character_id)
		else:
			if debug: print(GameState.script_name_tag(self, _fname) + "No character data file found for: " + character_id)

	# Fall back to the normal font for any variant not provided
	if font_bold_to_use == null:       font_bold_to_use       = font_to_use
	if font_italic_to_use == null:     font_italic_to_use     = font_to_use
	if font_bold_italic_to_use == null: font_bold_italic_to_use = font_to_use

	dialogue_label.add_theme_font_override("normal_font",       font_to_use)
	dialogue_label.add_theme_font_override("bold_font",         font_bold_to_use)
	dialogue_label.add_theme_font_override("italics_font",      font_italic_to_use)
	dialogue_label.add_theme_font_override("bold_italics_font", font_bold_italic_to_use)
	if debug: print(GameState.script_name_tag(self, _fname) + "Applied font: ", font_to_use.resource_path if font_to_use.resource_path else "built-in")

	dialogue_label.add_theme_color_override("default_color", color_to_use)
	dialogue_label.add_theme_font_size_override("normal_font_size", font_size)
	dialogue_label.add_theme_font_size_override("bold_font_size", font_size)
	dialogue_label.add_theme_font_size_override("italics_font_size", font_size)
	dialogue_label.add_theme_font_size_override("bold_italics_font_size", font_size)
	if debug: print(GameState.script_name_tag(self, _fname) + "Applied color: ", color_to_use, " and size: ", font_size)

func _to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos

func _get_character_screen_rect(character: Node2D) -> Rect2:
	var area : Node = character.get_node_or_null("InteractionArea")
	if area:
		var col : Node = area.get_node_or_null("CollisionShape2D")
		if col and col.shape is CircleShape2D:
			var center_world : Vector2 = character.to_global(area.position + col.position)
			var center_s     : Vector2 = _to_screen(center_world)
			var edge_s       : Vector2 = _to_screen(center_world + Vector2((col.shape as CircleShape2D).radius, 0))
			var r            : float   = (edge_s - center_s).length()
			return Rect2(center_s - Vector2(r, r), Vector2(r * 2.0, r * 2.0))

	var col : Node = character.get_node_or_null("CollisionShape2D")
	if col and col.shape is RectangleShape2D:
		var shape : RectangleShape2D = col.shape as RectangleShape2D
		var tl : Vector2 = _to_screen(character.to_global(col.position - shape.size * 0.5))
		var br : Vector2 = _to_screen(character.to_global(col.position + shape.size * 0.5))
		return Rect2(tl, br - tl)

	var s : Vector2 = _to_screen(character.global_position)
	return Rect2(s - Vector2(16, 32), Vector2(32, 48))

func _position_balloon() -> void:
	var panel : Panel = balloon.get_node("Panel")
	# Set width first so the DialogueLabel wraps text at the correct column width.
	panel.custom_minimum_size = Vector2(BALLOON_WIDTH, 0)
	panel.size = Vector2(BALLOON_WIDTH, panel.size.y)
	await get_tree().process_frame  # first frame: establish width
	await get_tree().process_frame  # second frame: text reflows at that width

	var vw : float = get_viewport().get_visible_rect().size.x
	var vh : float = get_viewport().get_visible_rect().size.y

	# Measure actual content height so the balloon resizes every line.
	var char_h  : float = character_label.size.y if character_label.visible else 0.0
	var text_h  : float = dialogue_label.get_content_height()
	const PADDING : float = 32.0
	var bh : float = clampf(
		maxf(char_h + text_h + PADDING, BALLOON_WIDTH / 2.0),
		BALLOON_WIDTH / 2.0,
		vh * 0.75)
	panel.size = Vector2(BALLOON_WIDTH, bh)

	var bw : float = BALLOON_WIDTH

	if not is_instance_valid(_current_speaker):
		# Fallback: bottom-centre for narrator / player lines with no NPC node
		panel.position = Vector2((vw - bw) / 2.0, vh - bh - BALLOON_MARGIN)
		return

	var speaker_rect  : Rect2   = _get_character_screen_rect(_current_speaker)
	var char_center_s : Vector2 = speaker_rect.get_center()

	var other_rects : Array[Rect2] = []
	for npc in get_tree().get_nodes_in_group("npc"):
		if npc != _current_speaker and is_instance_valid(npc):
			other_rects.append(_get_character_screen_rect(npc))

	var candidates : Array[Vector2] = [
		Vector2(char_center_s.x - bw * 0.5, speaker_rect.position.y - bh - BALLOON_MARGIN),
		Vector2(speaker_rect.position.x - bw - BALLOON_MARGIN, char_center_s.y - bh * 0.5),
		Vector2(speaker_rect.position.x + speaker_rect.size.x + BALLOON_MARGIN, char_center_s.y - bh * 0.5),
		Vector2(char_center_s.x - bw * 0.5, speaker_rect.position.y + speaker_rect.size.y + BALLOON_MARGIN),
	]

	var best_pos : Vector2 = Vector2(
		clamp(candidates[0].x, BALLOON_MARGIN, vw - bw - BALLOON_MARGIN),
		clamp(candidates[0].y, BALLOON_MARGIN, vh - bh - BALLOON_MARGIN)
	)
	var best_score : int = 999

	for candidate in candidates:
		var bx : float = clamp(candidate.x, BALLOON_MARGIN, vw - bw - BALLOON_MARGIN)
		var by : float = clamp(candidate.y, BALLOON_MARGIN, vh - bh - BALLOON_MARGIN)
		var brect := Rect2(bx, by, bw, bh)
		if brect.intersects(speaker_rect):
			continue
		var score : int = 0
		for r in other_rects:
			if brect.intersects(r):
				score += 1
		if score < best_score:
			best_score = score
			best_pos   = Vector2(bx, by)
			if score == 0:
				break

	panel.position = best_pos

func _unhandled_input(_event: InputEvent) -> void:
	# Only the balloon is allowed to handle input while it's showing
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	## Detect a change of locale and update the current dialogue line to show the new language
	if what == NOTIFICATION_TRANSLATION_CHANGED and _locale != TranslationServer.get_locale() and is_instance_valid(dialogue_label):
		_locale = TranslationServer.get_locale()
		var visible_ratio = dialogue_label.visible_ratio
		self.dialogue_line = await resource.get_next_dialogue_line(dialogue_line.id)
		if visible_ratio < 1:
			dialogue_label.skip_typing()

## Start some dialogue
func start(dialogue_resource: DialogueResource, title: String, extra_game_states: Array = []) -> void:
	var _fname = "start"
	if debug: print(GameState.script_name_tag(self, _fname) + "Start method called")
	if debug: print(GameState.script_name_tag(self, _fname) + "Dialogue resource: " + GameState.script_name(dialogue_resource))
	if debug: print(GameState.script_name_tag(self, _fname) + "Title: ", title)
	
	resource = dialogue_resource
	temporary_game_states = [self] + extra_game_states
	
	if debug: print(GameState.script_name_tag(self, _fname) + "About to get dialogue line")
	self.dialogue_line = await resource.get_next_dialogue_line(title, temporary_game_states)
	if debug: print(GameState.script_name_tag(self, _fname) + "Dialogue line received: ", self.dialogue_line)
	
	if self.dialogue_line:
		if debug: print(GameState.script_name_tag(self, _fname) + "Dialogue text: ", self.dialogue_line.text)
		_on_dialogue_line_started(self.dialogue_line)
		if debug: print(GameState.script_name_tag(self, _fname) + "Font applied for character")
	else:
		if debug: print(GameState.script_name_tag(self, _fname) + "No dialogue line returned!")

## Apply any changes to the balloon given a new [DialogueLine].
func apply_dialogue_line() -> void:
	var _fname = "apply_dialogue_line"
	if debug: print(GameState.script_name_tag(self, _fname) + "Apply dialogue line called")
	
	# Apply character styling first
	if dialogue_line and dialogue_line.text:
		_on_dialogue_line_started(dialogue_line)
	
	mutation_cooldown.stop()
	
	is_waiting_for_input = false
	balloon.focus_mode = Control.FOCUS_ALL
	balloon.grab_focus()

	character_label.visible = not dialogue_line.character.is_empty()
	character_label.text = tr(dialogue_line.character, "dialogue")

	dialogue_label.hide()
	dialogue_label.dialogue_line = dialogue_line
	if debug: print(GameState.script_name_tag(self, _fname) + "Dialogue text in apply: ", dialogue_line.text)
	
	responses_menu.hide()
	responses_menu.responses = dialogue_line.responses

	# Show our balloon and position it near the speaking character
	if debug: print(GameState.script_name_tag(self, _fname) + "About to show balloon")
	balloon.show()
	will_hide_balloon = false
	await _position_balloon()

	dialogue_label.show()
	if debug: print(GameState.script_name_tag(self, _fname) + "Dialogue label shown")
	if not dialogue_line.text.is_empty():
		if debug: print(GameState.script_name_tag(self, _fname) + "Starting typing")
		dialogue_label.type_out()
		if debug: print(GameState.script_name_tag(self, _fname) + "Waiting for typing to finish")
		await dialogue_label.finished_typing
		if debug: print(GameState.script_name_tag(self, _fname) + "Typing finished")

	# Wait for input
	if dialogue_line.responses.size() > 0:
		balloon.focus_mode = Control.FOCUS_NONE
		responses_menu.show()
	elif dialogue_line.time != "":
		var time = dialogue_line.text.length() * 0.02 if dialogue_line.time == "auto" else dialogue_line.time.to_float()
		await get_tree().create_timer(time).timeout
		next(dialogue_line.next_id)
	else:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()

## Go to the next line
func next(next_id: String) -> void:
	var _fname = "next"
	self.dialogue_line = await resource.get_next_dialogue_line(next_id, temporary_game_states)
	# Apply character styling when moving to next line
	if self.dialogue_line:
		_on_dialogue_line_started(self.dialogue_line)

#region Signals

func _on_mutation_cooldown_timeout() -> void:
	if will_hide_balloon:
		will_hide_balloon = false
		balloon.hide()

func _on_mutated(mutation):
	var _fname = "_on_mutated"
	if debug: print(GameState.script_name_tag(self, _fname) + str(mutation))
	
	if mutation.has("expression") and mutation["expression"].size() >= 3:
		var expr = mutation["expression"][2]
		if expr is Dictionary and expr.get("type", "") == "function":
			var func_name = expr.get("function", "")

			if func_name == "move_character_to_marker":
				var args = expr.get("value", [])
				if args.size() >= 2:
					var character_id = args[0][0].get("value", "")
					var target_marker = args[1][0].get("value", "")
					CutsceneManager.move_character_to_marker(character_id, target_marker)
					return
		
			elif func_name == "wait_for_movements": 
				if CutsceneManager:
					return CutsceneManager.wait_for_movements()

func _on_balloon_gui_input(event: InputEvent) -> void:
	# See if we need to skip typing of the dialogue
	if dialogue_label.is_typing and GameState.dialogue_skip_enabled:
		var mouse_was_clicked: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()
		var skip_button_was_pressed: bool = event.is_action_pressed(skip_action)
		if mouse_was_clicked or skip_button_was_pressed:
			get_viewport().set_input_as_handled()
			dialogue_label.skip_typing()
			return

	if not is_waiting_for_input: return
	if dialogue_line.responses.size() > 0: return

	# When there are no response options the balloon itself is the clickable thing
	get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		is_waiting_for_input = false  # Prevent re-entry: do-commands run async inside next(), so
		next(dialogue_line.next_id)   # is_waiting_for_input staying true would let a second click
	elif event.is_action_pressed(next_action) and get_viewport().gui_get_focus_owner() == balloon:
		is_waiting_for_input = false  # fire another next() while animations are mid-execution.
		next(dialogue_line.next_id)

func _on_responses_menu_response_selected(response: DialogueResponse) -> void:
	next(response.next_id)

#endregion
