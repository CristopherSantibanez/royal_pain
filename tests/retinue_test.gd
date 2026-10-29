extends SceneTree
# Séquito v2: nivel «Íntimo», plazas de íntimos, ocupaciones del mes, equipo, práctica y campeón designado.

var fails := 0

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _find_button(node: Node, contains: String) -> Button:
	if node is Button and (node as Button).text.contains(contains):
		return node
	for child in node.get_children():
		var b := _find_button(child, contains)
		if b != null:
			return b
	return null

func _run() -> void:
	seed(11)
	var GM = root.get_node("GameManager")
	var RD = root.get_node("RelationsData")
	var MD = root.get_node("MapData")
	var CS = root.get_node("CombatSetup")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var DC = load("res://scripts/resources/dialogue_catalog.gd")
	var OR = load("res://scripts/resources/occupation_rules.gd")
	var SS = load("res://scripts/resources/save_system.gd")
	var REL = load("res://scripts/resources/relationship.gd")
	var CC = load("res://scripts/resources/content_catalog.gd")

	print("[nivel Íntimo]")
	check(DC.intimacy_name(85, true, CharacterEnums.Gender.FEMENINO) == "Íntima", "80+ con romance, mujer: «%s»" % DC.intimacy_name(85, true, CharacterEnums.Gender.FEMENINO))
	check(DC.intimacy_name(85, false, CharacterEnums.Gender.MASCULINO) == "Íntimo", "80+ sin romance, hombre: «%s»" % DC.intimacy_name(85, false, CharacterEnums.Gender.MASCULINO))
	check(DC.intimacy_name(65, true, CharacterEnums.Gender.MASCULINO) == "Confidente", "60-79 sigue siendo Confidente")

	var player = CL.make_test_character("Juan Labriego", CH.Role.CAMPESINO)
	player.gender = CharacterEnums.Gender.MASCULINO
	player.gold = 500
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame
	var area: Array = RD.people_in_area().filter(func(r): return r.character != null)
	# Los que se baten (no campesinos) primero: b será el campeón.
	area.sort_custom(func(x, y): return int(x.character.role != CH.Role.CAMPESINO) > int(y.character.role != CH.Role.CAMPESINO))
	check(area.size() >= 4, "hay gente en la zona (%d)" % area.size())
	var b = area[0]
	var a = area[1]
	var c = area[2]
	var d = area[3]
	for r in [a, b, c, d]:
		r.affection = 60
	check(RD.intimacy_label(a) == "Confidente", "intimidad 60 → Confidente")
	print("[plazas: campesino]")
	GM.actions_remaining = 5
	check(RD.max_retinue() == 0, "un campesino no tiene plazas normales")
	check(not RD.can_invite(a).is_empty(), "con intimidad 60 no te sigue: «%s»" % RD.can_invite(a))
	a.affection = 85
	b.affection = 90
	c.affection = 82
	check(RD.is_intimate(a) and RD.intimacy_label(a).begins_with("Íntim"), "intimidad 85 → %s" % RD.intimacy_label(a))
	check(RD.can_invite(a).is_empty(), "un íntimo sí te sigue aunque seas campesino")
	RD.invite_to_retinue(a)
	GM.actions_remaining = 5
	RD.invite_to_retinue(b)
	GM.actions_remaining = 5
	check(RD.retinue.size() == 2, "dos íntimos en el séquito del campesino")
	check(not RD.can_invite(c).is_empty(), "el tercer íntimo ya no cabe: «%s»" % RD.can_invite(c))
	check(RD.retinue_slots_text() == "Séquito 0/0 (+2/2 íntimos)", "texto de plazas: %s" % RD.retinue_slots_text())

	print("[plazas: caballero con cónyuge]")
	player.role = CH.Role.CABALLERO
	player.fame = 0
	player.honor = 10
	RD._add_spouse_relation("Inés", "de Prueba", 0, CharacterEnums.Gender.FEMENINO)
	var spouse = RD.relations[RD.relations.size() - 1]
	RD.spouse_name = spouse.person_name
	check(RD.is_intimate(spouse), "el cónyuge cuenta como íntimo")
	check(RD.can_invite(spouse).is_empty(), "el cónyuge puede unirse")
	RD.invite_to_retinue(spouse)
	GM.actions_remaining = 5
	# Caballero: 2 plazas normales + 2 de íntimos; ya hay 3 íntimos (a, b y la esposa).
	d.affection = 60
	d.character.role = CH.Role.CABALLERO   # un caballero pide 15 de fama y 40 de honor
	var knight_req: String = RD.can_invite(d)
	check(not knight_req.is_empty(), "alguien no íntimo sigue pidiendo fama y honor: «%s»" % knight_req)
	check(RD.can_invite(c).is_empty(), "un cuarto íntimo cabe en una plaza normal libre")
	RD.invite_to_retinue(c)
	GM.actions_remaining = 5
	check(RD.retinue_slots_text() == "Séquito 2/2 (+2/2 íntimos)", "texto de plazas: %s" % RD.retinue_slots_text())
	player.fame = 90
	player.honor = 90
	d.affection = 60
	check(not RD.can_invite(d).is_empty(), "lleno: ni con fama entra alguien más («%s»)" % RD.can_invite(d))

	print("[ocupaciones]")
	check(RD.occupation_people().size() == 4, "cónyuge + 3 del séquito tienen ocupación (%d)" % RD.occupation_people().size())
	check(RD.occupation_of(a) == OR.DESCANSAR, "por defecto, descansar")
	RD.set_occupation(a, OR.ADMINISTRAR)
	RD.set_occupation(b, OR.ENTRENAR)
	RD.set_occupation(c, OR.ESTUDIAR)
	RD.set_occupation(spouse, OR.ADMINISTRAR)
	spouse.character.wound_months = 2
	var expected_gold: int = OR.admin_gold(a.character)
	var xp_b: int = b.character.xp + b.character.level * 1000
	var xp_c: int = c.character.xp + c.character.level * 1000
	var combat_b: int = b.character.combat
	var strategy_c: int = c.character.strategy
	var gold_before: int = player.gold
	RD._apply_occupations(player)
	check(player.gold - gold_before == expected_gold, "administrar rinde %d de oro (la esposa, herida, descansa)" % (player.gold - gold_before))
	check(b.character.xp + b.character.level * 1000 > xp_b, "entrenar da experiencia (%s)" % RD.retinue_news.back())
	check(c.character.xp + c.character.level * 1000 > xp_c, "estudiar da experiencia")
	check(spouse.character.wound_months == 0, "descansar cura 2 meses de herida en uno (1 normal + 1 extra)")
	var trained := 0
	var studied := 0
	for i in 60:
		var cb: int = b.character.combat
		var st: int = c.character.strategy
		RD._apply_occupations(player)
		trained += int(b.character.combat > cb)
		studied += int(c.character.strategy > st)
	print("  en 60 meses: +Combate %d veces, +Estrategia %d veces · nivel %d / %d" % [trained, studied, b.character.level, c.character.level])
	check(trained > 0 and studied > 0, "a veces sube Combate (entrenar) y Estrategia (estudiar)")
	check(b.character.level > 1 and b.character.unspent_points == 0, "sube de nivel y reparte solo sus puntos (nivel %d)" % b.character.level)
	check(b.character.pending_skill_choices == 0, "elige sola sus habilidades")
	check(not RD.retinue_news.is_empty() and RD.retinue_news.back().begins_with("Tu casa este mes:"), "resumen del mes en las noticias")

	print("[mes real y guardado]")
	RD.retinue_news.clear()
	GM.pending_event = {}
	GM.advance_turn()
	await process_frame
	check(RD.retinue_news.any(func(t): return t.begins_with("Tu casa este mes:")), "al pasar el mes se aplican las ocupaciones")
	RD.designated_champion = b.person_name
	var st: Dictionary = RD.save_state()
	RD.occupations.clear()
	RD.designated_champion = ""
	RD.load_state(st)
	check(RD.occupation_of(b) == OR.ENTRENAR and RD.designated_champion == b.person_name, "ocupaciones y campeón se guardan")
	RD.load_state({"retinue": RD.retinue.duplicate()})
	check(RD.occupation_of(b) == OR.DESCANSAR and RD.designated_champion == "", "partidas antiguas: descansar y sin campeón")
	check(SS.save_game() == OK, "guardar partida completa")
	check(SS.load_game(), "cargar partida completa")
	a = RD.get_relation(a.person_name)
	b = RD.get_relation(b.person_name)
	player = GM.player_character

	print("[equipo]")
	var sword := Equipment.new()
	sword.equipment_name = "Espada de Prueba"
	sword.slot = CC.SLOT_ARMA
	sword.combat_mod = 3
	for e in player.equipment.duplicate():
		if e.slot == CC.SLOT_ARMA:
			player.unequip(e)
	for e in a.character.equipment.duplicate():
		a.character.unequip(e)
	player.equip(sword)
	var combat_a: int = a.character.combat
	var combat_p: int = player.combat
	print("  ", RD.swap_equipment(a, CC.SLOT_ARMA))
	check(sword in a.character.equipment and not sword in player.equipment, "das tu espada a tu compañero")
	check(a.character.combat == combat_a + 3 and player.combat == combat_p - 3, "los bonos pasan con la pieza")
	print("  ", RD.swap_equipment(a, CC.SLOT_ARMA))
	check(sword in player.equipment, "y la recuperas")
	var unique = null
	for e in root.get_node("GameData").equipment_catalog:
		if SkillEffects.is_unique_item(e) and e.slot != CC.SLOT_ARMA:
			unique = e.duplicate()
			break
	if unique != null:
		a.character.equip(unique)
		RD.swap_equipment(a, unique.slot)
		check(unique in player.equipment, "las piezas únicas también se pueden pasar (%s)" % unique.equipment_name)

	print("[duelo de práctica]")
	GM.actions_remaining = 3
	player.current_health = player.max_health
	b.character.current_health = b.character.max_health
	b.character.wound_months = 0
	player.wound_months = 0
	var honor_p: int = player.honor
	var won_p: int = player.duels_won + player.duels_lost
	var aff_b: int = b.affection
	var lvlxp_p: int = player.xp + player.level * 1000
	var lvlxp_b: int = b.character.xp + b.character.level * 1000
	check(RD.start_practice(b).is_empty(), "empieza la práctica (gasta 1 acción)")
	check(not RD.can_practice(b).is_empty(), "solo una práctica al mes con cada uno")
	CS.start_campaign_duel(player, b.character)
	CS.return_scene = "res://scenes/relations/relations.tscn"
	change_scene_to_file("res://scenes/combat/combat.tscn")
	await create_timer(0.6).timeout
	var combat = current_scene
	check(combat._practice, "la escena sabe que es práctica (sin elegir campeón)")
	b.character.current_health = 4
	var guard := 0
	while not combat.duel.is_over and guard < 40:
		if combat.player_turn:
			combat._player_action(0)
		await create_timer(1.3).timeout
		guard += 1
	await create_timer(0.3).timeout
	print("  ", CS.last_result_text)
	check(combat.duel.is_over, "el duelo de práctica termina")
	check(player.current_health > 0 and player.wound_months == 0 and b.character.wound_months == 0, "nadie queda herido")
	check(b.character.current_health == b.character.max_health, "la vida vuelve a como estaba")
	check(player.honor == honor_p and player.duels_won + player.duels_lost == won_p, "ni honor ni récord de duelos cambian")
	check(player.xp + player.level * 1000 > lvlxp_p and b.character.xp + b.character.level * 1000 > lvlxp_b, "los dos ganan experiencia")
	check(b.affection == mini(100, aff_b + OR.PRACTICE_INTIMACY), "y algo de confianza (+%d)" % OR.PRACTICE_INTIMACY)
	check(RD.practice_partner == "", "la práctica queda cerrada")

	print("[campeón designado]")
	b.character.wound_months = 0
	b.character.current_health = b.character.max_health
	a.character.current_health = a.character.max_health
	RD.designated_champion = b.person_name
	check(RD.duel_champions()[0] == b.character, "el campeón designado se ofrece primero")
	var rival = CL.make_test_character("Sir Rival", CH.Role.CABALLERO)
	CS.start_campaign_duel(player, rival)
	CS.return_scene = "res://scenes/relations/relations.tscn"
	change_scene_to_file("res://scenes/combat/combat.tscn")
	await create_timer(0.6).timeout
	combat = current_scene
	var btn := _find_button(combat, "(campeón)")
	check(btn != null and btn.text.begins_with(b.character.first_name), "en la ventana previa aparece «%s»" % (btn.text if btn != null else "?"))
	if btn != null:
		btn.pressed.emit()
	await create_timer(0.4).timeout
	check(combat.player_character == b.character, "eliges al campeón y lo controlas tú en el duelo")
	check(not combat._practice, "un duelo de verdad no es práctica")
	print("[despedir]")
	RD.dismiss_from_retinue(b)
	check(RD.designated_champion == "" and not RD.occupations.has(b.person_name), "al despedirlo se borra campeón y ocupación")

	print("RESULTADO: %d FALLAS" % fails)
	quit(fails)
