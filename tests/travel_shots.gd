extends SceneTree
# Capturas y prueba de interfaz del viaje: ficha en el mapa, viaje con el botón, encuentro,
# castillo ajeno (acciones locales), audiencia y gobierno a distancia. Sin --headless guarda PNG.

const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots/"
var fails := 0

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(OUT + name)
		print("    captura ", name)

func _change(path: String) -> Node:
	change_scene_to_file(path)
	for i in 4:
		await process_frame
	return current_scene

func _run() -> void:
	seed(5)
	DirAccess.make_dir_recursive_absolute(OUT)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var TD = root.get_node("TravelData")
	var RD = root.get_node("RelationsData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var player = CL.make_test_character("Sir Viajero", CH.Role.CABALLERO)
	player.gold = 800
	player.fame = 20
	var home = null
	var foreign = null
	for c in MD.castles:
		if c.owner_name == RD.NO_LORD or c.kingdom == KingdomEnums.Kingdom.NEUTRAL:
			continue
		for n in c.connected_castle_ids:
			var nc = MD.get_castle_by_id(n)
			if nc.kingdom != c.kingdom and nc.kingdom != KingdomEnums.Kingdom.NEUTRAL and nc.owner_name != RD.NO_LORD:
				home = c
				foreign = nc
				break
		if home != null:
			break
	GM.start_new_game(player, home.castle_id)
	GM.current_month = 5
	GM.actions_remaining = 6
	GM.actions_per_turn = 6
	var map = await _change("res://scenes/map/map.tscn")
	check(map.get_node_or_null("PlayerToken") != null, "la ficha del jugador está en el mapa")
	map._on_castle_clicked(foreign)
	var btn: Button = map._btn_travel
	check(btn.visible and not btn.disabled, "botón de viaje: %s" % btn.text)
	await _shot("travel_01_mapa_ficha.png")
	# Forzamos un encuentro en el siguiente tramo.
	var old_base = TD.ENCOUNTER_BASE
	seed(1)
	btn.pressed.emit()
	await create_timer(1.0).timeout
	check(TD.is_at(foreign.castle_id), "viajó con el botón")
	if not TD.has_pending_encounter():
		TD.pending_encounter = {"id": "caballero_errante", "from": home.castle_id, "to": foreign.castle_id}
		map._show_encounter()
	check(map.event_overlay.visible, "el encuentro se muestra en el panel")
	await _shot("travel_02_encuentro.png")
	# Elegimos una opción sin combate.
	var ev: Dictionary = TD.encounter_event()
	var idx := 0
	for i in ev.options.size():
		if not ev.options[i].has("fight") and load("res://scripts/resources/event_catalog.gd").can_choose(ev.options[i], player, home):
			idx = i
	map._on_encounter_option_pressed(idx)
	check(not TD.has_pending_encounter(), "encuentro resuelto")
	map._on_event_close_pressed()

	print("[castillo ajeno]")
	GM.current_castle = foreign
	var ci = await _change("res://scenes/castle_interior/castle_interior.tscn")
	var labels: Array[String] = []
	for b0 in ci.action_buttons():
		labels.append(b0.text)
	print("    acciones: ", labels)
	check(labels.any(func(l): return l.begins_with("Pedir Audiencia")), "Pedir Audiencia")
	check(labels.any(func(l): return l.begins_with("Torneo de")), "torneo local")
	check(not labels.any(func(l): return l.begins_with("Movilizar")), "sin acciones de gobierno en castillo ajeno")
	check(ci.find_child("BtnObras", true, false) == null, "sin Obras en castillo ajeno")
	await _shot("travel_03_castillo_ajeno.png")
	var lord = TD.lord_relation(foreign)
	lord.affinity = 30
	ci._action_audiencia()
	await process_frame
	var panel = ci.get_child(ci.get_child_count() - 1)
	check(panel.has_method("_finish_with"), "panel de audiencia abierto")
	await _shot("travel_04_audiencia.png")
	panel.queue_free()
	await process_frame

	print("[gobierno a distancia]")
	GM.current_castle = home
	var ci2 = await _change("res://scenes/castle_interior/castle_interior.tscn")
	var remote_labels: Array[String] = []
	var disabled_train := false
	for b: Button in ci2.action_buttons():
		remote_labels.append(b.text)
		if b.text.begins_with("Entrenar"):
			disabled_train = b.disabled and (disabled_train or b.text.begins_with("Entrenar ("))
	print("    acciones: ", remote_labels)
	check(remote_labels.any(func(l): return l.begins_with("Movilizar") and l.ends_with("✉")), "movilizar por carta ✉")
	check(disabled_train, "entrenar exige estar presente")
	await _shot("travel_05_a_distancia.png")
	print("FALLAS: ", fails)
	quit(fails)
