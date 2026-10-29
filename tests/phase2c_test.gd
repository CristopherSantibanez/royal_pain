extends SceneTree
# Fase 2C: viajeros entre reinos (rutas, «Tu zona», encuentro con retrato, guardado)
# y gestor de personajes (listar, duplicar, renombrar, borrar, exportar, importar en user://_pruebas).

var fails := 0

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(5)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var TD = root.get_node("TravelData")
	var RD = root.get_node("RelationsData")
	var TR = root.get_node("TravelerData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var SS = load("res://scripts/resources/save_system.gd")
	var player = CL.make_test_character("Sir Viajero", CH.Role.CABALLERO)
	player.gold = 500
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame
	print("[viajeros]")
	check(SS.MODULES.has("TravelerData"), "TravelerData en SaveSystem.MODULES")
	# Elige a alguien que pueda viajar y un destino lejano.
	var who = null
	for r in RD.relations:
		if TR._valid(r):
			who = r
			break
	check(who != null, "hay gente que puede viajar")
	var start := ""
	for c in MD.castles:
		if c.kingdom == who.kingdom:
			start = c.castle_id
			break
	TR.travelers.clear()
	check(TR.start_trip(who.person_name, "errand", start), "se pone en camino")
	var t: Dictionary = TR.get_traveler(who.person_name)
	var path: Array = TD.path_to(t.dest, start)
	check(path.size() >= TR.MIN_HOPS, "destino a varios tramos (%d)" % path.size())
	TR.advance_all()
	check(t.at == path[0] and t.from == start, "avanza un tramo por la ruta")
	check(who.kingdom == MD.get_castle_by_id(t.at).kingdom, "su reino es el del castillo donde está")
	# El jugador está en ese castillo: aparece en «Tu zona».
	TD.location_id = t.at
	check(RD.in_area(who) and who in RD.people_in_area(), "aparece en «Tu zona»")
	var e: Dictionary = TR.meeting_event(t)
	check(e.speaker == who.person_name and RD.get_relation(e.speaker).character != null, "encuentro con retrato del viajero")
	check(e.options.size() == 5, "conversar, séquito, reto, trueque, dejar pasar")
	GM.pending_event = {}
	GM.event_queue.clear()
	t.met = false
	var old_meet = TR.MEET_CHANCE
	for i in 20:
		t.met = false
		TR._check_meeting(false)
		if not GM.pending_event.is_empty():
			break
	check(GM.pending_event.get("trav_owner", "") == who.person_name, "el encuentro se pone en cola")
	GM.resolve_pending_event(0, who)
	check(TR.take_conversation() == who.person_name, "«Conversar» deja la charla para el mapa")
	# Guardado.
	var st: Dictionary = TR.save_state()
	TR.reset()
	TR.load_state(JSON.parse_string(JSON.stringify(st)))
	check(TR.get_traveler(who.person_name).get("dest", "") == t.dest, "los viajeros se guardan")
	TR.load_state({})
	check(TR.travelers.is_empty(), "partida antigua: sin viajeros")
	# Llegar al destino: deja de viajar y se queda allí.
	TR.load_state(st)
	for i in 20:
		TR.advance_all()
	check(not TR.is_traveling(who.person_name) and who.kingdom == MD.get_castle_by_id(t.dest).kingdom, "al llegar se queda en el destino")
	for i in 24:
		GM.advance_turn()
	check(TR.travelers.size() <= TR.MAX_TRAVELERS, "nunca más de %d viajeros (%d)" % [TR.MAX_TRAVELERS, TR.travelers.size()])

	print("[mis personajes]")
	var CM = load("res://scenes/character_manager/character_manager.gd")
	check(CL.characters_dir().begins_with("user://_pruebas"), "las pruebas usan user://_pruebas")
	var c = CL.make_test_character("Gestor Prueba", CH.Role.CABALLERO)
	var p: String = CL.save_character(c, true)
	check(p in CM.list_paths(), "aparece en la lista")
	var copy: String = CM.duplicate_character(p)
	check(not copy.is_empty() and copy != p and copy in CM.list_paths(), "duplicar")
	check(CM.rename_character(copy, "Copia", "Renombrada") and CL.load_character(copy).full_name() == "Copia Renombrada", "renombrar")
	check(not CM.rename_character(copy, "  ", ""), "no se renombra sin nombre")
	var out := "user://_pruebas/export_prueba.json"
	check(CM.export_character(copy, out) and FileAccess.file_exists(out), "exportar")
	var imported: String = CM.import_character(out)
	check(not imported.is_empty() and CL.load_character(imported).full_name() == "Copia Renombrada", "importar")
	var bad := FileAccess.open("user://_pruebas/malo.json", FileAccess.WRITE)
	bad.store_string("{\"no\": 1}")
	bad.close()
	check(CM.import_character("user://_pruebas/malo.json").is_empty(), "importar un archivo inválido falla")
	for fp in [copy, imported, p]:
		check(CM.delete_character(fp) and not FileAccess.file_exists(fp) and not FileAccess.file_exists(fp + ".bak"), "borrar " + fp.get_file())
	DirAccess.remove_absolute(out)
	DirAccess.remove_absolute("user://_pruebas/malo.json")
	# La pantalla se construye sin errores.
	var scene = load("res://scenes/character_manager/character_manager.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.get_child_count() > 0, "la pantalla se construye")
	scene.queue_free()
	print("FALLAS: ", fails)
	quit(fails)
