extends LocationSceneBase

var bailey_follow : bool = true

func _on_scene_ready() -> void:
	location_id = "coras_kitchen"
	# camera limits stay at base defaults (right 1200 / bottom 800 / left 20 / top 20)
