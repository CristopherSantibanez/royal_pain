extends SceneTree
func _initialize() -> void:
	var s = load("res://scripts/resources/battle_manager.gd")
	print("ok ", s != null)
	quit()
