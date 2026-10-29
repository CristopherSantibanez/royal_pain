extends SceneTree
# Combates de eventos (duelo y escaramuza), encargo de combate y límites de la cámara del mapa.

func _initialize() -> void:
	_run.call_deferred()

func _play_battle(scene) -> void:
	var turns := 0
	while not scene.battle.is_over and turns < 30:
		# El jugador ataca con lo que puede y pasa turno (la IA juega su parte).
		for u in scene.battle.units:
			if scene.battle.is_active() if false else true:
				pass
		scene.battle.end_player_turn()
		turns += 1
		await process_frame

func _run() -> void:
	var GM = root.get_node("GameManager")
	var CS = root.get_node("CombatSetup")
	var MD = root.get_node("MapData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var EC = load("res://scripts/resources/event_catalog.gd")
	var player = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	player.combat = 14
	player.defense = 10
	GM.start_new_game(player, MD.castles[0].castle_id)
	var home = MD.get_castle_by_id(GM.home_castle_id)
	home.garrison_size = 100

	# 1. Duelo de evento: el insulto en la taberna.
	var insult: Dictionary = {}
	for e in EC.EVENTS:
		if e.id == "insulto":
			insult = e
	var fight: Dictionary = insult.options.filter(func(o): return o.has("fight"))[0].fight
	var honor_before: int = player.honor
	var scene_path: String = CS.begin_event_fight(fight, insult.title)
	print("Duelo de evento -> escena ", scene_path.get_file(), " · rival: ", CS.enemy_character.full_name())
	change_scene_to_file(scene_path)
	await create_timer(0.5).timeout
	var combat = current_scene
	combat.enemy_character.current_health = 3
	var guard := 0
	while not combat.duel.is_over and guard < 30:
		if combat.player_turn:
			combat._player_action(0)
		await create_timer(1.4).timeout
		guard += 1
	print("Duelo terminado: %s · honor %d -> %d · resumen: %s" % [combat.duel.is_over, honor_before, player.honor, CS.last_result_text.left(160)])

	# 2. Escaramuza de evento: bandidos con la guarnición.
	var bandits: Dictionary = {}
	for e in EC.EVENTS:
		if e.id == "bandidos":
			bandits = e
	var battle_fight: Dictionary = bandits.options.filter(func(o): return o.has("fight") and o.fight.type == "battle")[0].fight
	CS.last_result_text = ""
	scene_path = CS.begin_event_fight(battle_fight, bandits.title)
	print("Escaramuza -> escena %s · %d de los tuyos contra %d" % [scene_path.get_file(), CS.skirmish.player_soldiers, CS.skirmish.enemy_soldiers])
	change_scene_to_file(scene_path)
	await create_timer(0.6).timeout
	var battle_scene = current_scene
	print("Título: ", battle_scene.title_label.text.replace("\n", " / "))
	var garrison_before: int = home.garrison_size
	await _play_battle(battle_scene)
	await create_timer(1.5).timeout
	print("Escaramuza terminada: %s · guarnición %d -> %d · cartel: %s" % [battle_scene.battle.is_over, garrison_before, home.garrison_size,
		battle_scene.result_label.text.get_slice("\n\n", 2).left(140)])
	print("Escaramuza pendiente limpia: ", CS.skirmish.is_empty(), " · desenlace pendiente limpio: ", CS.pending_outcome.is_empty())

	# 3. Encargo de combate.
	var MC = load("res://scripts/resources/mission_catalog.gd")
	var MDa = root.get_node("MissionData")
	var template: Dictionary = {}
	for m in MC.TEMPLATES:
		if m.id == "bandidos":
			template = m.duplicate(true)
	template["uid"] = "t1"
	template["giver"] = root.get_node("RelationsData").liege_name
	template["progress"] = 0
	MDa.accept(template)
	GM.actions_remaining = 2
	print("Botón del encargo: ", MDa.action_label(MDa.find("t1")), " · bloqueo: '", MDa.action_blocker(MDa.find("t1")), "'")
	scene_path = MDa.start_fight("t1")
	change_scene_to_file(scene_path)
	await create_timer(0.6).timeout
	await _play_battle(current_scene)
	await create_timer(1.5).timeout
	print("Encargo tras el combate: activo=%s · cumplidos %d fallidos %d" % [not MDa.find("t1").is_empty(), MDa.completed_count, MDa.failed_count])

	print("¿Sucesión pendiente? ", root.get_node("DynastyData").needs_succession(), " · crónica: ", root.get_node("WorldEvents").chronicle.back() if "chronicle" in root.get_node("WorldEvents") else "")
	if root.get_node("DynastyData").needs_succession():
		print("(muerte del comandante: se omite la prueba de cámara)")
		quit()
		return
	# 4. Cámara: ¿se ven los bordes del mapa por encima de la interfaz?
	change_scene_to_file("res://scenes/map/map.tscn")
	await create_timer(0.6).timeout
	var cam = current_scene.camera
	cam.focus_on(Vector2(cam.map_size.x / 2, 0), true)
	var top_edge_screen: float = (0 - cam.position.y) * cam.zoom.y + root.get_visible_rect().size.y / 2
	cam.focus_on(Vector2(cam.map_size.x / 2, cam.map_size.y), true)
	var bottom_edge_screen: float = (cam.map_size.y - cam.position.y) * cam.zoom.y + root.get_visible_rect().size.y / 2
	print("Borde superior del mapa en pantalla y=%.0f (barra: %.0f) · borde inferior y=%.0f (paneles desde %.0f) · zoom mín %.2f" % [
		top_edge_screen, cam.hud_top, bottom_edge_screen, root.get_visible_rect().size.y - cam.hud_bottom, cam.min_zoom])
	quit()
