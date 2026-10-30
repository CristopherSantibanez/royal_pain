extends SceneTree
# Capturas: llamada a filas en el mapa, batalla con aliados, reto de la IA, duelo singular y traición.

const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"

func _initialize() -> void:
	_run.call_deferred()

func _save(name: String, wait: float = 0.7) -> void:
	await create_timer(wait).timeout
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	print("captura ", name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	seed(5)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var AD = root.get_node("ArmyData")
	var RD = root.get_node("RelationsData")
	var CS = root.get_node("CombatSetup")
	var TD = root.get_node("TravelData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var IC = load("res://scripts/resources/invitation_catalog.gd")
	var p = CL.make_test_character("Sir Alaric", CH.Role.CAMPESINO)
	p.honor = 65
	p.combat = 14
	p.defense = 12
	GM.start_new_game(p, MD.castles[0].castle_id)
	await process_frame
	var home = MD.get_castle_by_id(GM.home_castle_id)
	home.garrison_size = 90
	var neighbor = MD.get_castle_by_id(home.connected_castle_ids[0])
	var raid = AD.create_army(neighbor.owner_name, neighbor.kingdom, 70, neighbor.castle_id)
	raid.origin_castle_id = neighbor.castle_id
	raid.current_castle_id = home.castle_id
	raid.pending_battle = true
	GM.pending_event = IC.army_event(raid, home, BattleEnums.Side.DEFENSOR, home.owner_name, home.owner_name, true)
	change_scene_to_file("res://scenes/map/map.tscn")
	await _save("b2_01_llamada_a_filas", 1.2)

	# Batalla campal con aliados: tu pelotón (azul) entre los de tu anfitrión (verde).
	GM.pending_event = {}
	var enemy = null
	for id in home.connected_castle_ids:
		var c = MD.get_castle_by_id(id)
		if c.kingdom != home.kingdom:
			enemy = c
	if enemy == null:
		enemy = neighbor
	var fe: Dictionary = IC.field_event(home, enemy, home.owner_name, home.owner_name, true)
	change_scene_to_file(CS.begin_event_fight(fe.options[0].fight, fe.title))
	await create_timer(0.8).timeout
	var scene = current_scene
	var b = scene.battle
	b.weather = BattleEnums.Weather.DESPEJADO
	b.time_of_day = BattleEnums.TimeOfDay.DIA
	var mine = b.units.filter(func(u): return b.is_player_unit(u))[0]
	scene.selected = mine
	scene._refresh()
	await _save("b2_02_batalla_con_aliados", 1.0)

	# La IA reta a tu jefe.
	var foe = b.active_units(b._other_side(b.player_side))[0]
	foe.cell = mine.cell + Vector2i(1, 0) if b.unit_at(mine.cell + Vector2i(1, 0)) == null else mine.cell + Vector2i(0, 1)
	foe.leader().combat = 18
	for i in 80:
		foe.has_acted = false
		if b._ai_try_challenge(b._other_side(b.player_side)):
			break
	scene._refresh()
	await _save("b2_03_reto_de_la_ia")
	scene._answer_challenge(true)
	await create_timer(1.6).timeout
	await _save("b2_04_duelo_singular")
	# termina el duelo para seguir
	for ch in scene.get_children():
		if ch is CanvasLayer and ch.get_child_count() > 0 and "embedded" in ch.get_child(0):
			var d = ch.get_child(0)
			var guard := 0
			while not d.duel.is_over and guard < 200:
				Engine.time_scale = 6.0
				if d.player_turn:
					d._player_action(0)
				await create_timer(0.25).timeout
				guard += 1
			Engine.time_scale = 1.0
			d._on_volver_menu_pressed()
	await create_timer(0.5).timeout

	# Traición: tus pelotones se pasan al enemigo (en una batalla nueva).
	b.is_over = true
	p.current_health = p.max_health
	p.wound_months = 0
	change_scene_to_file(CS.begin_event_fight(fe.options[0].fight, fe.title))
	await create_timer(0.8).timeout
	scene = current_scene
	b = scene.battle
	print("traición: ", scene._betrayal_blocker())
	if not b.is_over and scene._betrayal_blocker() == "":
		scene._on_betray_pressed()
		scene._refresh()
		await _save("b2_05_traicion_confirmar", 0.4)
		scene._on_betray_pressed()
		await _save("b2_06_traicion", 0.9)
	quit()
