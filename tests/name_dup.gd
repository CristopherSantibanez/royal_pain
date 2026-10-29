extends SceneTree
func _initialize() -> void:
	var NC = load("res://scripts/resources/name_catalog.gd")
	var MD = root.get_node("MapData")
	var dups := 0
	var total := 0
	for i in 60:
		MD.new_world()
		for c in MD.castles:
			total += 1
			var w: PackedStringArray = c.owner_name.split(" ", false)
			for j in range(1, w.size()):
				if w[j] == w[j - 1]:
					dups += 1
					print("  repetido: ", c.owner_name)
	print("nombres de señores: %d · con palabra repetida: %d" % [total, dups])
	quit()
