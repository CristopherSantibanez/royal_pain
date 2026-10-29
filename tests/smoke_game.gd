extends SceneTree
# Partida de humo: 36 meses con eventos resueltos al azar, cortejo y duelos registrados.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var GM = root.get_node("GameManager")
	var RD = root.get_node("RelationsData")
	var MD = root.get_node("MapData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var player = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	player.gold = 500
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame
	var events := {}
	for m in 36:
		if not GM.is_game_active:
			print("Partida terminada en el mes ", m, ": ", GM.game_over_reason)
			break
		if m % 4 == 0 and RD.courtiers().size() > 0:
			RD.register_duel(RD.courtiers()[0].character, randf() < 0.6, false)
		var court: Array = RD.courtiers()
		if court.size() > 2 and RD.can_interact(court[2], "friendly").is_empty():
			RD.interact(court[2], "friendly")
		GM.advance_turn()
		await process_frame
		if GM.has_pending_event():
			var e: Dictionary = GM.pending_event
			events[e.id] = events.get(e.id, 0) + 1
			var rel = RD.get_relation(e.get("target", e.get("speaker", "")))
			GM.resolve_pending_event(randi() % e.options.size(), rel)
	print("Eventos: ", events)
	print("Jugador: oro %d honor %d rol %s | casado: %s" % [player.gold, player.honor, player.role_name(), RD.spouse_name])
	for r in RD.duel_rivals():
		print("Rival %s: rencor %d (%s), afecto %d" % [r.person_name, r.grudge, r.rivalry_text(), r.affection])
	quit()
