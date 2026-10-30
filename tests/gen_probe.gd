extends SceneTree
func _initialize() -> void:
	var BM = load("res://scripts/resources/battle_manager.gd")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	seed(5)
	var stats := {"aniquilado": 0, "huye": 0, "otro": 0}
	var types := {}
	var careful := 0
	for i in 120:
		var b = BM.new()
		b.challenge_offered.connect(func(_c, _t): b.answer_challenge(false))
		var a = CL.make_test_character("A", CH.Role.NOBLEZA_ALTA)
		var d = CL.make_test_character("D", CH.Role.NOBLEZA_ALTA)
		b.start_battle(100, 100, false, a, d, "X")
		for u in b.units:
			if u.side == 0: u.ally = true
			if u.general: types[BattleEnums.unit_type_name(u.type)] = types.get(BattleEnums.unit_type_name(u.type), 0) + 1
		var g := 0
		while not b.is_over and g < 60:
			g += 1
			if b.pending_retreat: b.answer_retreat(false)
			b.end_player_turn()
		for s in [0, 1]:
			var f = b._fallen_general_unit(s)
			if f != null:
				if f.soldiers <= 0: stats.aniquilado += 1
				elif f.left_field: stats.otro += 1
				else: stats.huye += 1
	print(stats, " ", types)
	quit()
