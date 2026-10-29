extends SceneTree
# Historias encadenadas (StoryData + StoryCatalog):
#  1) catálogo: toda opción lleva a un paso o a un final; todo final es alcanzable; pasos y finales existen.
#  2) cada historia arranca con sus condiciones y se recorre hasta CADA final con decisiones guionizadas
#     (resolviendo eventos de verdad por la cola de GameManager; combates con begin_event_fight/apply_outcome).
#  3) marcas recordadas, pasos de viaje (esperan a que llegues; plazo vencido → final de abandono).
#  4) ritmo en 30 años, guardado a mitad de historia y partidas antiguas.

var fails := 0
var EC
var GM; var MD; var RD; var SD; var CS; var TD; var CL; var CH; var SC; var SS

func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok  ", what)
	else:
		fails += 1
		print("  FALLA ", what)

func _initialize() -> void:
	_run.call_deferred()

func _new_game(role: int) -> void:
	var p = CL.make_test_character("Sir Prueba", role)
	p.gold = 2000
	p.honor = 60
	p.combat = 14
	p.defense = 12
	GM.start_new_game(p, MD.castles[0].castle_id)
	GM.event_queue.clear()
	GM.pending_event = {}
	var home = MD.get_castle_by_id(GM.home_castle_id)
	home.garrison_size = 200
	home.gold = 500
	if RD.liege_name.is_empty():
		RD.liege_name = home.owner_name

# --- 1) análisis estático del catálogo ---

func _flows(o: Dictionary) -> Array:
	# Desenlaces posibles de una opción: [{set, next|end}, ...]
	var out: Array = []
	if o.has("fight"):
		for k in ["win", "lose"]:
			out.append(o.fight.get(k, {}).get("effects", {}).get("story", {}))
	elif o.has("chance"):
		for k in ["success", "failure"]:
			out.append(o.get(k, {}).get("effects", {}).get("story", {}))
	else:
		out.append(o.get("effects", {}).get("story", {}))
	return out

func _static_checks() -> void:
	print("[catálogo]")
	var personalities := Character.Personality.keys()
	for c: Dictionary in SC.CHAINS:
		var reached := {}
		var ok: bool = c.steps.has(c.start)
		for step_id in c.steps:
			var step: Dictionary = c.steps[step_id]
			if step.has("timeout"):
				reached[step.timeout] = true
				ok = ok and c.endings.has(step.timeout)
			var has_plain := false
			for o: Dictionary in step.options:
				if not o.has("fight") and not o.has("if") and not o.get("requires", {}).has("gold") and not o.get("requires", {}).has("healthy"):
					has_plain = true
				if o.has("fight") and o.fight.foe.has("personality"):
					ok = ok and str(o.fight.foe.personality) in personalities
				for f: Dictionary in _flows(o):
					if f.has("end"):
						reached[f.end] = true
						ok = ok and c.endings.has(f.end)
					elif f.has("next"):
						ok = ok and c.steps.has(f.next)
					else:
						ok = false
						print("    opción sin salida en %s/%s: %s" % [c.id, step_id, o.label])
			# Siempre hay una salida sin combate, oro ni condiciones (para campesinos, heridos y pobres).
			if not has_plain:
				print("    %s/%s sin opción libre" % [c.id, step_id])
			ok = ok and has_plain
		var all_endings := true
		for e in c.endings:
			if not reached.has(e):
				all_endings = false
				print("    final inalcanzable: %s/%s" % [c.id, e])
		check(ok and all_endings, "%s: %d pasos, %d finales, todo enlazado" % [c.id, c.steps.size(), c.endings.size()])
	check(SC.CHAINS.size() >= 10, "%d historias en el catálogo" % SC.CHAINS.size())

# --- 2) recorrer cada final ---

## Planes para llegar a un final: lista de [paso, índice de opción visible por etiqueta, desenlace "win"/"lose"/"success"/"failure"/""].
func _paths(c: Dictionary) -> Array:
	# Búsqueda en profundidad: caminos (secuencias de (paso, etiqueta, desenlace)) hasta cada final.
	var result := {}
	var stack: Array = [[c.start, [], []]]   # paso, camino, marcas
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var step: Dictionary = c.steps[item[0]]
		for o: Dictionary in step.options:
			if o.has("if") and not str(o.if) in item[2]:
				continue
			if o.has("if_not") and str(o.if_not) in item[2]:
				continue
			var outcomes: Array = ["win", "lose"] if o.has("fight") else (["success", "failure"] if o.has("chance") else [""])
			for oc in outcomes:
				var f: Dictionary = (o.fight[oc].effects.get("story", {}) if oc in ["win", "lose"] else (o[oc].effects.get("story", {}) if oc != "" else o.effects.get("story", {})))
				var flags: Array = item[2].duplicate()
				for s in f.get("set", []):
					flags.append(s)
				var path: Array = item[1] + [[item[0], o.label, oc]]
				if f.has("end"):
					if not result.has(f.end):
						result[f.end] = path
				elif f.has("next") and path.size() < 8:
					stack.append([f.next, path, flags])
	return result.values()

func _resolve_current(label: String, outcome: String) -> bool:
	var e: Dictionary = GM.pending_event
	if e.is_empty() or not str(e.get("_story", "")).begins_with("story_"):
		return false
	var idx := -1
	for i in e.options.size():
		# las etiquetas llevan el reparto ya rellenado: se compara la plantilla sin llaves
		if _matches(str(e.options[i].label), label):
			idx = i
	if idx < 0:
		print("    no encuentro «%s» en %s" % [label, e.options.map(func(o): return o.label)])
		return false
	var option: Dictionary = e.options[idx]
	if not EC.can_choose(option, GM.player_character, MD.get_castle_by_id(GM.home_castle_id)):
		print("    opción bloqueada: ", label)
		return false
	if option.has("chance"):
		# Forzar el desenlace: se aplica a mano la rama elegida, como haría apply_option.
		var branch: Dictionary = option[outcome]
		GM.event_option_chosen.emit(e, option)
		EC._apply_effects(branch.get("effects", {}), GM.player_character, MD.get_castle_by_id(GM.home_castle_id))
		if GM.pending_event == e:
			GM.pending_event = {}
		GM._pull_queued_event()
		return true
	GM.resolve_pending_event(idx)
	if option.has("fight"):
		var scene: String = CS.begin_event_fight(option.fight, e.title)
		if scene.is_empty():
			print("    el combate no arrancó")
			return false
		CS.apply_outcome(outcome == "win")
		CS.skirmish = {}
	return true

func _matches(filled: String, template: String) -> bool:
	# Compara la etiqueta rellenada con la plantilla: los trozos fijos de la plantilla deben aparecer en orden.
	var pieces := template.split("{")
	var pos := 0
	for i in pieces.size():
		var piece: String = pieces[i]
		if i > 0:
			var close := piece.find("}")
			piece = piece.substr(close + 1) if close >= 0 else piece
		if piece.is_empty():
			continue
		var at := filled.find(piece, pos)
		if at < 0:
			return false
		pos = at + piece.length()
	return true

func _advance_until_event(max_months: int) -> bool:
	for i in max_months:
		if not GM.pending_event.is_empty() and str(GM.pending_event.get("_story", "")).begins_with("story_"):
			return true
		GM.pending_event = {}
		GM._pull_queued_event()
		if str(GM.pending_event.get("_story", "")).begins_with("story_"):
			return true
		GM.pending_event = {}
		GM.advance_turn()
		# Viajes: si el paso pide estar en otro castillo, se teletransporta (los viajes se prueban aparte).
		var target: String = SD.travel_target()
		if not target.is_empty() and TD.current_castle_id() != target:
			TD.location_id = target
			TD.location_changed.emit(target)
	return not GM.pending_event.is_empty() and str(GM.pending_event.get("_story", "")).begins_with("story_")

func _reset_between_paths() -> void:
	SD.reset()
	GM.event_queue.clear()
	GM.pending_event = {}
	CS.pending_outcome = {}
	var p = GM.player_character
	p.gold = 2000
	p.honor = 60
	p.current_health = p.max_health
	p.wound_months = 0
	var home = MD.get_castle_by_id(GM.home_castle_id)
	home.garrison_size = 200
	home.gold = 500
	var cd = root.get_node_or_null("CaptureData")
	if cd != null and cd.has_method("reset"):
		cd.reset()
	var td = root.get_node("TravelData")
	td.location_id = GM.home_castle_id

func _role_for(c: Dictionary) -> int:
	var cond: Dictionary = c.cond
	var rank: int = clampi(int(cond.get("min_rank", 2)), int(cond.get("min_rank", 0)), int(cond.get("max_rank", 6)))
	if cond.has("max_rank") and int(cond.max_rank) <= 1:
		return CH.Role.SOLDADO
	match rank:
		0: return CH.Role.CAMPESINO
		1: return CH.Role.SOLDADO
		2: return CH.Role.CABALLERO
		3: return CH.Role.NOBLEZA_BAJA
		_: return CH.Role.NOBLEZA_ALTA

func _walk_all() -> void:
	print("[recorridos]")
	for c: Dictionary in SC.CHAINS:
		var endings_seen := {}
		_new_game(_role_for(c))   # una partida por historia (crear partida es lento); entre caminos solo se reinicia la historia
		for path: Array in _paths(c):
			_reset_between_paths()
			if c.cond.get("needs_castle", false):
				MD.get_castle_by_id(GM.home_castle_id).owner_name = GM.player_character.full_name()
			if c.cond.has("months"):
				GM.current_month = int(c.cond.months[0])
			if not SD.start(c.id):
				print("    no arrancó ", c.id)
				break
			var ok := true
			if OS.get_environment("STORY_TRACE") != "":
				print("    · ", c.id, " ", path)
			for leg: Array in path:
				if OS.get_environment("STORY_TRACE") != "":
					print("      paso ", leg)
				if not _advance_until_event(8) or not _resolve_current(leg[1], leg[2]):
					ok = false
					print("    se atascó en %s/%s" % [c.id, leg[0]])
					break
			if ok and not SD.is_active() and not SD.history.is_empty():
				endings_seen[SD.history.back().ending] = true
		check(endings_seen.size() == c.endings.size(), "%s: %d/%d finales alcanzados (%s)" % [c.id, endings_seen.size(), c.endings.size(), ", ".join(endings_seen.keys())])


func _labels() -> Array:
	return GM.pending_event.get("options", []).map(func(o): return str(o.label))

func _mechanics() -> void:
	print("[marcas]")
	_new_game(CH.Role.CABALLERO)
	SD.start("herejia")
	check(_advance_until_event(2), "la herejía empieza con un evento en cola")
	_resolve_current("Escucharlo", "")
	check("escuchado" in SD.active.flags, "la marca «escuchado» queda guardada")
	check(_advance_until_event(6), "llega el segundo paso")
	check(_labels().any(func(l): return l.begins_with("Mediar")), "con «escuchado» aparece «Mediar»: %s" % [_labels()])
	check(not _labels().any(func(l): return l.begins_with("Entregarlo")), "sin «denunciado» no aparece «Entregarlo»")
	check(not GM.pending_event.get("speaker", "").is_empty(), "el paso lo cuenta su señor (retrato en el evento)")
	check(not str(GM.pending_event.text).contains("{"), "textos rellenados: %s" % GM.pending_event.text.left(80))

	print("[viaje]")
	_reset_between_paths()
	SD.start("reliquia")
	_advance_until_event(2)
	_resolve_current("Seguir su rastro", "")
	var target: String = SD.travel_target()
	check(not target.is_empty() and target != GM.home_castle_id, "el paso siguiente pide viajar a %s" % target)
	for i in 3:
		GM.pending_event = {}
		GM.event_queue.clear()
		GM.advance_turn()
	check(SD.is_active() and not SD.active.awaiting, "sin llegar, el paso espera (no se lanza)")
	check(SD.summary_line().contains("Viaja a"), "el resumen avisa: %s" % SD.summary_line())
	GM.pending_event = {}
	TD.location_id = target
	TD.location_changed.emit(target)
	check(str(GM.pending_event.get("_story", "")) == "story_reliquia" or GM.event_queue.any(func(e): return str(e.get("_story", "")) == "story_reliquia"),
		"al llegar a %s se lanza el paso" % target)
	# Plazo vencido.
	_reset_between_paths()
	SD.start("reliquia")
	_advance_until_event(2)
	_resolve_current("Seguir su rastro", "")
	for i in 8:
		GM.pending_event = {}
		GM.event_queue.clear()
		GM.advance_turn()
	check(not SD.is_active() and SD.history.back().ending == "El santo perdido", "plazo vencido: final «%s»" % (SD.history.back().ending if not SD.history.is_empty() else "?"))

	print("[efectos en el mundo]")
	_reset_between_paths()
	SD.start("reliquia")
	var relic_before: bool = GM.player_character.equipment.any(func(e): return e.equipment_name == "Relicario de Aquisgrán")
	for leg in [["Seguir su rastro", ""], ["Comprársela (60)", ""], ["Quedártelo", ""]]:
		var t2: String = SD.travel_target()
		if not t2.is_empty():
			TD.location_id = t2
		_advance_until_event(4)
		_resolve_current(leg[0], leg[1])
	var relic_after: bool = GM.player_character.equipment.any(func(e): return e.equipment_name == "Relicario de Aquisgrán")
	check(not relic_before and relic_after, "quedarse el relicario da la pieza única")
	check(WD().chronicle.any(func(e): return str(e.text).begins_with("Historia «La reliquia robada»")), "el final queda en la crónica")

	_reset_between_paths()
	SD.start("peste")
	var plague_castle = MD.get_castle_by_id(SD.active.cast.castle)
	plague_castle.garrison_size = 100
	_advance_until_event(2)
	_resolve_current("Rezar y esperar", "")
	_advance_until_event(4)
	var before_plague: int = plague_castle.garrison_size
	_resolve_current("Resistir", "")
	check(plague_castle.garrison_size == int(before_plague * 0.7), "la peste se lleva al 30%% de la guarnición (%d → %d)" % [before_plague, plague_castle.garrison_size])

	_reset_between_paths()
	SD.start("boda")
	var lord_name: String = SD.active.cast.lord
	_advance_until_event(2)
	_resolve_current("Disfrutar de la fiesta", "")
	_advance_until_event(3)
	_resolve_current("Callar", "")
	check(RD.get_relation(lord_name) == null and RD.castles_of(lord_name).is_empty(), "el señor envenenado muere y le sucede otro (%s)" % lord_name)

	print("[condiciones]")
	_new_game(CH.Role.CAMPESINO)
	check(SD.eligible(SC.chain("revuelta_pueblo")) and not SD.eligible(SC.chain("revuelta_senor")), "un campesino vive la revuelta desde abajo, no como señor")
	check(not SD.eligible(SC.chain("cruzada")), "un campesino no toma la cruz")
	GM.current_month = 1
	check(not SD.eligible(SC.chain("torneo_amanado")), "no hay torneos en enero")
	GM.current_month = 12
	check(SD.eligible(SC.chain("bestia")), "la bestia aparece en invierno")

	print("[guardado]")
	_new_game(CH.Role.CABALLERO)
	SD.start("mercader")
	_advance_until_event(2)
	_resolve_current("Prestárselo (80)", "")
	var saved_step: String = SD.active.step
	check(SS.save_game() == OK, "guardar a mitad de historia")
	SD.reset()
	check(SS.load_game() and SD.is_active() and SD.active.step == saved_step and "prestado" in SD.active.flags, "al cargar sigue en «%s» con sus marcas" % saved_step)
	SD.load_state({})
	check(not SD.is_active() and SD.history.is_empty(), "partida antigua: sin historias, sin errores")
	SD.load_state({"active": {"chain": "herejia", "step": "no_existe"}})
	check(not SD.is_active(), "un paso que ya no existe se descarta al cargar")

	print("[atasco]")
	_reset_between_paths()
	SD.start("caido")
	_advance_until_event(2)
	GM.pending_event = {}   # el evento desaparece sin respuesta (p. ej. combate abandonado)
	for i in SD.STALL_MONTHS + 1:
		GM.pending_event = {}
		GM.event_queue.clear()
		GM.advance_turn()
	check(not SD.is_active(), "un paso sin respuesta se cierra a los %d meses" % SD.STALL_MONTHS)

func WD():
	return root.get_node("WorldEvents")

func _pacing() -> void:
	print("[ritmo: 30 años]")
	_new_game(CH.Role.CABALLERO)
	var started := 0
	var finished := 0
	var steps_by_month := {}
	var max_steps_month := 0
	var concurrent_bad := false
	var was_active := false
	for month in 360:
		var t: String = SD.travel_target()
		if not t.is_empty() and randf() < 0.5:
			TD.location_id = t
			TD.location_changed.emit(t)
		# Responde como un jugador: primera opción posible; combates resueltos al azar.
		var guard := 0
		while not GM.pending_event.is_empty() and guard < 6:
			guard += 1
			var e: Dictionary = GM.pending_event
			var is_story := str(e.get("_story", "")).begins_with("story_")
			if is_story:
				steps_by_month[month] = int(steps_by_month.get(month, 0)) + 1
				max_steps_month = maxi(max_steps_month, steps_by_month[month])
			var idx := -1
			for i in e.options.size():
				if EC.can_choose(e.options[i], GM.player_character, MD.get_castle_by_id(GM.home_castle_id)):
					idx = i
					break
			if idx < 0:
				GM.pending_event = {}
				GM._pull_queued_event()
				continue
			var option: Dictionary = e.options[idx]
			GM.resolve_pending_event(idx)
			if option.has("fight") and is_story:
				if not CS.begin_event_fight(option.fight, e.title).is_empty():
					CS.apply_outcome(randf() < 0.5)
					CS.skirmish = {}
		if SD.is_active() and not was_active:
			started += 1
		if GM.player_character == null or not GM.is_game_active:
			break
		GM.player_character.honor = maxi(GM.player_character.honor, 40)
		GM.player_character.gold = maxi(GM.player_character.gold, 200)
		was_active = SD.is_active()
		GM.advance_turn()
		if not GM.is_game_active:
			break
	finished = SD.history.size()
	print("    historias empezadas: %d · terminadas: %d · %s" % [started, finished, SD.history.map(func(h): return "%s→%s" % [h.title, h.ending])])
	check(finished >= 3 and finished <= 14, "en 30 años: %d historias (unas 3 por década)" % finished)
	check(not SD.history.any(func(h): return h.ending == "Sin final"), "ninguna queda «Sin final» si el jugador responde")
	check(max_steps_month <= 1, "nunca dos pasos de historia el mismo mes")

func _run() -> void:
	GM = root.get_node("GameManager")
	MD = root.get_node("MapData")
	RD = root.get_node("RelationsData")
	SD = root.get_node("StoryData")
	CS = root.get_node("CombatSetup")
	TD = root.get_node("TravelData")
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	SC = load("res://scripts/resources/story_catalog.gd")
	SS = load("res://scripts/resources/save_system.gd")
	EC = load("res://scripts/resources/event_catalog.gd")
	seed(11)
	_static_checks()
	_walk_all()
	_mechanics()
	_pacing()
	print("FALLAS: ", fails)
	quit(fails)
