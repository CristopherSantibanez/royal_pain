extends SceneTree
# Roles: Duque (ascenso, corona vacante), quedarse sin tierras, abandonar al señor, interfaz y guardado.
# (El camino mercenario se retiró: sus comprobaciones ahora verifican que ya no aparece.)

var fails := 0

func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok  ", what)
	else:
		fails += 1
		print("  FALLA ", what)

func _initialize() -> void:
	_run.call_deferred()

func _month(GM) -> void:
	GM.advance_turn()
	await process_frame
	if GM.has_pending_event():
		GM.pending_event = {}

func _new_game(role: int) -> Character:
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var player = CL.make_test_character("Sir Alaric", role)
	player.gender = CharacterEnums.Gender.MASCULINO
	player.role = role
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame
	await process_frame
	return player

func _run() -> void:
	seed(11)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var MI = root.get_node("MissionData")
	var WE = root.get_node("WorldEvents")
	var AD = root.get_node("ArmyData")
	var RP = load("res://scripts/resources/role_progression.gd")
	var VR = load("res://scripts/resources/victory_rules.gd")
	var SS = load("res://scripts/resources/save_system.gd")
	var CH = load("res://scripts/resources/character.gd")

	print("[rangos]")
	check(CH.rank_of(CH.Role.DUQUE) > CH.rank_of(CH.Role.NOBLEZA_ALTA) and CH.rank_of(CH.Role.DUQUE) < CH.rank_of(CH.Role.REGENTE), "Duque entre Nobleza Alta y Regente")
	check(CH.rank_of(CH.Role.CAPITAN) == CH.rank_of(CH.Role.CABALLERO), "Capitán equivale a Caballero")
	check(CH.role_title_for(CH.Role.DUQUE, CharacterEnums.Gender.FEMENINO) == "Duquesa", "Duquesa")
	check(CH.role_title_for(CH.Role.CONDOTIERO, CharacterEnums.Gender.FEMENINO) == "Condotiera", "Condotiera")

	print("[Duque]")
	var p: Character = await _new_game(CH.Role.NOBLEZA_ALTA)
	var ctx: Dictionary = MI.progression_context()
	var chk: Dictionary = RP.check_ascension(p, ctx)
	check(chk.next_role == CH.Role.DUQUE and not chk.can_ascend, "Nobleza Alta apunta a Duque y pide requisitos: %s" % chk.reason)
	p.honor = 80
	p.leadership = 16
	var king_castle: Castle = null
	for c: Castle in MD.castles:
		if (c.owner_name.begins_with("Rey ") or c.owner_name.begins_with("Reina ")):
			king_castle = c
	for c: Castle in MD.castles:
		if c.castle_id != GM.home_castle_id and c != king_castle:
			c.owner_name = p.full_name()
			c.kingdom = GM.player_kingdom
			break
	ctx = MI.progression_context()
	print("    ", RP.check_ascension(p, ctx).reason)
	check(RP.ascend(p, ctx) and p.role == CH.Role.DUQUE, "asciende a Duque con 2 castillos, honor y liderazgo")
	GM.refresh_actions_for_role_change()
	check(GM.actions_per_turn >= 4, "Duque tiene 4+ acciones (%d)" % GM.actions_per_turn)
	check(RD.RETINUE_SIZE[CH.Role.DUQUE] == 5, "séquito de 5")
	chk = RP.check_ascension(p, MI.progression_context())
	check(chk.next_role == CH.Role.REGENTE, "Duque apunta a Regente")
	p.honor = 10
	check(RP.check_dishonor_demotion(p), "Duque deshonrado puede caer")
	RP.apply_dishonor_demotion(p)
	check(p.role == CH.Role.NOBLEZA_ALTA, "cae a Nobleza Alta")
	p.role = CH.Role.DUQUE
	p.honor = 80

	print("[corona vacante]")
	check(king_castle != null, "tu reino tiene rey: %s" % (king_castle.owner_name if king_castle else "-"))
	var got := false
	for i in 30:
		if king_castle == null:
			break
		GM.pending_event = {}
		WE.deferred_event = {}
		WE._lord_dies(RD.get_relation(king_castle.owner_name))
		if GM.pending_event.get("id", "") == "corona_vacante":
			got = true
			break
	check(got, "si eres Duque, el rey puede morir sin hijos")
	if got:
		var pretender: String = GM.pending_event.pretender
		var text: String = GM.resolve_pending_event(0)
		check(p.role == CH.Role.REGENTE, "reclamar el trono te hace Regente")
		check(RD.castles_of(pretender).is_empty(), "los castillos de la Corona pasan a ti")
		print("    ", text)

	print("[sin tierras]")
	p = await _new_game(CH.Role.CABALLERO)
	var home: Castle = MD.get_castle_by_id(GM.home_castle_id)
	var lines: Array[String] = []
	AD._handle_home_castle_lost(home, lines)
	check(GM.is_game_active and p.role == CH.Role.INAFILIADO and GM.home_castle_id != home.castle_id, "perder el último castillo: %s" % " ".join(lines))
	p.role = CH.Role.NOBLEZA_BAJA
	check(RP.landless_role(p) == CH.Role.INAFILIADO, "un noble sin tierras pasa a No afiliado")

	print("[abandonar a tu señor]")
	p.role = CH.Role.SOLDADO
	var txt: String = MI.desert_liege(p)
	check(p.role == CH.Role.INAFILIADO and RD.liege_name.is_empty(), txt)

	print("[guardado]")
	MI.active.clear()
	MI.active.append({"uid": "9", "id": "c_campeon", "contract": true, "title": "Viejo contrato"})
	check(SS.save_game("1") == OK, "guarda")
	check(SS.load_game("1") and MI.active.is_empty(), "los contratos de partidas antiguas se descartan al cargar")
	SS.delete_save("1")
	p = GM.player_character

	print("[interfaz]")
	for role in [CH.Role.INAFILIADO, CH.Role.CABALLERO, CH.Role.DUQUE]:
		p.role = role
		GM.current_castle = MD.get_castle_by_id(GM.home_castle_id) if role == CH.Role.DUQUE else MD.castles[2]
		var ci: Node = load("res://scenes/castle_interior/castle_interior.tscn").instantiate()
		root.add_child(ci)
		await process_frame
		print("    rol=", p.role, " gm=", GM.player_character.role, " same=", GM.player_character == p, " castle=", GM.current_castle.castle_id, " home=", GM.home_castle_id)
		var labels: Array[String] = []
		for b in ci.action_buttons():
			labels.append(b.text)
		check(labels.size() > 2 and not "Ofrecer tus Servicios" in labels, "%s: %s" % [p.role_title(), ", ".join(labels)])
		ci.queue_free()
		await process_frame
	var ng: Node = load("res://scenes/new_game/new_game.tscn").instantiate()
	root.add_child(ng)
	await process_frame
	var names: Array[String] = []
	for i in ng.role_option.item_count:
		names.append(ng.role_option.get_item_text(i))
	check(not "Condotiero" in names and not "Mercenario" in names and "No afiliado" in names, "Nueva Partida ofrece: %s" % ", ".join(names))
	ng.queue_free()

	print("FALLAS: ", fails)
	quit(fails)
