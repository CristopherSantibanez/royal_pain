extends SceneTree
# Ambiciones de los PNJ: IA de utilidad, avance, desenlaces, complots contigo, ritmo y guardado.

var fails := 0

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

var GM; var MD; var RD; var AD; var WE; var CH; var CL; var SS; var EC

func _rel(name: String, kind: int, personality: int, kingdom: int) -> Relationship:
	var r := Relationship.new()
	r.person_name = name
	r.kind = kind
	r.kingdom = kingdom
	r.character = CL.make_test_character(name, CH.Role.CABALLERO)
	r.character.personality = personality
	RD.relations.append(r)
	return r

func _best(r: Relationship, runs: int = 200) -> Dictionary:
	var counts := {}
	for i in runs:
		var c: Dictionary = AD.choose(r)
		var id: String = c.get("id", "-")
		counts[id] = counts.get(id, 0) + 1
	return counts

func _top(counts: Dictionary) -> String:
	var best := ""
	for k in counts:
		if best.is_empty() or counts[k] > counts[best]:
			best = k
	return best

## Resuelve el evento pendiente con la primera opción permitida que no lleve a un combate.
func _resolve_pending() -> String:
	var guard := 0
	var last := ""
	while GM.has_pending_event() and guard < 6:
		guard += 1
		var e: Dictionary = GM.pending_event
		var castle = MD.get_castle_by_id(GM.home_castle_id)
		var idx := -1
		for i in e.options.size():
			var o: Dictionary = e.options[i]
			if o.get("start_duel", false) or o.has("fight") or not EC.can_choose(o, GM.player_character, castle):
				continue
			idx = i
			break
		if idx < 0:
			GM.pending_event = {}
			GM._pull_queued_event()
			continue
		var target = RD.get_relation(e.get("target", e.get("speaker", "")))
		last = GM.resolve_pending_event(idx, target)
	return last

func _event_with_act(e: Dictionary, act: String) -> int:
	for i in e.options.size():
		if e.options[i].get("amb_act", "") == act:
			return i
	return -1

func _run() -> void:
	seed(11)
	GM = root.get_node("GameManager"); MD = root.get_node("MapData"); RD = root.get_node("RelationsData")
	AD = root.get_node("AmbitionData"); WE = root.get_node("WorldEvents")
	CH = load("res://scripts/resources/character.gd"); CL = load("res://scripts/resources/character_loader.gd")
	SS = load("res://scripts/resources/save_system.gd")
	EC = load("res://scripts/resources/event_catalog.gd")
	var player = CL.make_test_character("Sir Alaric", CH.Role.NOBLEZA_BAJA)
	player.gender = CharacterEnums.Gender.MASCULINO
	player.gold = 5000
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame
	var k: int = GM.player_kingdom

	print("[utilidad por personalidad]")
	var cruel := _rel("Ser Cruel", Relationship.Kind.CORTESANO, CH.Personality.CRUEL, k)
	cruel.grudge = 85
	var c1 := _best(cruel)
	check(_top(c1) == "vengarse", "un cruel con rencor 85 quiere vengarse (%s)" % str(c1))
	var romantic := _rel("Doña Romántica", Relationship.Kind.CORTESANO, CH.Personality.ROMANTICO, k)
	romantic.character.gender = CharacterEnums.Gender.FEMENINO
	romantic.affection = 60
	var c2 := _best(romantic)
	check(_top(c2) == "casarse", "una romántica enamorada quiere casarse (%s)" % str(c2))
	var pious := _rel("Fray Piadoso", Relationship.Kind.CORTESANO, CH.Personality.PIADOSO, k)
	pious.character.role = CH.Role.NOBLEZA_BAJA   # ya noble: no busca ascender
	WE.married_lords[pious.person_name] = "X"
	AD.married_npcs[pious.person_name] = "X"
	var c3 := _best(pious)
	check(_top(c3) == "fe", "un piadoso casado y noble prefiere obras de fe (%s)" % str(c3))
	var lords: Array = RD.lords().filter(func(r): return r.kingdom != k and not RD.castles_of(r.person_name).is_empty())
	var schemer: Relationship = null
	for l in lords:
		if AD._usurp_victim(l) != "":
			schemer = l
			break
	if schemer == null:
		# Un señor menor en un reino ajeno: se le da un castillo del reino con más castillos.
		var by_k := {}
		for c in MD.castles:
			if c.kingdom != k and c.kingdom != KingdomEnums.Kingdom.NEUTRAL:
				by_k[c.kingdom] = by_k.get(c.kingdom, []) + [c]
		for kk in by_k:
			if by_k[kk].size() >= 2:
				schemer = _rel("Lord Menor", Relationship.Kind.SENOR, CH.Personality.AMBICIOSO, kk)
				by_k[kk][1].owner_name = schemer.person_name
				break
	if schemer == null:
		print("  (sin reinos ajenos con dos señores en este mundo: la conjura se prueba en tu reino)")
	if schemer != null:
		schemer.character.personality = CH.Personality.AMBICIOSO
		WE.married_lords.erase(schemer.person_name)
		var c4 := _best(schemer)
		check(c4.get("usurpar", 0) > 30, "un señor ambicioso conspira a menudo (%s)" % str(c4))
	var astute := _rel("Maese Astuto", Relationship.Kind.CORTESANO, CH.Personality.ASTUTO, k)
	astute.character.role = CH.Role.NOBLEZA_BAJA
	AD.married_npcs[astute.person_name] = "Y"
	var before_secret: Dictionary = _best(astute)
	AD.secrets.append({"month": GM.months_elapsed(), "text": "x"})
	var after_secret: Dictionary = _best(astute)
	check(not before_secret.has("chantaje") and after_secret.get("chantaje", 0) > 40, "sin secreto no chantajea; con secreto sí (%d/200)" % after_secret.get("chantaje", 0))
	AD.secrets.clear()

	print("[avance mensual]")
	AD.ambitions.clear()
	AD.ambitions["Ser Cruel"] = {"id": "vengarse", "kind": "venganza", "progress": 0.0, "rate": 0.25, "target": "", "held": 0}
	AD.last_plot_month = -100
	AD.plot_owner = ""
	GM.pending_event = {}
	GM.event_queue.clear()
	for i in 3:
		AD._on_month_passed(GM.current_month, GM.current_year)
	check(AD.ambitions.has("Ser Cruel") and is_equal_approx(float(AD.ambitions["Ser Cruel"].progress), 0.75), "progresa 0,25 al mes (%.2f)" % float(AD.ambitions.get("Ser Cruel", {}).get("progress", -1)))

	print("[complots contigo: unirte, delatar, aprovecharte]")
	var plot_lord: Relationship = null
	var victim_name := ""
	for l in RD.lords():
		if l.kingdom == k and not RD.castles_of(l.person_name).is_empty() and l.person_name != player.full_name():
			var v: String = AD._usurp_victim(l)
			if v != "" and v != player.full_name():
				plot_lord = l
				victim_name = v
				break
	if plot_lord == null:
		# Mundo sin dos señores en tu reino: se fabrica uno.
		plot_lord = _rel("Lord Intrigante", Relationship.Kind.SENOR, CH.Personality.AMBICIOSO, k)
		for l in RD.lords():
			if l.kingdom == k and l != plot_lord and not RD.castles_of(l.person_name).is_empty():
				victim_name = l.person_name
				break
	check(not victim_name.is_empty(), "hay conspirador (%s) y víctima (%s)" % [plot_lord.person_name, victim_name])
	for act in ["join", "denounce", "exploit"]:
		var a := {"id": "usurpar", "kind": "poder", "progress": 1.0, "rate": 0.1, "target": victim_name, "held": 0, "involve": true}
		AD.ambitions[plot_lord.person_name] = a
		var e: Dictionary = AD._player_event(plot_lord, a)
		check(not e.is_empty() and e.title == "Únete a mi conjura", "%s: se ofrece la conjura" % act)
		if e.is_empty():
			continue
		var honor0: int = player.honor
		var gold0: int = player.gold
		var grudge0: int = plot_lord.grudge
		GM.pending_event = e
		var idx := _event_with_act(e, act)
		var text: String = GM.resolve_pending_event(idx, plot_lord)
		print("    %s → %s" % [act, text.replace("\n", " | ").left(160)])
		match act:
			"join": check(text.contains("conjura") or text.contains("arrebata") or text.contains("humilla") or text.contains("cadalso") or text.contains("desgracia"), "unirte resuelve la conjura")
			"denounce": check(player.honor > honor0 and (plot_lord.grudge > grudge0 or RD.get_relation(plot_lord.person_name) != plot_lord), "delatar da honor y su odio")
			"exploit": check(player.gold > gold0 and player.honor < honor0, "aprovecharte: oro a cambio de honor")
		check(not AD.ambitions.has(plot_lord.person_name), "%s: la ambición se cierra" % act)
		if RD.get_relation(plot_lord.person_name) == null or RD.castles_of(plot_lord.person_name).is_empty():
			plot_lord = _rel("Lord Intrigante %s" % act, Relationship.Kind.SENOR, CH.Personality.AMBICIOSO, k)
			MD.castles.filter(func(c): return c.kingdom == k and c.owner_name != player.full_name() and c.owner_name != victim_name)

	print("[otros complots: cada tipo genera su evento]")
	var friend := _rel("Doña Amiga", Relationship.Kind.CORTESANO, CH.Personality.GENEROSO, k)
	friend.character.gender = CharacterEnums.Gender.FEMENINO
	friend.affection = 60
	friend.affinity = 40
	RD.liege_name = victim_name
	var cases := {"casarse": friend, "ascender": friend, "rivalidad": friend, "enriquecerse": friend, "fe": friend,
		"torneo": schemer if schemer != null else friend, "vengarse": cruel}
	for id in cases:
		var r: Relationship = cases[id]
		var a := {"id": id, "kind": "", "progress": 1.0, "rate": 0.1, "target": "", "held": 0, "involve": true}
		var e: Dictionary = AD._player_event(r, a)
		check(not e.is_empty() and e.options.size() >= 2 and not str(e.get("quote", "")).is_empty(), "%s: evento «%s» con frase" % [id, e.get("title", "?")])
	AD.secrets.append({"month": GM.months_elapsed(), "text": "x"})
	var bm: Dictionary = AD._player_event(astute, {"id": "chantaje", "progress": 1.0, "target": "", "held": 0})
	check(not bm.is_empty() and bm.title == "Sé lo que hiciste", "chantaje con secreto")
	if not bm.is_empty():
		AD.ambitions[astute.person_name] = {"id": "chantaje", "kind": "riqueza", "progress": 1.0, "rate": 0.1, "target": "", "held": 0}
		GM.pending_event = bm
		var gold1: int = player.gold
		GM.resolve_pending_event(_event_with_act(bm, "pay"), astute)
		check(player.gold == gold1 - AD.BLACKMAIL_GOLD and not AD.has_secret(), "pagar el chantaje cuesta justo lo anunciado (%d) y entierra el secreto" % (gold1 - player.gold))
	# Inversión con fruto diferido.
	AD.ambitions[friend.person_name] = {"id": "enriquecerse", "kind": "riqueza", "progress": 1.0, "rate": 0.1, "target": "", "held": 0, "involve": true}
	var inv: Dictionary = AD._player_event(friend, AD.ambitions[friend.person_name])
	GM.pending_event = inv
	GM.resolve_pending_event(_event_with_act(inv, "invest"), friend)
	check(AD.investments.size() == 1, "invertir deja un negocio pendiente")
	AD.investments[0].due = GM.months_elapsed()
	var gold2: int = player.gold
	AD._pay_investments(GM.months_elapsed())
	check(AD.investments.is_empty() and (player.gold == gold2 + roundi(AD.INVEST_GOLD * AD.INVEST_RETURN) or player.gold == gold2), "el negocio se resuelve (gana o se pierde)")

	print("[desenlaces entre PNJ]")
	AD.news_count = 0
	var chron0: int = WE.chronicle.size()
	var npc_cases := ["casarse", "fe", "torneo", "rivalidad", "ascender"]
	var npc_people := {"casarse": _rel("Don Soltero", Relationship.Kind.CORTESANO, CH.Personality.LEAL, k),
		"fe": pious, "torneo": schemer if schemer != null else pious, "rivalidad": _rel("Ser Rencoroso", Relationship.Kind.CORTESANO, CH.Personality.ARROGANTE, k),
		"ascender": _rel("Escudero Ambicioso", Relationship.Kind.CORTESANO, CH.Personality.AMBICIOSO, k)}
	npc_people["ascender"].character.role = CH.Role.SOLDADO
	for id in npc_cases:
		var r: Relationship = npc_people[id]
		AD._npc_outcome(r, {"id": id, "target": ""})
	check(WE.chronicle.size() >= chron0 + 4, "los desenlaces llegan a la crónica (+%d)" % (WE.chronicle.size() - chron0))
	check(AD.married_npcs.has("Don Soltero"), "un cortesano se casa")
	check(npc_people["ascender"].character.role == CH.Role.CABALLERO, "el escudero asciende a Caballero")
	for e in WE.chronicle.slice(chron0):
		print("    crónica: ", e.text)
	AD.news_count = AD.NPC_NEWS_PER_YEAR
	var chron1: int = WE.chronicle.size()
	AD._npc_outcome(_rel("Don Otro", Relationship.Kind.CORTESANO, CH.Personality.LEAL, k), {"id": "casarse", "target": ""})
	check(WE.chronicle.size() == chron1, "con el cupo del año lleno, no hay más noticias")

	print("[guardado]")
	AD.ambitions["Ser Cruel"] = {"id": "vengarse", "kind": "venganza", "progress": 0.5, "rate": 0.2, "target": "", "held": 1}
	AD.investments.append({"due": 99, "amount": 60, "partner": "Doña Amiga"})
	var st: Dictionary = AD.save_state()
	AD.reset()
	AD.load_state(st)
	check(AD.ambitions.has("Ser Cruel") and AD.investments.size() == 1 and AD.married_npcs.has("Don Soltero"), "save_state/load_state conserva ambiciones, negocios y bodas")
	check(SS.save_game() == OK and SS.load_game(), "guardado completo con AmbitionData")
	check(root.get_node("AmbitionData").ambitions.has("Ser Cruel"), "tras cargar la partida sigue la ambición")
	AD.load_state({})
	check(AD.ambitions.is_empty() and AD.last_plot_month == -100, "partida antigua: sin ambiciones, sin errores")

	print("[ritmo: 20 años]")
	seed(5)
	var p2 = CL.make_test_character("Sir Viajero", CH.Role.CABALLERO)
	p2.gold = 3000
	GM.start_new_game(p2, MD.castles[1].castle_id)
	await process_frame
	var per_month := {}
	var plots_total := 0
	var max_in_month := 0
	var npc_by_year := {}
	var kinds := {}
	for m in 240:
		var before: int = AD.stats.plots
		GM.current_month = GM.current_month   # sin cambios
		GM.advance_turn()
		var new_plots: int = AD.stats.plots - before
		max_in_month = maxi(max_in_month, new_plots)
		plots_total += new_plots
		npc_by_year[GM.current_year] = AD.news_count
		if GM.has_pending_event() and str(GM.pending_event.get("amb_owner", "")) != "":
			var id: String = str(GM.pending_event.id)
			kinds[id] = kinds.get(id, 0) + 1
		_resolve_pending()
		GM.player_character.gold = maxi(GM.player_character.gold, 500)
		GM.player_character.honor = maxi(GM.player_character.honor, 30)
		GM.player_character.current_health = GM.player_character.max_health
		if not GM.is_game_active:
			print("    la partida terminó en el mes ", m)
			break
	var per := plots_total / 240.0
	print("    complots contigo: %d en 20 años (1 cada %.1f meses) · tipos: %s" % [plots_total, 240.0 / maxf(plots_total, 1), str(kinds)])
	print("    noticias entre PNJ: %d · descartadas por cupo o sin efecto: %d" % [AD.stats.npc_news, AD.stats.fizzled])
	check(max_in_month <= 1, "nunca más de un complot al mes (máx. %d)" % max_in_month)
	check(per >= 1.0 / 5.0 and per <= 1.0 / 2.5, "ritmo de complots entre 1 cada 2,5 y 1 cada 5 meses (1 cada %.1f)" % (240.0 / maxf(plots_total, 1)))
	var yearly: float = AD.stats.npc_news / 20.0
	var max_year: int = npc_by_year.values().max()
	check(yearly >= 2.0 and max_year <= AD.NPC_NEWS_PER_YEAR, "noticias entre PNJ: %.1f al año (máx. %d en un año)" % [yearly, max_year])
	print("FALLAS: ", fails)
	quit(fails)
