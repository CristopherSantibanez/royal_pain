extends SceneTree
# Diagnóstico: ¿qué le pasa al pelotón del compañero en una batalla ajena?

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var BM = load(OS.get_environment("BMPATH") if OS.get_environment("BMPATH") != "" else "res://scripts/resources/battle_manager.gd")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 42)
	var N := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 200
	var stats := {"wins": 0, "comp_start_morale": 0.0, "comp_soldiers": 0.0, "comp_family": {}, "comp_fate": {}, "duels_lost_by_us": 0, "duels_won_by_us": 0, "refused": 0}
	var log_lines := {}
	for i in N:
		var b = BM.new()
		b.player_side = BattleEnums.Side.ATACANTE
		b.ally_competence_override = 1.0
		var me: Character = CL.make_test_character("Tú", CH.Role.NOBLEZA_ALTA)
		b.player_leader = me
		var comp: Character = CL.make_test_character("Compañero", CH.Role.CABALLERO)
		var comps: Array[Character] = []
		if OS.get_environment("NOCOMP") != "1":
			comps.append(comp)
		b.ally_soldiers = 100
		var holder := [-1]
		b.battle_ended.connect(func(w: int, _r: Dictionary): holder[0] = w)
		b.challenge_offered.connect(func(_c, _t): b.answer_challenge(false))
		b.log_message.connect(func(t: String):
			for key in ["reta a duelo", "rehúsa", "rehusa", "abandona", "Duelo singular", "se retira", "huye", "aniquilado"]:
				if key in t:
					log_lines[key] = log_lines.get(key, 0) + 1)
		b.start_battle(128, 120, false, CL.make_test_character("Anfitrión", CH.Role.NOBLEZA_ALTA), CL.make_test_character("Enemigo", CH.Role.NOBLEZA_ALTA), "X", comps)
		var cu = null
		for u in b.units:
			if u.side == BattleEnums.Side.ATACANTE:
				if u.companion == comp:
					cu = u
				u.ally = true
		if cu != null:
			stats.comp_start_morale += cu.morale
			stats.comp_soldiers += cu.soldiers
			var fam := BattleEnums.unit_type_name(cu.type)
			stats.comp_family[fam] = stats.comp_family.get(fam, 0) + 1
		var guard := 0
		while not b.is_over and guard < 60:
			guard += 1
			if b.pending_retreat:
				b.answer_retreat(false)
			b.end_player_turn()
		if holder[0] == BattleEnums.Side.ATACANTE:
			stats.wins += 1
		if cu != null:
			var fate := "en pie"
			if cu.left_field:
				fate = "se retiró"
			elif cu.soldiers <= 0:
				fate = "aniquilado"
			elif cu.routed:
				fate = "huyó"
			stats.comp_fate[fate] = stats.comp_fate.get(fate, 0) + 1
	print("gana %.1f%% | moral inicial compañero %.0f | soldados %.1f" % [100.0 * stats.wins / N, stats.comp_start_morale / N, stats.comp_soldiers / N])
	print("familias: ", stats.comp_family)
	print("destino del pelotón del compañero: ", stats.comp_fate)
	print("registro: ", log_lines)
	quit()
