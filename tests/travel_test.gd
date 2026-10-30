extends SceneTree
# Viaje: ficha por rutas, coste por tramo (invierno), zona por ubicación, encuentros, audiencia,
# jurar lealtad, gobierno a distancia, guardado.

var fails := 0

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(11)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var TD = root.get_node("TravelData")
	var RD = root.get_node("RelationsData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var SS = load("res://scripts/resources/save_system.gd")
	var REC = load("res://scripts/resources/road_encounter_catalog.gd")
	var player = CL.make_test_character("Sir Viajero", CH.Role.CABALLERO)
	player.gold = 2000
	# Un castillo de origen con señor y vecinos de otro reino.
	var home = null
	for c in MD.castles:
		if c.owner_name != RD.NO_LORD:
			for n in c.connected_castle_ids:
				var nc = MD.get_castle_by_id(n)
				if nc.kingdom != c.kingdom and nc.kingdom != KingdomEnums.Kingdom.NEUTRAL:
					home = c
					break
		if home != null:
			break
	GM.start_new_game(player, home.castle_id)
	await process_frame

	print("[ubicación inicial]")
	check(TD.current_castle_id() == home.castle_id, "empieza en su castillo")
	check(TD.is_at_home(), "is_at_home")
	check(TD.zone_kingdom() == home.kingdom, "zona = reino de origen")

	print("[camino y coste]")
	var foreign = null
	for n in home.connected_castle_ids:
		var nc = MD.get_castle_by_id(n)
		if nc.kingdom != home.kingdom and nc.kingdom != KingdomEnums.Kingdom.NEUTRAL:
			foreign = nc
	var far = null
	for c in MD.castles:
		if TD.path_to(c.castle_id).size() >= 3:
			far = c
			break
	check(TD.path_to(foreign.castle_id) == [foreign.castle_id], "vecino: un tramo")
	check(far != null and TD.path_to(far.castle_id).size() >= 3, "camino de varios tramos (%d)" % (TD.path_to(far.castle_id).size() if far else -1))
	GM.current_month = 6
	check(TD.hop_cost() == 1, "verano: 1 acción por tramo")
	GM.current_month = 1
	check(TD.hop_cost() == 2, "invierno: 2 acciones por tramo")
	GM.current_month = 6

	print("[viajar]")
	GM.actions_remaining = 5
	var r: Dictionary = TD.travel_toward(foreign.castle_id)
	check(r.ok and TD.is_at(foreign.castle_id), "llega al vecino")
	check(GM.actions_remaining == 4, "gastó 1 acción (quedan %d)" % GM.actions_remaining)
	check(TD.zone_kingdom() == foreign.kingdom, "la zona cambia al reino visitado")
	var area: Array = RD.people_in_area()
	check(not area.is_empty() and area.all(func(x): return x.kingdom < 0 or x.kingdom == foreign.kingdom), "Tu zona: gente del lugar (%d)" % area.size())
	if TD.has_pending_encounter():
		TD.pending_encounter = {}
	GM.actions_remaining = 0
	check(not TD.travel_blocker(home.castle_id).is_empty(), "sin acciones no se viaja")
	GM.actions_remaining = 5
	TD.pending_encounter = {"id": "mercader", "from": home.castle_id, "to": foreign.castle_id}
	check(not TD.travel_blocker(home.castle_id).is_empty(), "con un encuentro pendiente no se sigue")
	var ev: Dictionary = TD.encounter_event()
	check(ev.title == "Un mercader ambulante" and not "{place}" in ev.options[1].label, "encuentro con textos completados: %s" % ev.options[1].label)
	var gold0: int = player.gold
	var res: Dictionary = TD.resolve_encounter(1)
	check(res.ok and player.gold == gold0 + 25 and not TD.has_pending_encounter(), "resolver el encuentro aplica efectos")

	print("[encuentros]")
	var counts := {}
	for i in 400:
		var id: String = REC.pick({"winter": false, "war": false})
		counts[id] = counts.get(id, 0) + 1
	check(not counts.has("patrulla") and not counts.has("lobos"), "sin guerra ni invierno no hay patrullas ni lobos")
	var wc := {}
	for i in 400:
		var id: String = REC.pick({"winter": true, "war": true})
		wc[id] = wc.get(id, 0) + 1
	check(wc.has("patrulla") and wc.has("lobos"), "en guerra e invierno sí")
	for id in REC.ENCOUNTERS:
		var e: Dictionary = REC.as_event(id, {"place": "X", "kingdom": "Y"})
		check(not e.text.contains("{") and e.options.size() >= 2, "encuentro %s bien formado" % id)
	var ch_base: float = TD.encounter_chance(home.castle_id, foreign.castle_id)
	GM.current_month = 1
	var ch_winter: float = TD.encounter_chance(home.castle_id, foreign.castle_id)
	GM.current_month = 6
	check(ch_winter > ch_base and ch_winter <= TD.ENCOUNTER_MAX, "invierno sube el riesgo (%.2f → %.2f)" % [ch_base, ch_winter])
	# Frecuencia real en 300 tramos de ida y vuelta (verano).
	var n_enc := 0
	for i in 300:
		GM.actions_remaining = 5
		var dest = home if TD.is_at(foreign.castle_id) else foreign
		var tr: Dictionary = TD.travel_toward(dest.castle_id)
		if not tr.encounter.is_empty():
			n_enc += 1
		TD.pending_encounter = {}
	print("    encuentros en 300 tramos: %d" % n_enc)
	check(n_enc > 20 and n_enc < 150, "frecuencia moderada")

	print("[gobierno a distancia]")
	GM.actions_remaining = 5
	if TD.is_at_home():
		TD.travel_toward(foreign.castle_id)
		TD.pending_encounter = {}
	check(TD.is_remote(home), "tu castillo desde lejos = remoto")
	check(TD.can_enter(home).is_empty(), "puedes entrar a tu castillo desde lejos")
	var other = null
	for c in MD.castles:
		if not TD.is_at(c.castle_id) and c.castle_id != home.castle_id:
			other = c
			break
	check(not TD.can_enter(other).is_empty(), "no entras a un castillo ajeno donde no estás")

	print("[audiencia]")
	var lord = TD.lord_relation(foreign)
	lord.affinity = 0
	player.fame = 0
	check(TD.audience_blocker(foreign).is_empty(), "un caballero es recibido")
	GM.actions_remaining = 3
	var a: Dictionary = TD.request_audience(foreign)
	check(a.ok and GM.actions_remaining == 2, "la audiencia gasta 1 acción")
	check(not TD.audience_blocker(foreign).is_empty(), "una audiencia al mes por señor")
	var aff0: int = lord.affinity
	TD.audience_respects(foreign)
	check(lord.affinity > aff0, "presentar respetos sube la afinidad")
	check(TD.audience_news(foreign).contains("soldados"), "las noticias cuentan guarniciones")
	var peasant_block := func():
		player.role = CH.Role.CAMPESINO
		var b: String = TD.audience_blocker(foreign)
		player.role = CH.Role.CABALLERO
		return b
	TD._audience_months.clear()
	check(not str(peasant_block.call()).is_empty(), "un campesino sin fama no es recibido")

	print("[jurar lealtad]")
	lord.affinity = 0
	check(TD.fealty_blocker(foreign).contains("no se fía"), "sin afinidad ni fama: no acepta")
	lord.affinity = 30
	check(TD.fealty_blocker(foreign).is_empty(), "con afinidad: puede jurar")
	var old_liege: String = RD.liege_name
	var old_rel = RD.get_relation(old_liege)
	var old_aff: int = old_rel.affinity if old_rel else 0
	var honor0: int = player.honor
	var cost: int = TD.fealty_honor_cost(foreign)
	var f: Dictionary = TD.swear_fealty(foreign)
	check(f.ok, "jura lealtad: %s" % f.text)
	check(GM.player_kingdom == foreign.kingdom and GM.home_castle_id == foreign.castle_id and RD.liege_name == lord.person_name, "nuevo reino, hogar y señor")
	check(player.honor == maxi(0, honor0 - cost) and cost >= TD.FEALTY_HONOR_COST, "pierde %d de honor" % cost)
	check(old_rel == null or old_rel.affinity <= old_aff + TD.FEALTY_OLD_LIEGE_AFFINITY + 1 or old_rel.affinity == -100, "el antiguo señor te detesta")
	check(TD.is_at_home(), "ahora estás en tu nuevo hogar")
	check(not TD.fealty_blocker(home).is_empty(), "no puedes volver a jurar enseguida")

	print("[torneo local]")
	GM.current_month = 5
	check(TD.local_tournament_blocker(foreign).is_empty(), "torneo local disponible en mayo")
	TD.mark_local_tournament(foreign)
	check(not TD.local_tournament_blocker(foreign).is_empty(), "uno por castillo y año")

	print("[guardado]")
	GM.actions_remaining = 5
	TD.travel_toward(home.castle_id)
	TD.pending_encounter = {"id": "lobos", "from": foreign.castle_id, "to": home.castle_id}
	var st: Dictionary = TD.save_state()
	var loc: String = TD.location_id
	TD.reset()
	TD.load_state(st)
	check(TD.location_id == loc and TD.pending_encounter.id == "lobos", "ubicación y encuentro pendiente se guardan")
	check(int(TD.local_tournament_years.get(foreign.castle_id, 0)) == GM.current_year, "torneos locales se guardan")
	TD.load_state({})
	check(TD.current_castle_id() == GM.home_castle_id, "partida antigua: empiezas en casa")
	check(SS.MODULES.has("TravelData"), "TravelData en SaveSystem.MODULES")

	print("FALLAS: ", fails)
	quit(fails)
