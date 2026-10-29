extends SceneTree
var n := 0
func _process(_d: float) -> bool:
	n += 1
	return n > 60
