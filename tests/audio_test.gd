extends SceneTree
# Audio: cada contexto/cultura tiene pista, sin repeticiones seguidas, variantes de efectos,
# ambiente por escena y que todos los archivos nuevos cargan.

var fails := 0

func check(c: bool, what: String) -> void:
	print(("  ok  " if c else "  FALLA ") + what)
	if not c:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _exists(t: String) -> bool:
	return ResourceLoader.exists("res://assets/music/%s.ogg" % t)

func _run() -> void:
	var MC = load("res://scripts/resources/music_catalog.gd")
	var Music = root.get_node("Music")
	var Sfx = root.get_node("Sfx")
	var Amb = root.get_node("Ambience")
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")

	print("[pistas por contexto y cultura]")
	var missing: Array[String] = []
	for ctx in MC.POOLS:
		for t in MC.POOLS[ctx]:
			if not _exists(t):
				missing.append(t)
	for ck in MC.CULTURE_KEYS:
		for pre in ["map_", "castle_"]:
			if not _exists(pre + ck):
				missing.append(pre + ck)
	for s in MC.STINGS:
		if not _exists(s):
			missing.append(s)
	check(missing.is_empty(), "todas las pistas existen %s" % [missing])
	for ctx in ["duel", "battle"]:
		for t in MC.POOLS[ctx]:
			check(_exists(t + "_tension"), "%s tiene capa de tensión" % t)
	var loaded_ok := true
	for ctx in MC.POOLS:
		for t in MC.POOLS[ctx]:
			if _exists(t) and load("res://assets/music/%s.ogg" % t) == null:
				loaded_ok = false
	check(loaded_ok, "las pistas cargan")
	var pools_ok := true
	for c in range(MC.CULTURE_KEYS.size()):
		for ctx in ["map", "castle", "travel"]:
			var pl: Array = MC.pool(ctx, c, _exists)
			if not (pl.size() >= 3 and pl.has(("castle_" if ctx == "castle" else "map_") + MC.CULTURE_KEYS[c])):
				pools_ok = false
				print("    sin su cultura: %s/%s %s" % [ctx, MC.CULTURE_KEYS[c], pl])
	check(pools_ok, "mapa, castillo y viaje incluyen la pieza de cada cultura")

	print("[sin repetir seguidas]")
	for ctx in ["map", "castle", "travel", "court", "duel", "battle", "mourning", "captivity"]:
		var last := ""
		var repeats := 0
		var seen := {}
		for i in 50:
			var t: String = MC.pick(ctx, 2, last, _exists)
			if t == last:
				repeats += 1
			seen[t] = true
			last = t
		check(repeats == 0 and seen.size() >= 2, "%s: 50 elecciones, %d repetidas seguidas, %d piezas distintas" % [ctx, repeats, seen.size()])

	print("[efectos con variantes]")
	for s in ["hit", "clash", "crit", "whoosh", "guard", "push", "melee", "arrows", "shout"]:
		check(Sfx.variant_count(s) >= 5, "%s: %d versiones" % [s, Sfx.variant_count(s)])
	for s in ["month_turn", "travel_hop", "letter", "achievement", "level_up", "chains", "execution", "story", "plot"]:
		check(Sfx.variant_count(s) >= 1, "sonido «%s» cargado" % s)
	var picks := {}
	var last_s = null
	var srep := 0
	for i in 40:
		var st = Sfx._pick("hit")
		if st == last_s:
			srep += 1
		picks[st] = true
		last_s = st
	check(picks.size() >= 4 and srep == 0, "hit: %d variantes usadas en 40 golpes, %d repetidas seguidas" % [picks.size(), srep])

	print("[avisos de eventos]")
	check(Amb.event_cue({"id": "cautiverio"}) == "chains", "cautiverio → cadenas")
	check(Amb.event_cue({"id": "story_herejia_1", "_story": "story_herejia"}) == "story", "historia → campana")
	check(Amb.event_cue({"id": "amb_usurpar", "amb_owner": "X"}) == "plot", "complot → intriga")
	check(Amb.event_cue({"id": "bandidos"}) == "letter", "evento corriente → carta")

	print("[música y ambiente por escena]")
	var p = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	GM.start_new_game(p, MD.castles[0].castle_id)
	await process_frame
	change_scene_to_file("res://scenes/map/map.tscn")
	await create_timer(0.8).timeout
	var culture: int = Music._location_culture()
	var ck: String = MC.culture_key(culture)
	check(Music.current_context == "map", "mapa en casa → contexto map (%s)" % Music.current_context)
	check(MC.pool("map", culture, _exists).has(Music.current_track), "pista del mapa de su pool: %s (cultura %s)" % [Music.current_track, ck])
	check(Amb.current in ["amb_wind", "amb_sea"], "ambiente del mapa: %s" % Amb.current)
	GM.current_castle = MD.get_castle_by_id(GM.home_castle_id)
	change_scene_to_file("res://scenes/castle_interior/castle_interior.tscn")
	await create_timer(0.8).timeout
	check(Music.current_context == "castle" and MC.pool("castle", culture, _exists).has(Music.current_track), "castillo → %s" % Music.current_track)
	check(Amb.current == "amb_castle", "ambiente del castillo: %s" % Amb.current)
	change_scene_to_file("res://scenes/relations/relations.tscn")
	await create_timer(0.8).timeout
	check(Music.current_context == "court", "relaciones → corte (%s)" % Music.current_track)
	# Viaje: lejos de casa suena el camino.
	var travel = root.get_node_or_null("TravelData")
	if travel != null:
		var far = null
		for c in MD.castles:
			if c.castle_id != GM.home_castle_id and not c.kingdom in Amb.COASTAL_KINGDOMS:
				far = c
				break
		if far != null:
			travel.location_id = far.castle_id
			travel.location_changed.emit(far.castle_id)
			change_scene_to_file("res://scenes/map/map.tscn")
			await create_timer(0.8).timeout
			check(Music.current_context == "travel", "lejos de casa → viaje (%s)" % Music.current_track)
			check(Amb.current == "amb_road", "ambiente del camino: %s" % Amb.current)
			travel.location_id = GM.home_castle_id
	# Rotación: otra pieza del mismo contexto, nunca la misma.
	change_scene_to_file("res://scenes/castle_interior/castle_interior.tscn")
	await create_timer(0.6).timeout
	var before: String = Music.current_track
	Music._rotate()
	check(Music.current_track != before and Music.current_context == "castle", "rotación: %s → %s" % [before, Music.current_track])
	# Fanfarria de una vez.
	Music.sting()
	await process_frame
	check(Music._sting != null and Music._sting.playing, "fanfarria suena")
	print("FALLAS: ", fails)
	quit(fails)
