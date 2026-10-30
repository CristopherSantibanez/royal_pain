extends SceneTree
func _initialize() -> void:
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var BM = load("res://scripts/resources/battle_manager.gd")
	var counts := {}
	for i in 200:
		var a = CL.make_test_character("Cmd", CH.Role.NOBLEZA_ALTA)
		a.leadership = 8; a.strategy = 8
		a.mastery_xp = {"1": 240, "seeded": 1}
		var d = CL.make_test_character("Cmd", CH.Role.NOBLEZA_ALTA)
		d.leadership = 8; d.strategy = 8
		var b = BM.new()
		b.start_battle(100, 100, false, a, d, "X")
		var comp := {0: "", 1: ""}
		for u in b.units:
			comp[u.side] += ("G" if u.general else "") + str(BattleEnums.family_of(u.type))
		var k = "A:" + comp[0] + " D:" + comp[1]
		counts[k] = counts.get(k, 0) + 1
	var keys = counts.keys()
	keys.sort_custom(func(x, y): return counts[x] > counts[y])
	for k in keys.slice(0, 8):
		print(counts[k], "  ", k)
	print("combat/defense de prueba: ", CL.make_test_character("Cmd", CH.Role.NOBLEZA_ALTA).combat, "/", CL.make_test_character("Cmd", CH.Role.NOBLEZA_ALTA).defense)
	quit()
