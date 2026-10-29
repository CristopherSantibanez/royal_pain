extends SceneTree
# Fase 2B: SocialEvents (lazos por intimidad, rivalidades por etapa, señores, facción) y la huella
# duradera de las historias (modificadores con tick mensual, títulos, regresos, logros). Ritmo en 20 años.

var fails := 0
var GM; var MD; var RD; var SE; var SD; var CL; var CH; var SEC; var AD

func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok  ", what)
	else:
		fails += 1
		print("  FALLA ", what)

func _initialize() -> void:
	_run.call_deferred()

func _new_game() -> void:
	var p = CL.make_test_character("Sir Prueba", CH.Role.NOBLEZA_BAJA)
	p.gold = 2000
	p.honor = 50
	GM.start_new_game(p, MD.castles[0].castle_id)
	GM.event_queue.clear()
	GM.pending_event = {}
	if RD.liege_name.is_empty():
		RD.liege_name = MD.get_castle_by_id(GM.home_castle_id).owner_name

func _resolve(e: Dictionary, idx: int) -> String:
	GM.event_queue.clear()
	GM.pending_event = e
	var rel = RD.get_relation(str(e.get("target", e.get("speaker", ""))))
	return GM.resolve_pending_event(idx, rel)

func _run() -> void:
	GM = root.get_node("GameManager"); MD = root.get_node("MapData"); RD = root.get_node("RelationsData")
	SE = root.get_node("SocialEvents"); SD = root.get_node("StoryData"); AD = root.get_node("AchievementData")
	CL = load("res://scripts/resources/character_loader.gd"); CH = load("res://scripts/resources/character.gd")
	SEC = load("res://scripts/resources/social_event_catalog.gd")
	seed(77)
	_new_game()
	var p = GM.player_character
	var court: Array = RD.courtiers(GM.player_kingdom).filter(func(r): return r.character != null)
	check(court.size() >= 3, "hay cortesanos del reino")
	var r = court[0]; var r2 = court[1]; var r3 = court[2]

	print("1) catálogo: toda plantilla se rellena sin marcadores sueltos")
	var leftovers := 0
	for list in [SEC.BOND, SEC.RIVALRY, SEC.LORD, SEC.FACTION, [SEC.DUEL_DAY]]:
		for t in list:
			var e = SEC.build(t, r.character, p, {"name": "A", "player": "B", "third": "C", "comrade": "D"})
			if str(e).contains("{") and (str(e).contains("{name") or str(e).contains("{a:") or str(e).contains("{s:")):
				leftovers += 1
	check(leftovers == 0, "sin marcadores sin rellenar")

	print("2) lazos: el nivel de intimidad desbloquea sucesos")
	r.affection = 25
	var low: Array = SE.bond_templates(r).map(func(t): return t.id)
	r.affection = 90
	var high: Array = SE.bond_templates(r).map(func(t): return t.id)
	check(not "soc_momento_intimo" in low and "soc_momento_intimo" in high, "momento íntimo solo con Íntimos")
	check(not "soc_confidencia" in low and "soc_confidencia" in high, "confidencias desde Confidente")
	check(high.size() > low.size(), "más intimidad, más sucesos (%d > %d)" % [high.size(), low.size()])
	check(not "soc_celos" in high, "celos solo con cónyuge o amante")
	var e = SE.bond_event(r, "soc_momento_intimo")
	var before: int = r.affection
	r.affection = 80; before = 80
	_resolve(e, 0)
	check(r.affection > before, "noche en vela: intimidad %d -> %d" % [before, r.affection])
	e = SE.bond_event(r, "soc_confidencia")
	var g0: int = p.gold
	_resolve(e, 1)
	check(p.gold > g0 and r.affection < 90, "vender una confidencia da oro y enfría")
	r.romance = true
	check(SE.bond_kinds(r).has("lover") and not SE.bond_event(r, "soc_celos").is_empty(), "amante: puede haber celos")
	r.romance = false
	r.affection = 50
	e = SE.bond_event(r, "soc_regalo")
	var res := _resolve(e, 0)
	check(not res.is_empty() and str(e.speaker) == r.person_name, "regalo con retrato de quien lo da")

	print("3) rivalidades: más frecuentes con la etapa")
	r2.kind = 1   # RIVAL_DUELO
	var rates := []
	for g in [0, 50, 80]:
		r2.grudge = g
		var hits := 0
		for i in range(3000):
			SE.cooldowns = {}
			if not SE._try_rivalry().is_empty():
				hits += 1
		rates.append(hits)
	check(rates[0] < rates[1] and rates[1] < rates[2], "conocido < rival < némesis: %s" % str(rates))
	r2.grudge = 80
	e = SE.rivalry_event(r2, "soc_humillacion")
	check(not e.is_empty() and e.duel_with == r2.person_name, "humillación pública (con duelo)")
	r2.grudge = 0
	check(SE.rivalry_event(r2, "soc_humillacion").is_empty(), "sin humillación entre simples conocidos")
	r2.grudge = 50
	r.romance = true; r.affection = 60
	e = SE.rivalry_event(r2, "soc_sabotaje")
	check(not e.is_empty() and e.target == r.person_name, "sabotaje del cortejo: afecta a quien amas")
	before = r.affection
	_resolve(e, 0)
	check(r.affection > before, "redoblar el cortejo sube el afecto")
	r.romance = false
	e = SE.rivalry_event(r2, "soc_duelo_concertado")
	_resolve(e, 0)
	check(SE.scheduled_duels.size() == 1, "duelo de honor concertado")
	SE.scheduled_duels[0].due = GM.months_elapsed()
	GM.pending_event = {}
	check(SE._queue_due_duel() and GM.pending_event.get("id", "") == "soc_dia_duelo", "llega el día del duelo")
	r2.grudge = 50
	e = SE.rivalry_event(r2, "soc_reconciliacion")
	_resolve(e, 0)
	check(r2.grudge < 50, "reconciliación baja el rencor")
	r3.kind = 1; r3.grudge = 0
	r2.grudge = 50
	e = SE.rivalry_event(r2, "soc_alianza_rival")
	check(not e.is_empty(), "alianza contra un tercero")
	if not e.is_empty():
		var third = RD.get_relation(str(e._social.names.third))
		var tg: int = third.grudge
		_resolve(e, 0)
		check(third.grudge > tg, "el tercero gana rencor")
	r2.kind = 2; r3.kind = 2   # vuelven a ser cortesanos
	var none := 0
	for i in range(200):
		SE.cooldowns = {}
		if not SE._try_rivalry().is_empty() and RD.duel_rivals().is_empty():
			none += 1
	check(none == 0, "sin rivales no hay sucesos de rivalidad")

	print("4) señores: reaccionan a tus hazañas, con retrato")
	var liege = RD.get_relation(RD.liege_name)
	check(liege != null and liege.character != null, "hay señor con retrato")
	RD.last_victory_month = GM.months_elapsed()
	SE._track_deeds(p)
	check(SE.deeds.size() == 1 and SE.deeds[0].type == "victoria", "victoria anotada")
	e = SE.lord_event("victoria", "soc_elogio")
	var aff: int = liege.affinity
	_resolve(e, 0)
	check(e.speaker == RD.liege_name and liege.affinity > aff, "carta de elogio: afinidad %d -> %d" % [aff, liege.affinity])
	p.honor = 30
	SE._track_deeds(p)
	check(SE.deeds.back().type == "deshonra", "deshonra anotada")
	check(not SE.lord_event("deshonra").is_empty(), "reproche del señor")
	for id in ["soc_orden", "soc_banquete"]:
		check(not SE.lord_event("", id).is_empty(), "suceso de señor: " + id)

	print("5) facción: brindis tras la victoria y vida de camaradas")
	SE.note_battle([r.person_name, r3.person_name], true)
	e = SE.faction_event(true, "soc_brindis")
	check(not e.is_empty(), "brindis tras la victoria")
	var other = RD.get_relation(str(e._social.group[1]))
	var oa: int = other.affection
	_resolve(e, 0)
	check(other.affection > oa, "el brindis une a toda la facción")
	SE.cooldowns = {}
	e = SE.faction_event(false, "soc_rivalidad_interna")
	check(not e.is_empty() and e.text.contains(str(e._social.names.comrade)), "disputa entre camaradas")
	check(not SE.faction_event(false, "soc_camarada_apuros").is_empty(), "camarada en apuros")
	check(not SE.faction_event(true, "soc_honor_grupo").is_empty(), "el señor honra al grupo")

	print("6) historias con huella")
	var home = MD.get_castle_by_id(GM.home_castle_id)
	var parts: Array[String] = []
	SD._apply_lasting({"lasting": "peste", "title": "Guardián en la plaga", "returns": "caido_vuelve", "building": "capilla"}, home, parts)
	check(SD.modifiers.size() == 1 and SD.titles.size() == 1 and SD.returns.size() == 1, "modificador, título y regreso guardados")
	check(int(home.buildings.get("capilla", 0)) >= 1, "el castillo mejora su capilla")
	var garr: int = home.garrison_size
	for i in range(8):
		SD._tick_lasting()
	check(home.garrison_size < garr, "la peste baja guarniciones (%d -> %d)" % [garr, home.garrison_size])
	check(SD.modifiers.is_empty(), "la peste caduca a los 8 meses")
	SD._apply_lasting({"lasting": "herejia"}, home, parts)
	var h0: int = p.honor
	load("res://scripts/resources/event_catalog.gd")._apply_effects({"honor": 10}, p, home)
	check(p.honor - h0 == 5, "herejía: honor ganado a la mitad (+%d)" % (p.honor - h0))
	SD.returns[0].due = 0
	SD.returns[0].npc = "Rodrigo Vela"
	GM.pending_event = {}; GM.event_queue.clear()
	SD._tick_lasting()
	check(str(GM.pending_event.get("text", "")).contains("Rodrigo Vela"), "el caballero caído vuelve")
	check(AD.context().get("story_titles", 0) == 1, "los títulos cuentan para las hazañas")
	var save = SD.save_state()
	SD.load_state({})
	check(SD.modifiers.is_empty(), "partida antigua: sin huella")
	SD.load_state(save)
	check(SD.titles.size() == 1, "la huella se guarda")

	print("7) ritmo en 20 años (jugador pasivo)")
	var months := 0; var decided := 0
	var social_total := 0
	for game in range(2):
		_new_game()
		for m in range(240):
			GM.pending_event = {}
			GM.event_queue.clear()
			GM.advance_turn()
			months += 1
			if not GM.pending_event.is_empty():
				decided += 1
			if not GM.is_game_active:
				break
		for k in SE.counts:
			social_total += int(SE.counts[k])
	var share := 100.0 * decided / months
	print("  meses con decisión: %.0f%%, sucesos sociales: %d en %d meses" % [share, social_total, months])
	check(share <= 60.0, "ritmo ≤ 60%")
	check(social_total > 0, "los sucesos sociales aparecen")
	print("RESULTADO: ", "OK" if fails == 0 else "FALLA (%d)" % fails)
	quit()
