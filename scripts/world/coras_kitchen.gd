extends LocationSceneBase

var bailey_follow : bool = true

func _on_scene_post_ready() -> void:
	super._on_scene_post_ready()
	location_id = "coras_kitchen"
	CutsceneManager.start_cutscene("first_breakfast")
	# camera limits stay at base defaults (right 1200 / bottom 800 / left 20 / top 20)
