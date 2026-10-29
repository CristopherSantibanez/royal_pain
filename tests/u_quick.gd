extends SceneTree

func _initialize() -> void:
	var BM = load("res://scripts/resources/battle_manager.gd")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var a = CL.make_test_character("Sir A", CH.Role.NOBLEZA_BAJA)
	var d = CL.make_test_character("Sir D", CH.Role.CABALLERO)
	var wins := 0
	for i in 20:
		var b = BM.new()
		b.challenge_offered.connect(func(_c, _t): b.answer_challenge(false))
		b.random_conditions = false
		b.start_battle(120, 100, false, a, d, "Prueba")
		if i == 0:
			for u in b.units:
				print(BattleEnums.unit_type_name(u.type), " ", u.soldiers, " gen=", u.general, " lead=", u.leader().full_name() if u.leader() else "-")
		var guard := 0
		while not b.is_over and guard < 40:
			b._run_ai(b.player_side)
			b.end_player_turn()
			guard += 1
		if i < 6: print(b.turn, " ", b.total_soldiers(0), " vs ", b.total_soldiers(1), " over=", b.is_over)
		if b.is_over and b.total_soldiers(0) > b.total_soldiers(1):
			wins += 1
	print("ataque gana ", wins, "/20")
	quit()
