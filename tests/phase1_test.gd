extends SceneTree
# Fase 1: registros de alto fijo, reinos caídos, tropa elegida, fin del camino mercenario.

var fails := 0

func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok  ", what)
	else:
		fails += 1
		print("  FALLA ", what)

func _initialize() -> void:
	_run.call_deferred()

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
	GM.pending_event = {}
	return player

func _people_of(RD, k: int) -> Array:
	return RD.relations.filter(func(r): return r.kingdom == k and (r.kind == Relationship.Kind.CORTESANO or r.kind == Relationship.Kind.PUEBLO))

func _run() -> void:
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var SS = load("res://scripts/resources/save_system.gd")
	var RP = load("res://scripts/resources/role_progression.gd")

	print("[registro de 200 líneas]")
	var host := VBoxContainer.new()
	host.size = Vector2(400, 600)
	root.add_child(host)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host.add_child(label)
	var scroll: ScrollContainer = LogView.wrap(label, 100.0)
	var text := ""
	for i in 200:
		text += ("\n" if i > 0 else "") + "Línea %d del registro" % i
		LogView.show(label, text)
	await process_frame
	await process_frame
	check(scroll.size.y <= 101.0, "el registro mantiene su alto (%.0f)" % scroll.size.y)
	check(label.text.split("\n").size() == LogView.MAX_LINES, "se guardan sólo las últimas %d líneas" % LogView.MAX_LINES)
	check(label.text.ends_with("Línea 199 del registro"), "la última línea queda visible")
	host.queue_free()

	var duel: Node = load("res://scenes/combat/combat.tscn").instantiate()
	root.add_child(duel)
	await process_frame
	var duel_log: Label = duel.log_label
	var before: float = duel_log.get_parent().size.y
	for i in 200:
		duel._on_log_message("Golpe número %d en el duelo" % i)
	await process_frame
	await process_frame
	check(duel_log.get_parent() is ScrollContainer and absf(duel_log.get_parent().size.y - before) < 1.0, "el registro del duelo no crece (%.0f)" % duel_log.get_parent().size.y)
	duel.queue_free()
	await process_frame

	print("[un reino cae: su gente no desaparece]")
	var player = await _new_game(Character.Role.CABALLERO)
	var target := -1
	for c: Castle in MD.castles:
		if c.kingdom != GM.player_kingdom and c.kingdom != KingdomEnums.Kingdom.NEUTRAL and not _people_of(RD, c.kingdom).is_empty():
			target = c.kingdom
			break
	check(target >= 0, "hay un reino ajeno con gente")
	var people := _people_of(RD, target)
	var conqueror: int = GM.player_kingdom
	for c: Castle in MD.castles:
		if c.kingdom == target:
			c.kingdom = conqueror
			RD.on_castle_taken(c, target, conqueror)
	check(_people_of(RD, target).is_empty(), "nadie queda en el reino caído")
	var visible := 0
	var joined := 0
	for r in people:
		if r in RD.courtiers(r.kingdom) or r in RD.commoners(r.kingdom):
			if RD.kingdom_has_castles(r.kingdom):
				visible += 1
		if r.kingdom == conqueror:
			joined += 1
	check(visible == people.size(), "los %d se ven en algún reino vivo (%d)" % [people.size(), visible])
	check(joined > 0 and joined < people.size() or people.size() < 4, "parte se une al vencedor (%d/%d)" % [joined, people.size()])

	print("[partida antigua con gente varada]")
	var stray = RD.courtiers()[0]
	stray.kingdom = target
	check(SS.save_game("1") == OK and SS.load_game("1"), "guarda y carga")
	var stray2 = RD.get_relation(stray.person_name)
	check(stray2 != null and stray2.kingdom != target and RD.kingdom_has_castles(stray2.kingdom), "al cargar, el varado se recoloca")

	print("[la tropa elegida se mantiene]")
	player = GM.player_character
	var foe = RD.lords().filter(func(r): return r.kingdom != GM.player_kingdom)[0]
	for fam in [BattleEnums.Family.ARQUERIA, BattleEnums.Family.CABALLERIA]:
		player.assigned_family = fam
		var bm := BattleManager.new()
		bm.player_leader = player
		bm.start_battle(100, 100, false, player, foe.character, "el campo", [], [])
		bm.apply_assignments()
		check(bm.player_unit() != null and bm.player_unit().family() == fam, "Consejo: tu pelotón lleva la familia %d" % fam)
		# Se rehace el despliegue (cambiar el reparto): la elección no se pierde.
		bm.reuse_terrain = true
		bm.start_battle(100, 100, false, player, foe.character, "el campo", [], [])
		check(bm.player_unit().family() == fam, "tras rehacer las tropas sigue la familia %d" % fam)
	player.assigned_family = -1
	var ally_lord = RD.get_relation(RD.liege_name) if not RD.liege_name.is_empty() else foe
	var bm2 := BattleManager.new()
	bm2.player_leader = player
	bm2.start_battle(100, 100, false, player, foe.character, "el campo", [], [])
	if bm2.player_unit() != null:
		var want := (bm2.player_unit().family() + 1) % 4
		bm2.player_family = want   # como si el general hubiera accedido en la negociación
		bm2.reuse_terrain = true
		bm2.start_battle(100, 100, false, player, foe.character, "el campo", [], [])
		check(bm2.player_unit().family() == want, "lo negociado sobrevive a rehacer las tropas")

	print("[adiós al camino mercenario]")
	player.role = Character.Role.MERCENARIO
	GM.starting_role = Character.Role.CAPITAN
	check(SS.save_game("1") == OK and SS.load_game("1"), "guarda una partida mercenaria")
	check(GM.player_character.role == Character.Role.INAFILIADO, "Mercenario -> No afiliado")
	check(GM.starting_role == Character.Role.INAFILIADO, "meta de Capitán -> No afiliado")
	var p2: Character = GM.player_character
	p2.role = Character.Role.CONDOTIERO
	var home: Castle = MD.get_castle_by_id(GM.home_castle_id)
	home.owner_name = p2.full_name()
	RP.migrate_legacy_role(p2)
	check(p2.role == Character.Role.NOBLEZA_BAJA, "Condotiero con castillo -> Nobleza Baja")
	for c: Castle in MD.castles:
		if c.owner_name == p2.full_name():
			c.owner_name = "Nadie"
	p2.role = Character.Role.CONDOTIERO
	RP.migrate_legacy_role(p2)
	check(p2.role == Character.Role.INAFILIADO, "Condotiero sin castillo -> No afiliado")
	for role in [Character.Role.CABALLERO, Character.Role.NOBLEZA_ALTA, Character.Role.DUQUE, Character.Role.SOLDADO]:
		var tmp := Character.new()
		tmp.role = role
		check(RP.landless_role(tmp) == Character.Role.INAFILIADO, "sin tierras %s -> No afiliado" % Character.role_name_for(role))

	print("FALLOS: %d" % fails)
	quit()
