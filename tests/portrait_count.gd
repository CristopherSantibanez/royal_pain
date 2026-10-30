extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var c = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	root.get_node("GameManager").start_new_game(c, root.get_node("MapData").castles[0].castle_id)
	var counts := {}
	var males := 0
	var total := 0
	for r in root.get_node("RelationsData").relations:
		if r.character == null: continue
		total += 1
		if r.character.gender == 0: males += 1
		var p: String = r.character.get_portrait().resource_path
		counts[p] = counts.get(p, 0) + 1
	var dup := 0
	for p in counts:
		if counts[p] > 1:
			dup += counts[p]
			print("repetido x%d: %s" % [counts[p], p])
	print("personajes=%d hombres=%d retratos distintos=%d con retrato repetido=%d" % [total, males, counts.size(), dup])
	quit()
