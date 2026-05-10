extends LocationSceneBase

var bailey_follow : bool = true

func _on_scene_ready() -> void:
	location_id = "church_interior"
	cutscene_triggers = {"CutsceneTrigger": "church_intro"}
	CutsceneManager.start_cutscene("pre_sermon")
	# camera limits stay at base defaults (right 1200 / bottom 800 / left 20 / top 20)
