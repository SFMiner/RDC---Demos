extends Control

var game_controller

const scr_debug:bool = false
var debug : bool

const DEMO_SCENES: Array = [
	{"id": "church_interior", "label": "Church Interior"},
	{"id": "ithaca_exterior", "label": "Ithaca Exterior"},
	{"id": "coras_kitchen", "label": "Cora's Kitchen"},
]

func _ready():
	debug = scr_debug or GameController.sys_debug
	game_controller = get_node_or_null("/root/GameController")

	$MenuButtons/NewGameButton.pressed.connect(_on_new_game_pressed)
	$MenuButtons/LoadGameButton.pressed.connect(_on_load_game_pressed)
	$MenuButtons/OptionsButton.pressed.connect(_on_options_pressed)
	$MenuButtons/CreditsButton.pressed.connect(_on_credits_pressed)
	$MenuButtons/QuitButton.pressed.connect(_on_quit_pressed)

func _on_new_game_pressed():
	$MenuButtons.visible = false
	_show_scene_picker()

func _show_scene_picker():
	var picker := VBoxContainer.new()
	picker.name = "ScenePicker"
	picker.position = $MenuButtons.position
	picker.add_theme_constant_override("separation", 20)

	var label := Label.new()
	label.text = "Choose a Scene"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	picker.add_child(label)

	for scene: Dictionary in DEMO_SCENES:
		var btn := Button.new()
		btn.text = scene["label"]
		btn.custom_minimum_size = Vector2(200, 0)
		btn.pressed.connect(_launch_scene.bind(scene["id"]))
		picker.add_child(btn)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(200, 0)
	back.pressed.connect(_on_scene_picker_back)
	picker.add_child(back)

	add_child(picker)

func _on_scene_picker_back():
	var picker := get_node_or_null("ScenePicker")
	if picker:
		picker.queue_free()
	$MenuButtons.visible = true

func _launch_scene(scene_id: String):
	game_controller = get_node_or_null("/root/GameController")
	if not game_controller:
		DebugManager.print_error_auto(self, "GameController not found")
		return
	visible = false
	game_controller.start_new_game(scene_id)


func _on_load_game_pressed():
	var save_load_system = get_node_or_null("/root/SaveLoadSystem")
	if save_load_system:
		save_load_system.load_game(0)

func _on_options_pressed():
	pass

func _on_credits_pressed():
	pass

func _on_quit_pressed():
	get_tree().quit()
