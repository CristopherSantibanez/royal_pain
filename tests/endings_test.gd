extends SceneTree
# Libro de hazañas y finales: recompensas, guardado, migración, conquista, unificación, deshonra y ejecución.

var fails := 0

func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok  ", what)
	else:
		fails += 1
		print("  FALLA ", what)

func _initialize() -> void:
	_run.call_deferred()

func _new_game(role: int, castle_index: int = 0):
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var player = CL.make_test_character("Sir Alaric", role)
	player.gender = CharacterEnums.Gender.MASCULINO
	GM.start_new_game(player, MD.castles[castle_index].castle_id)
	await process_frame
	return player

func _run() -> void:
	seed(11)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var AD = root.get_node("AchievementData")
	var RD = root.get_node("RelationsData")
	var DD = root.get_node("DynastyData")
	var WE = root.get_node("WorldEvents")
	var CH = load("res://scripts/resources/character.gd")
	var CL = load("res://scripts/resources/character_loader.gd")
	var SS = load("res://scripts/resources/save_system.gd")
	var CAT = load("res://scripts/resources/achievement_catalog.gd")

	print("[catálogo]")
	for role in [CH.Role.CAMPESINO, CH.Role.SOLDADO, CH.Role.NOBLEZA_ALTA, CH.Role.CONDOTIERO]:
		var vis: Array = CAT.visible_for(role)
		check(vis.size() >= 25 and vis.size() <= 34, "%s ve %d hazañas" % [CH.role_name_for(role), vis.size()])
		check(vis.filter(func(a): return a.has("goal_role")).size() == 1, "una sola de destino para %s" % CH.role_name_for(role))
		check(CAT.featured_for(role).size() >= 2, "%s tiene %d destacadas" % [CH.role_name_for(role), CAT.featured_for(role).size()])

	print("[hazaña y recompensa]")
	var player = await _new_game(CH.Role.SOLDADO)
	check(AD.achieved.is_empty(), "sin hazañas al empezar")
	check(AD.visited_castles.size() == 1, "el castillo de origen cuenta como visitado")
	var gold0: int = player.gold
	var chron0: int = WE.chronicle.size()
	player.duels_won = 1
	var got: Array = AD.check_all()
	check("primera_sangre" in got, "primera sangre al ganar un duelo (%s)" % [got])
	check(player.gold >= gold0 + 30, "recompensa de oro (%d -> %d)" % [gold0, player.gold])
	check(WE.chronicle.size() > chron0 and str(WE.chronicle[-1].text).contains("Hazaña"), "queda en la crónica")
	check(AD.check_all().is_empty(), "no se repite")
	var next: Array = AD.next_achievements()
	check(next.size() == 3 and next[0].id == "goal_soldado", "Tu destino: la de destino primero, 3 en total")

	print("[meta de destino: recompensa sin fin de partida]")
	var points0: int = player.unspent_points
	player.role = CH.Role.CABALLERO
	player.duels_won = 10
	got = AD.check_all()
	check("goal_soldado" in got, "meta del Soldado cumplida")
	check(player.unspent_points >= points0 + 2, "da puntos de atributo (%d -> %d)" % [points0, player.unspent_points])
	check(GM.is_game_active and GM.victory_achieved, "la partida sigue (victory_achieved = true por compatibilidad)")

	print("[guardado y migración]")
	var before: Dictionary = AD.achieved.duplicate()
	check(SS.save_game() == OK and SS.load_game(), "guarda y carga")
	check(AD.achieved.keys().size() == before.keys().size() and AD.achieved.has("goal_soldado"), "las hazañas sobreviven al guardado")
	GM.victory_achieved = true
	GM.starting_role = CH.Role.CABALLERO
	AD.load_state({})
	check(AD.achieved.has("goal_caballero") and AD.achieved.size() == 1, "partida antigua con victoria: meta del rol marcada")
	GM.victory_achieved = false
	AD.load_state({})
	check(AD.achieved.is_empty(), "partida antigua sin victoria: nada marcado")

	print("[deshonra sin fin de partida]")
	player = await _new_game(CH.Role.CABALLERO)
	RD.liege_name = "Lord Prueba"
	player.honor = 0
	var text: String = GM.check_disgrace()
	print("  ", text)
	check(GM.is_game_active, "la partida sigue")
	check(player.role == CH.Role.MERCENARIO and RD.liege_name.is_empty(), "un caballero deshonrado es expulsado y queda como mercenario")
	check(player.honor == 15, "honor rehecho a 15 (%d)" % player.honor)
	check(GM.check_disgrace().is_empty(), "no se repite con honor > 0")
	player.role = CH.Role.NOBLEZA_BAJA
	player.honor = 0
	GM.check_disgrace()
	check(player.role == CH.Role.CABALLERO and GM.is_game_active, "una noble deshonrada baja un rango")
	check(not GM.check_defeat(), "check_defeat ya no termina la partida")

	print("[final: conquista del mundo, vía tu señor]")
	player = await _new_game(CH.Role.CABALLERO)
	RD.liege_name = "Lord Soberano"
	check(AD.check_endings().is_empty(), "al empezar no hay final")
	for c in MD.castles:
		if c.kingdom != KingdomEnums.Kingdom.NEUTRAL:
			c.kingdom = GM.player_kingdom
	var ending: Dictionary = AD.check_endings()
	check(ending.get("id", "") == AD.ENDING_CONQUEST, "conquista del mundo")
	check(str(ending.get("text", "")).contains("Lord Soberano"), "habla de tu señor: %s" % str(ending.get("text", "")).left(90))
	check(GM.is_game_active, "se puede seguir jugando")
	check(AD.check_endings().is_empty(), "el final no se repite")

	print("[final: unificación por matrimonio]")
	player = await _new_game(CH.Role.NOBLEZA_ALTA)
	var mine: int = GM.player_kingdom
	var other := -1
	for c in MD.castles:
		if c.kingdom != KingdomEnums.Kingdom.NEUTRAL and c.kingdom != mine:
			other = c.kingdom
			break
	for c in MD.castles:
		if c.kingdom != KingdomEnums.Kingdom.NEUTRAL and c.kingdom != mine and c.kingdom != other:
			c.kingdom = mine
	check(AD.kingdoms_standing().size() == 2, "quedan dos reinos")
	check(AD.check_endings().is_empty(), "sin matrimonio no hay unificación")
	var lord = null
	for r in RD.relations:
		if r.kind == Relationship.Kind.SENOR and r.kingdom == other:
			lord = r
			break
	check(lord != null, "hay un señor del otro reino")
	if lord != null:
		lord.affinity = 90
		RD.arrange_political_marriage(lord.person_name)
		ending = AD.check_endings()
		check(ending.get("id", "") == AD.ENDING_UNIFICATION, "boda con la casa del último reino: unificación")
		print("  ", str(ending.get("text", "")).left(160))

	print("[ejecución tras captura]")
	player = await _new_game(CH.Role.CABALLERO)
	var child = CL.make_child(player, player, "Alaric")
	child.age = 20
	DD._children.append(child)
	DD._parent_of[child.full_name()] = player.full_name()
	DD.on_player_executed("Lord Cruel")
	check(DD.needs_succession() and GM.is_game_active, "con heredero: se elige sucesor")
	check(DD.death_cause().contains("ejecutado por orden de Lord Cruel"), "causa: %s" % DD.death_cause())
	DD.succeed(DD.adult_children()[0])
	check(GM.player_character == child and GM.is_game_active, "el heredero sigue la partida")
	AD.check_all()
	check(AD.generation == 2, "segunda generación (%d)" % AD.generation)
	DD._children.clear()
	DD.on_player_executed("Lord Cruel")
	check(DD.needs_succession() and DD.adult_children().is_empty(), "sin heredero: sucesión imposible")
	DD.end_lineage()
	check(not GM.is_game_active, "sin heredero: fin de la partida")

	print("RESULTADO: %d FALLAS" % fails)
	quit()
