extends SceneTree
func _initialize() -> void:
	seed(7)
	var KA = load("res://scripts/resources/kingdom_ai.gd")
	for pair in [[135, 90], [120, 100], [100, 100], [150, 90], [90, 90]]:
		var w := 0
		for i in 4000:
			if KA.auto_resolve(pair[0], pair[1]).attacker_won:
				w += 1
		print("auto %d vs %d (asedio): atacante gana %.1f%%" % [pair[0], pair[1], 100.0 * w / 4000])
	quit()
