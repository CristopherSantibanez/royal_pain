extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _check(name: String, ok: bool) -> void:
	print("%s %s" % ["OK  " if ok else "FAIL", name])

func _run() -> void:
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var AD = root.get_node("ArmyData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var RP = load("res://scripts/resources/role_progression.gd")
	var VR = load("res://scripts/resources/victory_rules.gd")
	var MV = load("res://scenes/map/map_vision.gd")
	var BM = load("res://scripts/resources/battle_manager.gd")

	# Alistarse
	var peasant = CL.make_test_character("Campesino", CH.Role.CAMPESINO)
	peasant.gold = 20
	peasant.combat = 5
	_check("campesino sin oro ni combate no se alista", not RP.check_ascension(peasant).can_ascend)
	peasant.gold = 70
	_check("campesino con 60 de oro se alista y paga", RP.ascend(peasant) and peasant.gold == 10 and peasant.role == CH.Role.SOLDADO)

	# Partida
	var pc = CL.make_test_character("Sir Prueba", CH.Role.NOBLEZA_BAJA)
	GM.start_new_game(pc, "hielo")
	var home = MD.get_castle_by_id("hielo")
	var vis_nb: Array = MV.get_visible_castle_ids(CH.Role.NOBLEZA_BAJA, "hielo")
	var vis_cab: Array = MV.get_visible_castle_ids(CH.Role.CABALLERO, "hielo")
	var vis_na: Array = MV.get_visible_castle_ids(CH.Role.NOBLEZA_ALTA, "hielo")
	print("vision caballero=%d noble_baja=%d noble_alta=%d" % [vis_cab.size(), vis_nb.size(), vis_na.size()])
	_check("la visión no se reduce al ascender", vis_nb.size() >= vis_cab.size() and vis_na.size() >= vis_nb.size())

	# Victoria Nobleza Baja: 2 castillos + Nobleza Alta
	var goal = VR.evaluate(CH.Role.NOBLEZA_BAJA, pc, MD.castles, GM.player_kingdom, "hielo")
	_check("meta noble baja no cumplida al empezar: " + goal.progress, not goal.done)

	# Ejércitos: movilizar dos veces se suma; reunir; volver a la guarnición
	var a1 = AD.add_player_troops("hielo", home.kingdom, 30)
	var a2 = AD.add_player_troops("hielo", home.kingdom, 20)
	_check("dos movilizaciones forman un solo ejército de 50", a1 == a2 and a1.size == 50)
	var extra = AD.create_army(pc.full_name(), home.kingdom, 10, "hielo")
	var merged = AD.merge_armies("hielo")
	_check("reunir ejércitos suma 60", merged != null and merged.size == 60 and AD.idle_player_armies_at("hielo").size() == 1)
	var garrison_before: int = home.garrison_size
	_check("volver a la guarnición", AD.garrison_army(merged) and home.garrison_size == garrison_before + 60)

	# Economía mensual: renta del jugador, paga y comida
	pc.rent = 20
	var gold_before: int = pc.gold
	var food_before: int = home.food
	GM.pending_event = {}
	GM.advance_turn()
	print("oro jugador %d -> %d (renta 20) | comida castillo %d -> %d" % [gold_before, pc.gold, food_before, home.food])
	_check("la renta se cobra cada mes", pc.gold >= gold_before + 20)

	# Asedio: un ejército del jugador pendiente desgasta al castillo
	var target = null
	for nid in home.connected_castle_ids:
		var n = MD.get_castle_by_id(nid)
		if n.kingdom != home.kingdom:
			target = n
			break
	var siege = AD.create_army(pc.full_name(), home.kingdom, 50, target.castle_id)
	siege.pending_battle = true
	siege.origin_castle_id = "hielo"
	var g0: int = target.garrison_size
	pc.gold = 100
	GM.pending_event = {}
	GM.advance_turn()
	print("asedio: guarnición %d -> %d, oro 100 -> %d" % [g0, target.garrison_size, pc.gold])
	_check("el asedio baja la guarnición y cobra la paga", target.garrison_size < g0 + 2 and pc.gold < 100)

	# Liderazgo por batalla ganada al mando (una vez al mes)
	var lead0: int = pc.leadership
	AD.resolve_battle(siege, true, 40, 0)
	_check("conquistar da +1 Liderazgo", pc.leadership == lead0 + 1)

	# Vista previa de bajas en batalla
	var bm = BM.new()
	bm.start_battle(120, 80, true, pc, null, "Prueba")
	var att = bm.active_units(0)[0]
	var tgt = bm.active_units(1)[0]
	var p = bm.preview_attack(att, tgt)
	print("preview: ", p)
	_check("preview devuelve bajas", p.casualties >= 1)
	quit()
