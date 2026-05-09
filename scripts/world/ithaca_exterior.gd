extends LocationSceneBase

func _on_scene_ready() -> void:
	location_id = "ithaca_exterior"
	camera_limit_right  = -5080.0
	camera_limit_bottom = 709.0
	camera_limit_left   = -6200.0
	camera_limit_top    = 110
	if player:
		player.char_anim._set_initial_frame("idle", "left")

func _on_scene_post_ready() -> void:
	super._on_scene_post_ready()
	CutsceneManager.start_cutscene("ithaca_intro")
