extends SceneTree
# Prueba del frente WORLD: mundo aleatorio, sucesos globales, noticias, encargos y guardado.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var MI = root.get_node("MissionData")
	var WE = root.get_node("WorldEvents")
	var SS = load("res://scripts/resources/save_system.gd")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")

	# 1. Mundos distintos
	MD.new_world(1)
	var a: Array = MD.castles.map(func(c): return c.owner_name)
	MD.new_world(2)
	var b: Array = MD.castles.map(func(c): return c.owner_name)
	print("Mundo 1: ", a.slice(0, 4))
	print("Mundo 2: ", b.slice(0, 4))
	print("Distintos: ", a != b, " | ", MD.world_summary())

	var player = CL.make_test_character("Sir Prueba", CH.Role.CABALLERO)
	player.gold = 400
	GM.start_new_game(player, "hielo")
	await process_frame
	print("Señor: ", RD.liege_name, " | guerras iniciales: ", RD.kingdom_wars.keys(), " alianzas: ", RD.kingdom_alliances.keys())

	# 2. 36 meses
	var counts := {}
	var notes := 0
	var missions_seen := {}
	for m in 36:
		if not GM.is_game_active:
			print("Partida terminada mes ", m, ": ", GM.game_over_reason)
			break
		GM.advance_turn()
		await process_frame
		while WE.has_notifications():
			var n = WE.pop_notification()
			notes += 1
			if notes <= 6:
				print("  [aviso] ", n.title, ": ", n.text)
		if GM.has_pending_event():
			var e: Dictionary = GM.pending_event
			counts[e.id] = counts.get(e.id, 0) + 1
			var rel = RD.get_relation(e.get("target", e.get("speaker", "")))
			GM.resolve_pending_event(0 if e.id in ["encargo", "boda_politica"] else randi() % e.options.size(), rel)
		for mm in MI.active.duplicate():
			missions_seen[mm.id] = true
			if MI.action_label(mm) != "" and mm.type != "exhibition":
				GM.actions_remaining = 2
				MI.act(mm.uid)
	print("Eventos: ", counts)
	print("Avisos: ", notes, " | encargos vistos: ", missions_seen.keys(), " | cumplidos %d fallidos %d activos %d" % [MI.completed_count, MI.failed_count, MI.active.size()])
	print("Jugador: oro %d honor %d fama %d | casado: %s" % [player.gold, player.honor, player.fame, RD.spouse_name])

	# 3. Exhibición + on_duel_finished
	var knights: Array = RD.courtiers().filter(func(r): return r.kingdom != GM.player_kingdom and r.character != null and r.character.role == CH.Role.CABALLERO)
	if not knights.is_empty():
		MI.accept({"id": "exhibicion", "title": "Prueba", "type": "exhibition", "months": 3, "text": "x {target}", "target": knights[0].person_name,
			"reward": {"fame": 10}, "penalty": {"honor": -4}, "giver": RD.liege_name, "uid": "t1", "progress": 0})
		var fame_before: int = player.fame
		MI.on_duel_finished(knights[0].character, true)
		print("Exhibición ganada: fama %d -> %d, activos %d" % [fame_before, player.fame, MI.active.size()])

	# 4. Guardado y carga
	MI.accept({"id": "levas", "title": "Levas prueba", "type": "garrison", "amount": 999, "months": 6, "text": "t",
		"reward": {"honor": 1}, "penalty": {"honor": -1}, "giver": RD.liege_name, "uid": "t2", "progress": 0})
	WE.notify("Prueba", "aviso guardado")
	WE.married_lords["X"] = "Y"
	var saved_active: int = MI.active.size()
	var err: int = SS.save_game("ranura_3")
	MI.reset()
	WE.notifications.clear()
	WE.married_lords.clear()
	var ok: bool = SS.load_game("ranura_3")
	print("Guardado %d, carga %s | encargos %d (antes %d) | avisos %d | bodas %s" % [err, ok, MI.active.size(), saved_active, WE.notifications.size(), WE.married_lords])
	SS.delete_slot("ranura_3") if SS.has_method("delete_slot") else null
	quit()
