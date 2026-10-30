extends SceneTree
# Fase 4B: IA del tablero más lista (flanquea, escolta al general, reserva, se repliega, dificultad),
# orientación y flancos, formaciones (Línea, Cuña, Cuadro), conmutador «Oficial» y escaramuza de evento con choques.

var fails := 0
var CL
var CH
const A := BattleEnums.Side.ATACANTE
const D := BattleEnums.Side.DEFENSOR

func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok  ", what)
	else:
		fails += 1
		print("  FALLA ", what)

func _initialize() -> void:
	_run.call_deferred()

func _cmd() -> Character:
	var c: Character = CL.make_test_character("Cmd", CH.Role.NOBLEZA_ALTA)
	c.leadership = 8
	c.strategy = 8
	return c

func _bm(att: int = 120, defn: int = 120) -> BattleManager:
	var b := BattleManager.new()
	b.player_side = A
	b.start_battle(att, defn, false, _cmd(), _cmd(), "X")
	b.weather = BattleEnums.Weather.DESPEJADO
	b.time_of_day = BattleEnums.TimeOfDay.DIA
	for x in BattleManager.GRID_W:
		for y in BattleManager.GRID_H:
			b.terrain[x][y] = BattleEnums.Terrain.LLANO
	b.use_encounters = false
	b.ai_difficulty = 2
	return b

func _keep(b: BattleManager, keep: Array) -> void:
	for u: BattleUnit in b.units:
		if not u in keep:
			u.routed = true
	b._roles_done[A] = true
	b._roles_done[D] = true

func _ready_unit(u: BattleUnit, type: int, cell: Vector2i, facing: Vector2i, soldiers: int = 20) -> void:
	u.type = type
	u.cell = cell
	u.facing = facing
	u.soldiers = soldiers
	u.max_soldiers = soldiers
	u.morale = 70
	u.fatigue = 0
	u.routed = false
	u.order = BattleEnums.Order.NINGUNA
	u.formation = BattleEnums.Formation.LINEA
	u.reset_turn()

func _non_general(b: BattleManager, side: int) -> Array:
	return b.units.filter(func(u): return u.side == side and not u.general)

func _run() -> void:
	seed(5)
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")

	print("[orientación y flancos]")
	var b := _bm()
	var att: BattleUnit = _non_general(b, A)[0]
	var tgt: BattleUnit = _non_general(b, D)[0]
	_ready_unit(att, BattleEnums.UnitType.INFANTERIA, Vector2i(4, 4), Vector2i(1, 0), 200)
	_ready_unit(tgt, BattleEnums.UnitType.INFANTERIA, Vector2i(5, 4), Vector2i(-1, 0), 500)
	var cas := {}
	for spec in [["frente", Vector2i(4, 4)], ["flanco", Vector2i(5, 3)], ["espalda", Vector2i(6, 4)]]:
		att.cell = spec[1]
		cas[spec[0]] = b._compute_casualties(att, tgt, 1, false)
	att.cell = Vector2i(4, 4)
	check(b.flank_of(att, tgt) == 0 and b.flank_of(att, tgt, Vector2i(5, 3)) == 1 and b.flank_of(att, tgt, Vector2i(6, 4)) == 2, "frente / flanco / espalda según hacia dónde mira")
	check(cas.espalda > cas.flanco and cas.flanco > cas.frente, "más bajas por el flanco y la espalda (%s)" % str(cas))
	check(absf(float(cas.espalda) / cas.frente - BattleManager.REAR_DAMAGE) < 0.1 and absf(float(cas.flanco) / cas.frente - BattleManager.FLANK_DAMAGE) < 0.1, "bonos ×%.2f y ×%.2f" % [BattleManager.FLANK_DAMAGE, BattleManager.REAR_DAMAGE])
	var mover: BattleUnit = _non_general(b, A)[1]
	_ready_unit(mover, BattleEnums.UnitType.INFANTERIA, Vector2i(2, 1), Vector2i(1, 0))
	b.move_unit(mover, Vector2i(2, 3))
	check(mover.facing == Vector2i(0, 1), "al moverse mira hacia donde fue (%s)" % mover.facing)
	var logs: Array = []
	b.log_message.connect(func(t): logs.append(t))
	att.cell = Vector2i(6, 4)
	att.reset_turn()
	var m0 := tgt.morale
	b.attack(att, tgt)
	check(att.facing == Vector2i(-1, 0), "al atacar mira al objetivo")
	check(logs.any(func(t): return "espalda" in t) and tgt.morale <= m0 - BattleManager.REAR_MORALE, "por la espalda: aviso y −%d de moral (%d → %d)" % [BattleManager.REAR_MORALE, m0, tgt.morale])
	check(tgt.facing == Vector2i(-1, 0), "el golpeado no se gira solo")

	print("[formaciones]")
	tgt.soldiers = 500
	tgt.morale = 70
	att.cell = Vector2i(4, 4)
	var front := b._compute_casualties(att, tgt, 1, false)
	att.formation = BattleEnums.Formation.CUNA
	check(absf(float(b._compute_casualties(att, tgt, 1, false)) / front - BattleManager.CUNA_POWER) < 0.08, "Cuña: golpea un %d%% más" % roundi((BattleManager.CUNA_POWER - 1) * 100))
	att.formation = BattleEnums.Formation.LINEA
	att.cell = Vector2i(5, 3)
	var flank_line := b._compute_casualties(att, tgt, 1, false)
	tgt.formation = BattleEnums.Formation.CUNA
	check(b._compute_casualties(att, tgt, 1, false) > flank_line, "Cuña: sus flancos aguantan peor")
	tgt.formation = BattleEnums.Formation.CUADRO
	check(b.flank_of(att, tgt) == 0 and b.flank_of(att, tgt, Vector2i(6, 4)) == 1, "Cuadro: apenas tiene flancos")
	att.cell = Vector2i(4, 4)
	att.type = BattleEnums.UnitType.CABALLERIA
	tgt.formation = BattleEnums.Formation.LINEA
	var cav_line := b._compute_casualties(att, tgt, 1, false)
	tgt.formation = BattleEnums.Formation.CUADRO
	var cav_sq := b._compute_casualties(att, tgt, 1, false)
	check(cav_sq < cav_line * 0.8, "Cuadro: aguanta la caballería (%d → %d)" % [cav_line, cav_sq])
	var mv := b.effective_move_range(tgt)
	tgt.formation = BattleEnums.Formation.LINEA
	check(mv == b.effective_move_range(tgt) - BattleManager.CUADRO_MOVE, "Cuadro: se mueve una casilla menos")
	att.type = BattleEnums.UnitType.INFANTERIA
	att.reset_turn()
	check(b.cycle_formation(att) and att.formation == BattleEnums.Formation.CUNA and b.cycle_formation(att) and att.formation == BattleEnums.Formation.CUADRO and b.cycle_formation(att) and att.formation == BattleEnums.Formation.LINEA, "la orden de formación rota Línea → Cuña → Cuadro")
	att.has_acted = true
	check(not b.set_formation(att, BattleEnums.Formation.CUNA), "no se cambia tras actuar")

	print("[flancos y formación en el choque RPG]")
	att.reset_turn()
	att.cell = Vector2i(6, 4)
	att.soldiers = 20
	tgt.soldiers = 20
	var enc := CampalEncounters.make(b, att, tgt, 1)
	check(int(enc.flank) == 2, "el choque sabe que es por la espalda")
	var lead: Character = enc.b[0]
	var mgr := RpgBattleManager.new()
	mgr.setup(enc.a, enc.b, {})
	var f1 = mgr.fighters.filter(func(f): return f.c == lead)[0]
	CampalEncounters.set_troops(enc.b, tgt, att, 0)
	var mgr2 := RpgBattleManager.new()
	mgr2.setup(enc.a, enc.b, {})
	var f2 = mgr2.fighters.filter(func(f): return f.c == lead)[0]
	check(f1.morale < f2.morale and float(f1.s.defensa) < float(f2.s.defensa), "cogidos por la espalda: menos moral (%d < %d) y defensa" % [f1.morale, f2.morale])
	var alead: Character = enc.a[0]
	var fa1 = mgr2.fighters.filter(func(f): return f.c == alead)[0]
	att.formation = BattleEnums.Formation.CUNA
	CampalEncounters.set_troops(enc.a, att, tgt)
	var mgr3 := RpgBattleManager.new()
	mgr3.setup(enc.a, enc.b, {})
	var fa2 = mgr3.fighters.filter(func(f): return f.c == alead)[0]
	check(float(fa2.s.fuerza) > float(fa1.s.fuerza), "en Cuña, los atacantes tienen más Fuerza")
	CampalEncounters.clear_troops(enc.a + enc.b)

	print("[IA: flanquea]")
	b = _bm()
	var g: BattleUnit = b._general_unit(D)
	var cav: BattleUnit = _non_general(b, D)[0]
	var prey: BattleUnit = b._general_unit(A)
	_keep(b, [g, cav, prey])
	_ready_unit(prey, BattleEnums.UnitType.INFANTERIA, Vector2i(5, 4), Vector2i(1, 0))
	_ready_unit(cav, BattleEnums.UnitType.CABALLERIA, Vector2i(7, 3), Vector2i(-1, 0))
	_ready_unit(g, BattleEnums.UnitType.INFANTERIA, Vector2i(11, 0), Vector2i(-1, 0))
	b._run_ai(D)
	check(b.flank_of(cav, prey) >= 1 and prey.soldiers < 20, "la caballería rodea y golpea por el flanco o la espalda (%s, nivel %d)" % [cav.cell, b.flank_of(cav, prey)])
	check(cav.formation == BattleEnums.Formation.CUNA, "la caballería de la IA forma en Cuña")

	print("[IA: escolta del general y reserva]")
	b = _bm()
	b._ai_assign_roles(D)
	var escorts := b.units.filter(func(u): return u.side == D and u.escort)
	var reserves := b.units.filter(func(u): return u.side == D and u.reserve)
	check(escorts.size() == 1 and reserves.size() == 1, "un pelotón escolta al general y otro queda en reserva (%d, %d)" % [escorts.size(), reserves.size()])
	b._run_ai(D)
	var res: BattleUnit = reserves[0]
	var others := b.units.filter(func(u): return u.side == D and u.is_active() and not u.general and not u.reserve and not u.escort and not BattleEnums.is_ranged(u.type))
	var avg_x := 0.0
	for u in others:
		avg_x += u.cell.x
	avg_x /= maxi(1, others.size())
	check(res.reserve and res.cell.x > avg_x, "la reserva se queda atrás el primer turno (x %d, línea %.1f)" % [res.cell.x, avg_x])
	b.turn = BattleManager.AI_RESERVE_TURN
	for u in b.units:
		u.reset_turn()
	b._run_ai(D)
	check(not res.reserve, "la reserva entra en combate cuando hace falta")
	b = _bm()
	g = b._general_unit(D)
	var esc: BattleUnit = _non_general(b, D)[0]
	var raider: BattleUnit = b._general_unit(A)
	_keep(b, [g, esc, raider])
	esc.escort = true
	_ready_unit(g, BattleEnums.UnitType.INFANTERIA, Vector2i(10, 4), Vector2i(-1, 0))
	_ready_unit(esc, BattleEnums.UnitType.CABALLERIA, Vector2i(10, 6), Vector2i(-1, 0))
	_ready_unit(raider, BattleEnums.UnitType.INFANTERIA, Vector2i(8, 4), Vector2i(1, 0))
	b._run_ai(D)
	check(esc.has_acted and b.distance(esc.cell, raider.cell) <= 1, "la escolta sale al paso de quien amenaza al general")
	check(b.distance(g.cell, raider.cell) >= 2 or raider.soldiers < 20, "el general no se expone")

	print("[IA: se repliega para reagruparse; dificultad]")
	b = _bm()
	g = b._general_unit(D)
	var weak: BattleUnit = _non_general(b, D)[0]
	var foe: BattleUnit = b._general_unit(A)
	_keep(b, [g, weak, foe])
	var withdrew := {}
	for diff in [0, 2]:
		b.ai_difficulty = diff
		var n := 0
		for i in 60:
			_ready_unit(g, BattleEnums.UnitType.INFANTERIA, Vector2i(11, 0), Vector2i(-1, 0))
			_ready_unit(weak, BattleEnums.UnitType.INFANTERIA, Vector2i(6, 4), Vector2i(-1, 0))
			_ready_unit(foe, BattleEnums.UnitType.INFANTERIA, Vector2i(5, 4), Vector2i(1, 0))
			weak.morale = 35
			b.is_over = false
			b._run_ai(D)
			if foe.soldiers == 20 and b.distance(weak.cell, foe.cell) > 1:
				n += 1
		withdrew[diff] = n
	check(withdrew[2] == 60, "en Difícil, con moral baja se repliega siempre (%d/60)" % withdrew[2])
	check(withdrew[0] < 52 and withdrew[0] > 15, "en Fácil, a menudo sigue luchando (%d/60)" % withdrew[0])
	var smart := {}
	for diff in [0, 1, 2]:
		b.ai_difficulty = diff
		var k := 0
		for i in 2000:
			if b._ai_smart(weak):
				k += 1
		smart[diff] = k / 2000.0
	check(smart[0] < smart[1] and smart[1] < smart[2] and smart[2] == 1.0, "la dificultad sube lo a menudo que la IA elige lo mejor (%s)" % str(smart))
	b.ally_competence_override = 0.0
	foe.ally = true
	check(not b._ai_smart(foe), "la IA aliada sigue dependiendo de la competencia de su jefe")

	print("[grupo: conmutador «Oficial»]")
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var PD = root.get_node("PartyData")
	var CS = root.get_node("CombatSetup")
	var player = CL.make_test_character("Sir Test", CH.Role.CABALLERO)
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame
	GM.pending_event = {}
	var people: Array = RD.relations.filter(func(r): return r.character != null and r.character.role != CH.Role.CAMPESINO and not RD.is_spouse(r.person_name)).slice(0, 2)
	for r in people:
		RD.retinue.append(r.person_name)
	var mate: Character = people[0].character
	var panel = load("res://scripts/ui/party_panel.gd").open(root)
	await process_frame
	var btn: Button = null
	for row in panel._body.get_children():
		if row is HBoxContainer and row.get_meta("who", "") == mate.full_name():
			for x in row.get_children():
				if x is Button and x.text == "Oficial":
					btn = x
	check(btn != null and btn.toggle_mode and not btn.button_pressed, "cada miembro tiene su botón «Oficial»")
	if btn != null:
		btn.pressed.emit()
		await process_frame
		check(PD.is_officer(mate), "pulsarlo lo hace oficial")
	panel._close()
	await process_frame

	print("[escaramuza de evento con choques RPG]")
	load("res://scenes/battle/battle.gd").test_auto_encounters = true
	var home = MD.get_castle_by_id(GM.home_castle_id)
	home.garrison_size = 100
	var fight: Dictionary = {}
	var title := ""
	for e in load("res://scripts/resources/event_catalog.gd").EVENTS:
		for o in e.get("options", []):
			if fight.is_empty() and o.has("fight") and o.fight.get("type", "") == "battle":
				fight = o.fight
				title = e.title
	var path: String = CS.begin_event_fight(fight, title)
	check(path.ends_with("battle.tscn"), "la escaramuza lleva al tablero")
	change_scene_to_file(path)
	await create_timer(0.6).timeout
	var scene = current_scene
	var bb: BattleManager = scene.battle
	check(bb.use_encounters and not bb.has_walls, "escaramuza en campo abierto con choques RPG")
	var mine: BattleUnit = bb.player_unit()
	scene.selected = mine
	scene._give_order(scene.FORMATION_ORDER)
	check(mine.formation == BattleEnums.Formation.CUNA and scene._order_buttons[scene.FORMATION_ORDER].text.begins_with("Cuña"), "botón de formación: Cuña")
	var ev := InputEventKey.new()
	ev.keycode = KEY_F
	ev.pressed = true
	scene._unhandled_input(ev)
	check(mine.formation == BattleEnums.Formation.CUADRO, "tecla F: Cuadro")
	scene._unhandled_input(ev)
	var chocs := [0]
	bb.log_message.connect(func(t): if "Choque" in t: chocs[0] += 1)
	var enemy: BattleUnit = bb.active_units(bb._other_side(bb.player_side))[0]
	enemy.cell = mine.cell + Vector2i(1, 0)
	if not bb.in_bounds(enemy.cell) or bb.unit_at(enemy.cell) != enemy:
		enemy.cell = mine.cell + Vector2i(0, 1)
	mine.reset_turn()
	bb.attack(mine, enemy)
	for i in 60:
		await process_frame
		if bb.pending_encounters.is_empty() and not scene._encounters_running:
			break
	check(chocs[0] >= 1, "el choque se juega como combate RPG y se resuelve")
	var guard := 0
	while not bb.is_over and guard < 4:
		guard += 1
		scene._on_end_turn_pressed()
		for i in 120:
			await process_frame
			if not scene._encounters_running and bb.pending_encounters.is_empty() and not scene._dueling:
				break
		await create_timer(0.3).timeout
	if not bb.is_over:
		for u in bb.units:
			if u.side != bb.player_side and u.is_active():
				u.soldiers = 1
				u.morale = 1
				u.routed = true
		bb._check_end()
	await create_timer(0.8).timeout
	check(bb.is_over and CS.skirmish.is_empty(), "la escaramuza termina y cierra su desenlace (%d choques)" % chocs[0])
	check(not scene.result_title.text.is_empty(), "cartel final: %s" % scene.result_title.text)

	print("\nFALLOS: %d" % fails)
	quit(1 if fails > 0 else 0)
