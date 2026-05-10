extends LocationSceneBase

var bailey_follow : bool = false

func _on_scene_ready() -> void:
	zoom_factor = 2
	location_id = "coras_kitchen"
	$Node2D/Camera2D.make_current()
	
func _on_scene_post_ready() -> void:
	super._on_scene_post_ready()
	CutsceneManager.start_cutscene("first_breakfast")
	# camera limits stay at base defaults (right 1200 / bottom 800 / left 20 / top 20)
