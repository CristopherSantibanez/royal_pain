extends SceneTree
var n := 0
var s
func _initialize() -> void:
	s = load("res://scripts/resources/equipment.gd")
func _process(_d: float) -> bool:
	n += 1
	return n > 60
