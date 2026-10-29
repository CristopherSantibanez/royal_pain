extends SceneTree
# Dinastía: niveles + panel, edades, nacimientos, mayoría de edad, guardado y sucesión.

var fails := 0

func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok  ", what)
	else:
		fails += 1
		print("  FALLA ", what)

func _initialize() -> void:
	_run.call_deferred()

func _january(GM) -> void:
	GM.current_month = 12
	GM.advance_turn()
	await process_frame
	if GM.has_pending_event():
		GM.pending_event = {}

func _run() -> void:
	seed(7)
	var GM = root.get_node("GameManager")
	var RD = root.get_node("RelationsData")
	var MD = root.get_node("MapData")
	var DD = root.get_node("DynastyData")
	var AD = root.get_node("ArmyData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var SS = load("res://scripts/resources/save_system.gd")
	var player = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	player.gender = CharacterEnums.Gender.MASCULINO
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame

	print("[edad inicial]")
	check(player.age == 23, "caballero empieza con 23 años (tiene %d)" % player.age)
	var ages := {}
	for r in RD.relations:
		if r.character != null:
			ages[r.character.age] = true
	check(ages.size() > 3, "los PNJ tienen edades variadas (%d distintas)" % ages.size())

	print("[niveles]")
	var lv: int = player.gain_xp(100 + 200 + 300)
	check(lv == 3 and player.level == 4, "600 xp → nivel 4 (subió %d)" % lv)
	check(player.unspent_points == 6 and player.pending_skill_choices == 1, "6 puntos y 1 habilidad por elegir")
	var Panel = load("res://scripts/ui/level_up_panel.gd")
	var panel = Panel.open(root)
	await process_frame
	var combat_before: int = player.combat
	panel._change("combat", 1)
	panel._change("combat", 1)
	panel._change("combat", -1)
	check(player.combat == combat_before, "sin confirmar no cambia el atributo")
	panel._confirm_points()
	check(player.combat == combat_before + 1 and player.unspent_points == 5, "confirmar aplica +1 combate y gasta 1 punto")
	var offer: Array = panel._skill_offer()
	check(offer.size() == 3, "ofrece 3 habilidades (%d)" % offer.size())
	var offer2: Array = panel._skill_offer()
	check(offer == offer2, "la oferta no cambia al volver a abrir")
	var n_skills: int = player.general_skills.size() + player.combat_skills.size() + player.battle_skills.size()
	panel._pick_skill(offer[0])
	check(player.pending_skill_choices == 0 and player.general_skills.size() + player.combat_skills.size() + player.battle_skills.size() == n_skills + 1, "elegir habilidad la añade")
	panel._tabs.current_tab = 1
	await process_frame
	panel.queue_free()

	print("[matrimonio y nacimientos]")
	var spouse_rel = null
	for r in RD.relations:
		if r.character != null and r.character.gender == CharacterEnums.Gender.FEMENINO and r.kind != Relationship.Kind.SENOR:
			spouse_rel = r
			break
	spouse_rel.kind = Relationship.Kind.CONYUGE
	spouse_rel.character.age = 24
	RD.spouse_name = spouse_rel.person_name
	var start_age: int = player.age
	for y in 12:
		await _january(GM)
	check(player.age == start_age + 12, "el jugador cumple 12 años en 12 eneros")
	check(DD.children().size() > 0, "nacen hijos (%d en 12 años)" % DD.children().size())
	var kid = DD.children()[0]
	kid.age = 15
	check(kid.portrait == null, "el niño no tiene retrato")
	await _january(GM)
	check(kid.age == 16 and kid.portrait != null, "a los 16 recibe retrato")
	check(kid.portrait.resource_path != player.portrait.resource_path if player.portrait != null else true, "retrato distinto del jugador")
	check(DD.adult_children().size() >= 1, "hay un hijo adulto")
	check(kid.equipment.size() > 0, "el adulto tiene equipo")

	print("[guardado]")
	var n_kids: int = DD.children().size()
	var kid_name: String = kid.full_name()
	check(SS.save_game() == OK, "guardar")
	DD._children.clear()
	check(SS.load_game(), "cargar")
	check(DD.children().size() == n_kids and DD.adult_children()[0].full_name() == kid_name, "los hijos vuelven al cargar")
	check(GM.player_character.age == player.age, "la edad del jugador se guarda")
	player = GM.player_character

	print("[sucesión]")
	var old_name: String = player.full_name()
	MD.castles[1].owner_name = old_name
	var army_count: int = 0
	if not AD.armies.is_empty():
		AD.armies[0].owner_name = old_name
		army_count = 1
	var castles_before: int = MD.castles.filter(func(c): return c.owner_name == old_name).size()
	player.gold = 777
	DD.on_player_died("en un duelo a muerte contra Sir Prueba")
	check(DD.needs_succession(), "tras morir hay que elegir heredero")
	check(SS.save_game() == OK and SS.load_game() and DD.needs_succession(), "la sucesión pendiente sobrevive al guardado")
	var heir = DD.adult_children()[0]
	var text: String = DD.succeed(heir)
	print("  ", text)
	check(GM.player_character == heir and heir.gold == 777, "el heredero es el jugador y hereda el oro")
	check(MD.castles.filter(func(c): return c.owner_name == heir.full_name()).size() == castles_before, "hereda los %d castillos" % castles_before)
	check(AD.armies.filter(func(a): return a.owner_name == old_name).is_empty(), "ningún ejército queda a nombre del difunto")
	check(AD.armies.filter(func(a): return a.owner_name == heir.full_name()).size() >= army_count, "hereda %d ejército(s)" % army_count)
	check(heir.last_name == "de Alaric", "apellido de la casa: «%s»" % heir.last_name)
	check(not RD.is_married() and not DD.needs_succession(), "viuda retirada y sucesión resuelta")
	check(not heir in DD.children(), "el heredero ya no figura entre los hijos")

	check(DD.children().all(func(c): return not DD.is_own_child(c)), "los demás hijos pasan a ser hermanos del heredero")
	print("[linaje extinto]")
	DD._children = DD._children.filter(func(c): return c.age < 16)
	DD.on_player_died("de vejez")
	check(DD.adult_children().is_empty(), "sin hijos adultos")
	var reason: String = DD.end_lineage()
	print("  ", reason)
	check(not GM.is_game_active, "la partida termina")

	print("[probabilidad de vejez] 55:%.2f 60:%.2f 70:%.2f 87:%.2f" % [DD.old_age_chance(55), DD.old_age_chance(60), DD.old_age_chance(70), DD.old_age_chance(87)])
	print("RESULTADO: ", "TODO OK" if fails == 0 else "%d FALLAS" % fails)
	quit()
