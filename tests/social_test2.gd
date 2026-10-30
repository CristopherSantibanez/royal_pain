extends SceneTree
# Prueba del sistema social v2: intimidad, romance solo hombre-mujer, retos, séquito, compañeros y guardado.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var GM = root.get_node("GameManager")
	var RD = root.get_node("RelationsData")
	var MD = root.get_node("MapData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var REL = load("res://scripts/resources/relationship.gd")
	var player = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	player.charisma = 12
	player.gold = 2000
	player.fame = 70
	player.honor = 90
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame

	var area: Array = RD.people_in_area()
	var kinds := {}
	for r in area:
		kinds[REL.Kind.keys()[r.kind]] = kinds.get(REL.Kind.keys()[r.kind], 0) + 1
	print("Gente en la zona: ", area.size(), " ", kinds)

	var same_gender = null
	var other_gender = null
	for r in area:
		if r.character.gender == player.gender and same_gender == null:
			same_gender = r
		if r.character.gender != player.gender and other_gender == null and r.character.role != CH.Role.CAMPESINO:
			other_gender = r
	print("Mismo género: romance posible=%s, gesto íntimo: %s" % [RD.romance_possible(same_gender), RD.can_interact(same_gender, "intimate")])

	# Intimidad y romance con alguien del otro género.
	var month := 0
	for i in 14:
		GM.actions_remaining = 3
		GM.current_month = 1 + month % 12
		GM.current_year = 1 + month / 12
		month += 1
		var kind: String = "friendly" if other_gender.affection < RD.INTIMATE_MIN_AFFECTION else "intimate"
		var res: String = RD.interact(other_gender, kind)
		print("%-8s intimidad=%3d romance=%s | %s" % [kind, other_gender.affection, other_gender.romance, res.replace("\n", " ")])
		if other_gender.affection >= RD.PROPOSAL_MIN_AFFECTION:
			break

	# Retos.
	GM.actions_remaining = 5
	for r in area.slice(0, 6):
		var why: String = RD.can_challenge(r)
		var result: Dictionary = RD.challenge(r) if why.is_empty() else {"accepted": false, "text": why}
		print("Reto a %s (%s): %s" % [r.person_name, r.character.role_name(), result.text.replace("\n", " ")])
		GM.actions_remaining = 5

	# Séquito y compañeros.
	print("Plazas de séquito: ", RD.max_retinue())
	print("Compañeros de facción sin séquito: ", RD.battle_companions().map(func(c): return "%s (facción=%s)" % [c.full_name(), c.has_meta("faction_companion")]))
	GM.actions_remaining = 3
	print("Invitar: ", RD.invite_to_retinue(other_gender).replace("\n", " "))
	print("Séquito: ", RD.retinue, " | campeones: ", RD.duel_champions().map(func(c): return c.full_name()), " | compañeros: ", RD.battle_companions().map(func(c): return c.full_name()))

	# Guardado y carga.
	var SS = load("res://scripts/resources/save_system.gd")
	print("Guardar: ", SS.save_game("slot_3"))
	RD.retinue.clear()
	print("Cargar: ", SS.load_game("slot_3"), " | séquito tras cargar: ", RD.retinue)
	SS.delete_slot("slot_3") if SS.has_method("delete_slot") else null
	quit()
