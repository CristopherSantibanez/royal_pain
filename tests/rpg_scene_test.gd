extends SceneTree
# Pantalla del combate RPG (scenes/rpg_battle): 4 contra 5, un combate entero por la interfaz y cada
# punto de entrada (duelo de evento, escaramuza, torneo, encuentro de camino, práctica, a muerte, incrustado).
# Uso: --headless --script tests/rpg_scene_test.gd

const SCENE := "res://scenes/rpg_battle/rpg_battle.tscn"
var fails := 0
var RS

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _find_fight(data, pred: Callable) -> Dictionary:
	if data is Dictionary:
		if data.has("fight") and data.fight is Dictionary and pred.call(data.fight):
			return data.fight
		for k in data:
			var r := _find_fight(data[k], pred)
			if not r.is_empty():
				return r
	elif data is Array:
		for v in data:
			var r := _find_fight(v, pred)
			if not r.is_empty():
				return r
	return {}

func _wait_end(scene, limit := 20.0) -> bool:
	var t := 0.0
	while is_instance_valid(scene) and not scene._ended and t < limit:
		await create_timer(0.1).timeout
		t += 0.1
	return is_instance_valid(scene) and scene._ended

func _open(path: String):
	check(path == SCENE, "lleva a la pantalla RPG (%s)" % path.get_file())
	change_scene_to_file(path)
	await create_timer(0.3).timeout
	return current_scene

func _run() -> void:
	RS = load("res://scenes/rpg_battle/rpg_battle.gd")
	RS.test_delay = 0.0
	var GM = root.get_node("GameManager")
	var CS = root.get_node("CombatSetup")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var EC = load("res://scripts/resources/event_catalog.gd")
	var player = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	GM.start_new_game(player, MD.castles[0].castle_id)
	MD.get_castle_by_id(GM.home_castle_id).garrison_size = 100

	print("[4 contra 5 y combate por la interfaz]")
	CS.clear()
	var mine: Array = [player]
	for i in 3:
		mine.append(CL.make_test_character("Compañero %d" % i, CH.Role.SOLDADO))
	var foes: Array = Array(EnemyCatalog.make_party("escaramuza", 6, 2)).slice(0, 5)
	var sc = load(SCENE).instantiate()
	sc.side_a = mine
	sc.side_b = foes
	root.add_child(sc)
	await create_timer(0.3).timeout
	var shown_e: int = sc.enemy_row.get_children().filter(func(c): return c.visible).size()
	var shown_p: int = sc.party_row.get_children().filter(func(c): return c.visible).size()
	check(shown_e == 5 and shown_p == 4, "5 retratos enemigos y 4 del grupo (%d, %d)" % [shown_e, shown_p])
	check(sc.timeline_box.get_child_count() == 8, "línea de turnos con 8 caras")
	var guard := 0
	while sc._acting == null and not sc._ended and guard < 100:
		await create_timer(0.05).timeout
		guard += 1
	check(sc._acting != null and sc._menu == "main" and sc.cmd_box.get_child(0).get_child_count() == 6, "menú de 6 órdenes para quien actúa")
	var log_before: String = sc._log_text
	sc.cmd_box.get_child(0).get_child(0).pressed.emit()   # Atacar
	check(sc._menu == "target" and not sc._targeting.is_empty(), "Atacar pide objetivo")
	sc._cycle_target(1)
	sc._confirm_target()
	check(sc._log_text.length() > log_before.length(), "el ataque elegido se ejecuta")
	RS.test_auto = true   # desde aquí la IA juega también por el grupo
	check(await _wait_end(sc, 60.0), "el combate termina (%d rondas, gana el bando %d)" % [sc.mgr.round_num, sc.mgr.result.get("winner", -9)])
	check(not sc.btn_back.disabled, "botón de volver activo al terminar")
	sc.queue_free()

	print("[duelo de evento → combate de grupo]")
	var insult: Dictionary = {}
	for e in EC.EVENTS:
		if e.id == "insulto":
			insult = e
	var fight: Dictionary = insult.options.filter(func(o): return o.has("fight"))[0].fight
	var honor0: int = player.honor
	sc = await _open(CS.begin_event_fight(fight, insult.title))
	check(sc.group and sc.mgr.side_fighters(1).size() >= 2 and sc.mgr.side_fighters(1)[0].c == CS.enemy_character, "rival con nombre de jefe + escolta")
	check(await _wait_end(sc), "termina")
	check(not CS.last_result_text.is_empty() and CS.pending_outcome.is_empty(), "desenlace aplicado: %s" % CS.last_result_text.left(90))
	print("  honor %d -> %d" % [honor0, player.honor])

	print("[escaramuza]")
	var bandits: Dictionary = {}
	for e in EC.EVENTS:
		if e.id == "bandidos":
			bandits = e
	var bf: Dictionary = bandits.options.filter(func(o): return o.has("fight") and o.fight.type == "battle")[0].fight
	var path: String = CS.begin_event_fight(bf, bandits.title)
	check(path.ends_with("battle.tscn"), "la escaramuza con soldados sigue en el tablero (campal)")
	CS.skirmish = {}
	CS.pending_outcome = {}

	print("[torneo]")
	var opps: Array[Character] = []
	for i in 3:
		opps.append(CL.make_test_character("Justador %d" % i, CH.Role.CABALLERO))
	CS.start_tournament(player, opps)
	CS.return_scene = "res://scenes/map/map.tscn"
	sc = await _open(CS.RPG_SCENE)
	check(sc.mgr.side_fighters(0).size() == 1 and sc.mgr.side_fighters(1).size() == 1, "ronda de torneo 1 contra 1")
	check(await _wait_end(sc), "ronda terminada (%s)" % ("siguiente ronda" if sc._pending_next_round else sc.hint_label.text.left(60)))
	if sc._pending_next_round:
		sc._on_back_pressed()
		await create_timer(0.3).timeout
		check(current_scene.title_label.text.contains("ronda 2"), "siguiente ronda en la misma pantalla")
		await _wait_end(current_scene)
	CS.clear()

	print("[encuentro de camino]")
	var RE = load("res://scripts/resources/road_encounter_catalog.gd")
	var road := _find_fight(RE.ENCOUNTERS, func(f): return f.get("type", "") == "duel")
	sc = await _open(CS.begin_event_fight(CS.tag_fight(road, "camino"), "Camino"))
	check(CS.fight_context == "camino" and sc.mgr.side_fighters(1).size() >= 2, "contexto camino con escolta")
	check(await _wait_end(sc), "termina")
	CS.clear()

	print("[práctica sin heridas]")
	var rel = null
	for r in RD.relations:
		if r.character != null:
			rel = r
			break
	var wounds0: int = player.wound_months
	var hp0: int = player.current_health
	var honor1: int = player.honor
	RD.practice_partner = rel.person_name
	CS.start_campaign_duel(player, rel.character)
	CS.return_scene = "res://scenes/relations/relations.tscn"
	sc = await _open(CS.RPG_SCENE)
	check(sc._practice and sc.mgr.side_fighters(0).size() == 1, "práctica 1 contra 1")
	check(await _wait_end(sc), "termina")
	check(player.wound_months == wounds0 and player.current_health == hp0 and player.honor == honor1, "sin heridas ni honor en juego")
	CS.clear()

	print("[incrustado (duelo de jefes)]")
	var bconst: Dictionary = load("res://scenes/battle/battle.gd").get_script_constant_map()
	check(str(bconst.get("COMBAT_SCENE", "")) == SCENE, "la batalla campal usa la pantalla RPG para los duelos de jefes")
	var a = CL.make_test_character("Jefe A", CH.Role.CABALLERO)
	var b = CL.make_test_character("Jefe B", CH.Role.CABALLERO)
	sc = load(SCENE).instantiate()
	sc.player_character = a
	sc.enemy_character = b
	sc.embedded = true
	var got := [false]
	sc.embedded_finished.connect(func(_w): got[0] = true)
	root.add_child(sc)
	check(await _wait_end(sc), "duelo incrustado termina")
	sc._on_back_pressed()
	check(got[0] and sc.btn_back.text == "Volver a la batalla", "emite embedded_finished")
	sc.queue_free()

	print("[a muerte: muere el jugador]")
	var DD = root.get_node("DynastyData")
	var site := _find_fight(load("res://scripts/resources/site_catalog.gd").SITES, func(f): return f.get("to_death", false))
	path = CS.begin_event_fight(CS.tag_fight(site, "exploracion"), "Sitio")
	check(CS.duel_to_death and CS.fight_context == "exploracion", "lucha a muerte en exploración")
	for e in CS.enemy_party:
		e.combat = 20
		e.level = 15
	player.current_health = 1
	sc = await _open(path)
	check(await _wait_end(sc), "termina")
	check(player in sc.mgr.result.get("dead", []) and DD.needs_succession() and sc.btn_back.text == "Volver al Mapa", "el jugador muere y se abre la sucesión")
	RS.test_auto = false
	print("FALLAS: %d" % fails if fails else "TODO OK")
	quit()
