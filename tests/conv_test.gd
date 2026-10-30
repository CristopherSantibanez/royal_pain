extends SceneTree
# Prueba de conversaciones por actitud: probabilidades y resultados para las 12 personalidades,
# charla íntima (solo hombre-mujer), amenazas al pueblo, rumores, una vez al mes, muerte y némesis.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var GM = root.get_node("GameManager")
	var RD = root.get_node("RelationsData")
	var MD = root.get_node("MapData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var REL = load("res://scripts/resources/relationship.gd")
	var DC = load("res://scripts/resources/dialogue_catalog.gd")
	var player = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	player.charisma = 10
	player.gold = 100
	player.honor = 60
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame
	var errors := 0
	var area: Array = RD.people_in_area()
	var courtier = null
	var commoner = null
	for r in area:
		if r.kind == REL.Kind.CORTESANO and r.character.gender != player.gender and courtier == null:
			courtier = r
		if r.kind == REL.Kind.PUEBLO and commoner == null and r.character.role < player.role:
			commoner = r
	print("cortesano=%s pueblo=%s" % [courtier.person_name, commoner.person_name if commoner else "-"])

	# Tabla de éxito y ganancia media por personalidad y actitud (Monte Carlo).
	var month := [0]
	var atts := ["amable", "halagador", "franco", "amenazante", "intima"]
	print("%-11s %s" % ["", "  ".join(atts.map(func(a): return "%-16s" % a))])
	for p in 12:
		courtier.character.personality = p
		var row := []
		for a in atts:
			var wins := 0
			var total := 0
			var empty_lines := 0
			for i in 60:
				courtier.affection = 50
				courtier.romance = false
				courtier.last_courted_month = -1
				GM.actions_remaining = 3
				var res: Dictionary = RD.converse(courtier, a)
				if not res.ok:
					print("ERROR no ok: ", res.text); errors += 1; break
				if res.reply.is_empty():
					empty_lines += 1
				if res.success:
					wins += 1
				total += res.delta
			if empty_lines > 0:
				print("ERROR respuestas vacías %s/%s: %d" % [DC.PERSONALITY_NAMES.get(p, p), a, empty_lines]); errors += 1
			courtier.affection = 50
			row.append("%3d%% ok, %+5.1f" % [roundi(RD.converse_chance(courtier, a) * 100), total / 60.0])
		print("%-11s %s" % [DC.PERSONALITY_NAMES.get(p, str(p)), "  ".join(row.map(func(x): return "%-16s" % x))])

	# Una vez al mes.
	courtier.last_courted_month = -1
	GM.actions_remaining = 3
	RD.converse(courtier, "amable")
	var again: Dictionary = RD.converse(courtier, "franco")
	print("Segunda charla el mismo mes: ok=%s (%s)" % [again.ok, again.text])
	if again.ok: errors += 1

	# Charla íntima: solo con el otro género y con confianza.
	var same = null
	for r in RD.relations:
		if RD.sociable(r) and r.character.gender == player.gender and same == null:
			same = r
	var ids := []
	for o in RD.conversation_options(same):
		ids.append(o.id)
	print("Mismo género, actitudes: ", ids)
	if "intima" in ids: errors += 1
	courtier.affection = 10
	courtier.last_courted_month = -1
	for o in RD.conversation_options(courtier):
		if o.id == "intima": print("Íntima con intimidad 10: ", o.reason)
	courtier.affection = 60
	courtier.character.personality = CH.Personality.ROMANTICO
	var romance_ok := false
	for i in 20:
		courtier.last_courted_month = -1
		GM.actions_remaining = 3
		var res: Dictionary = RD.converse(courtier, "intima")
		if not res.get("ok", true):
			print("Charla íntima bloqueada: ", res.text)
			break
		if res.success:
			romance_ok = courtier.romance
			print("Charla íntima lograda: ", res.text.replace("\n", " "))
			break
	if not romance_ok: errors += 1

	# Amenazar al pueblo: oro y honor.
	if commoner:
		commoner.character.personality = CH.Personality.COBARDE
		var gold_before: int = player.gold
		var honor_before: int = player.honor
		var got := 0
		for i in 10:
			commoner.last_courted_month = -1
			GM.actions_remaining = 3
			var res: Dictionary = RD.converse(commoner, "amenazante")
			if res.success: got += 1
			if i == 0: print("Amenaza: ", res.text.replace("\n", " "))
		print("Amenazas con éxito %d/10: oro %+d, honor %+d" % [got, player.gold - gold_before, player.honor - honor_before])
		player.honor = 10
		player.role = CH.Role.CAMPESINO
		commoner.last_courted_month = -1
		print("Sin honor ni rango: ", RD.can_converse(commoner, "amenazante"))
		player.role = CH.Role.CABALLERO
		player.honor = 60

	# Rumores de un confidente.
	courtier.character.personality = CH.Personality.LEAL
	var rumors := 0
	for i in 40:
		courtier.affection = 70
		courtier.last_courted_month = -1
		GM.actions_remaining = 3
		var res: Dictionary = RD.converse(courtier, "franco")
		if not res.reward.is_empty():
			rumors += 1
			if rumors == 1: print(res.reward)
	print("Rumores en 40 charlas francas con un Confidente leal: ", rumors)
	if rumors == 0: errors += 1

	# Némesis: opción de duelo a muerte.
	var rival = null
	for r in RD.relations:
		if r.kind == REL.Kind.RIVAL_DUELO: rival = r; break
	if rival == null:
		rival = courtier
	rival.grudge = 90
	var ev: Dictionary = {}
	for i in 30:
		ev = RD._rival_event(rival, player)
		if ev.id == "rival_reto": break
	var labels := []
	for o in ev.options: labels.append("%s%s" % [o.label, " [a muerte]" if o.get("to_death", false) else ""])
	print("Etapa=%s opciones: %s" % [REL.RivalryStage.keys()[rival.rivalry_stage()], labels])
	if ev.id == "rival_reto" and rival.rivalry_stage() == REL.RivalryStage.NEMESIS and not labels.any(func(l): return "a muerte" in l): errors += 1

	# Muerte: sale de relaciones, séquito y pretendientes; si era cónyuge, fin del matrimonio.
	var dead_name: String = courtier.person_name
	RD.retinue.append(dead_name)
	var witness = null
	for r in RD.relations:
		if r != courtier and r.kind != REL.Kind.SENOR: witness = r; break
	witness.rival_suitor = dead_name
	RD.spouse_name = dead_name
	RD.on_character_died(dead_name, "duelo a muerte")
	print("Tras morir: relación=%s séquito=%s pretendiente='%s' cónyuge='%s'" % [RD.get_relation(dead_name), dead_name in RD.retinue, witness.rival_suitor, RD.spouse_name])
	if RD.get_relation(dead_name) != null or dead_name in RD.retinue or witness.rival_suitor != "" or RD.spouse_name != "": errors += 1
	print("ERRORES: ", errors)
	quit()
