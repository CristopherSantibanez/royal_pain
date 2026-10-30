extends SceneTree
# No afiliado: libertad de movimiento, jornales, voluntario, asentarse, alistarse, abandonar y ascensos más caros.

var fails := 0

func check(c: bool, what: String) -> void:
	print(("  ok  " if c else "  FALLA ") + what)
	if not c:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _castle_scene(GM, castle) -> Node:
	GM.current_castle = castle
	change_scene_to_file("res://scenes/castle_interior/castle_interior.tscn")
	await create_timer(0.4).timeout
	return current_scene

func _labels(ci) -> Array:
	return ci.action_buttons().map(func(b): return b.text)

func _run() -> void:
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var TD = root.get_node("TravelData")
	var MI = root.get_node("MissionData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var RP = load("res://scripts/resources/role_progression.gd")
	var SS = load("res://scripts/resources/save_system.gd")

	print("[inicio]")
	var p = CL.make_test_character("Juan Sintierra", CH.Role.INAFILIADO)
	p.gold = 40
	p.combat = 8
	GM.start_new_game(p, MD.castles[0].castle_id)
	await process_frame
	await process_frame
	check(p.role_title() == "No afiliado" and CH.role_title_for(CH.Role.INAFILIADO, CharacterEnums.Gender.FEMENINO) == "No afiliada", "títulos «No afiliado/a»")
	check(RD.liege_name.is_empty(), "sin señor desde el primer día")
	check(CH.rank_of(CH.Role.INAFILIADO) == 0, "rango como el campesino")

	print("[viaje]")
	var far = null
	for c in MD.castles:
		if c.castle_id in MD.castles[0].connected_castle_ids:
			far = c
			break
	GM.actions_remaining = 4
	GM.pending_event = {}
	var r: Dictionary = TD.travel_toward(far.castle_id)
	check(r.get("ok", false), "viaja a un castillo vecino (%s)" % r.get("text", ""))
	TD.location_id = far.castle_id
	check(TD.can_enter(MD.castles[0]) != "", "lejos, no entra a «su» castillo de origen (no tiene tierra)")

	print("[castillo ajeno]")
	GM.actions_remaining = 5
	var ci = await _castle_scene(GM, far)
	var labels := _labels(ci)
	check(not labels.any(func(l): return l.begins_with("Trabajar la Tierra")), "no puede trabajar la tierra")
	check(labels.any(func(l): return l.begins_with("Trabajo a Jornal")), "puede trabajar a jornal")
	check(labels.any(func(l): return l.begins_with("Asentarte")), "puede asentarse")
	check(labels.any(func(l): return l.begins_with("Alistarte")), "puede alistarse")

	print("[jornales]")
	var g0: int = p.gold
	var DJ = load("res://scripts/resources/day_jobs.gd")
	var paid: int = ci._do_day_job(DJ.JOBS[0])
	check(paid > 0 and p.gold == g0 + paid, "el jornal paga (%d oro)" % paid)
	ci._do_day_job(DJ.JOBS[1])
	var g1: int = p.gold
	check(ci._do_day_job(DJ.JOBS[0]) == 0 and p.gold == g1, "tope de %d jornales al mes" % DJ.PER_MONTH)
	var strong = CL.make_test_character("Fuerte", CH.Role.INAFILIADO)
	strong.combat = 18
	check(DJ.pay(DJ.JOBS[3], strong, far) > DJ.pay(DJ.JOBS[3], p, far), "la escolta paga más con más Combate")

	print("[voluntario]")
	RD.kingdom_wars.clear()
	var enemy = null
	for id in far.connected_castle_ids:
		var c = MD.get_castle_by_id(id)
		if c != null and c.kingdom != far.kingdom:
			enemy = c
			break
	if enemy != null:
		KingdomDiplomacy.declare_war(RD.kingdom_wars, RD.kingdom_alliances, far.kingdom, enemy.kingdom, 0)
		var ev: Dictionary = root.get_node("ArmyData").volunteer_event(far)
		check(not ev.is_empty() and ev.options.size() >= 2, "se ofrece voluntario en una guerra ajena")
		var CS = root.get_node("CombatSetup")
		check(CS.battle_blocker(p) == "", "el no afiliado sí puede ir a la batalla")
	else:
		print("  (sin vecino de otro reino para probar el voluntario)")
	RD.kingdom_wars.clear()

	print("[alistarse]")
	check(RP.enlist_blocker(p) != "", "sin 150 de oro ni Combate 12 no se alista")
	p.gold = 160
	GM.actions_remaining = 3
	ci = await _castle_scene(GM, far)
	ci._action_enlist()
	check(p.role == CH.Role.SOLDADO and p.gold == 10 and RD.liege_name == far.owner_name, "se alista: soldado de %s, paga las armas" % far.owner_name)

	print("[soldado abandona → no afiliado]")
	MI.desert_liege(p)
	check(p.role == CH.Role.INAFILIADO and RD.liege_name.is_empty(), "el soldado que abandona a su señor queda no afiliado")

	print("[asentarse → campesino]")
	TD.last_fealty_month = -999
	GM.actions_remaining = 3
	var res: Dictionary = TD.swear_fealty(far)
	check(res.ok and p.role == CH.Role.CAMPESINO, "se asienta: campesino")

	print("[campesino abandona sus tierras]")
	TD.location_id = GM.home_castle_id
	ci = await _castle_scene(GM, MD.get_castle_by_id(GM.home_castle_id))
	check(_labels(ci).any(func(l): return l.begins_with("Abandonar tus Tierras")), "el campesino puede abandonar sus tierras")
	ci._action_abandon_land()
	check(p.role == CH.Role.INAFILIADO and RD.liege_name.is_empty(), "queda no afiliado")

	print("[ascensos]")
	var camp = CL.make_test_character("Campesino", CH.Role.CAMPESINO)
	camp.gold = 100
	camp.combat = 10
	check(not RP.check_ascension(camp).can_ascend, "campesino con 100 oro y Combate 10 ya no asciende")
	camp.gold = 150
	check(RP.check_ascension(camp).can_ascend, "con 150 de oro sí")
	var sol = CL.make_test_character("Soldado", CH.Role.SOLDADO)
	sol.duels_won = 3
	sol.honor = 80
	check(not RP.check_ascension(sol).can_ascend, "soldado con 3 duelos ya no basta (pide %d)" % RP.SOLDADO_MIN_DUELS_WON)

	print("[guardado]")
	check(SS.save_game() == OK and SS.load_game(), "guarda y carga")
	check(GM.player_character.role == CH.Role.INAFILIADO, "sigue siendo no afiliado tras cargar")

	print("FALLAS: ", fails)
	quit(fails)
