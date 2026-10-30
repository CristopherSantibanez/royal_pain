extends SceneTree
# Familias de tropa, comandancia, general, retirada, negociación, Consejo de guerra, Estrategia y guardado.

var fails := 0
var NONE: Array[Character] = []
var BM
var CL
var CH
var BE

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _char(n: String, role: int, strategy: int = 8) -> Character:
	var c: Character = CL.make_test_character(n, role)
	c.strategy = strategy
	c.mastery_xp = {"seeded": 1}
	return c

func _battle(walls: bool, a: Character, d: Character, size_a: int = 100, size_d: int = 100) -> Object:
	var b = BM.new()
	b.random_conditions = false
	b.start_battle(size_a, size_d, walls, a, d, "Prueba")
	return b

func _run() -> void:
	BM = load("res://scripts/resources/battle_manager.gd")
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	BE = load("res://scripts/resources/battle_enums.gd")
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	seed(11)
	var player := _char("Sir Prueba", CH.Role.NOBLEZA_BAJA)
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame

	print("[círculo de ventajas]")
	var b = _battle(false, player, _char("Rival", CH.Role.CABALLERO))
	var T = BE.UnitType
	check(b._matchup(T.CABALLERIA, T.ARQUEROS, 1) == BM.ADVANTAGE_FACTOR, "caballería > arqueros")
	check(b._matchup(T.ARQUEROS, T.INFANTERIA, 2) == BM.ADVANTAGE_FACTOR, "arqueros > infantería (a distancia)")
	check(b._matchup(T.INFANTERIA, T.PIQUEROS, 1) == BM.ADVANTAGE_FACTOR, "infantería > piqueros")
	check(b._matchup(T.LANCEROS, T.CABALLERIA_PESADA, 1) == BM.ADVANTAGE_FACTOR, "lanceros > caballería pesada (misma familia)")
	check(b._matchup(T.CABALLERIA, T.PIQUEROS, 1) == BM.DISADVANTAGE_FACTOR, "caballería contra piqueros: desventaja")
	check(b._matchup(T.CABALLERIA, T.INFANTERIA, 1) == 1.0 and b._matchup(T.BALLESTEROS, T.PIQUEROS, 2) == 1.0, "familias enfrentadas en el círculo: neutral")
	check(b._matchup(T.ARQUEROS, T.CABALLERIA, 1) == BM.RANGED_MELEE_FACTOR, "arqueros cuerpo a cuerpo rinden poco")
	check(BE.stat(T.BALLESTEROS, "range") < BE.stat(T.ARQUEROS, "range") and BE.stat(T.CABALLERIA_PESADA, "move") < BE.stat(T.CABALLERIA, "move"),
		"ballesteros con menos alcance y caballería pesada más lenta")

	print("[tropa avanzada según maestría]")
	var c := _char("Capitán Real", CH.Role.CABALLERO)
	var u = b.units[0]
	b._set_family(u, BE.Family.CABALLERIA, c)
	check(u.type == T.CABALLERIA, "maestría 1: caballería básica")
	while c.mastery(BE.Family.CABALLERIA) < CH.MASTERY_ADVANCED:
		c.add_mastery_xp(BE.Family.CABALLERIA, 50)
	b._set_family(u, BE.Family.CABALLERIA, c)
	check(u.type == T.CABALLERIA_PESADA, "maestría %d: caballería pesada" % c.mastery(BE.Family.CABALLERIA))
	check(c.best_family() == BE.Family.CABALLERIA, "su mejor familia es la caballería")

	print("[general]")
	var lord := _char("Señor Famoso", CH.Role.NOBLEZA_ALTA)
	lord.fame = 80
	var knight := _char("Caballero Novato", CH.Role.CABALLERO)
	var comps: Array[Character] = [knight]
	b = BM.new()
	b.random_conditions = false
	b.player_side = BE.Side.DEFENSOR
	b.player_leader = _char("Otro", CH.Role.SOLDADO)
	b.ally_soldiers = 80
	b.start_battle(100, 100, false, _char("Atacante", CH.Role.NOBLEZA_BAJA), lord, "Prueba", comps, NONE)
	check(b.general_of(BE.Side.DEFENSOR) == lord, "el señor nombra general a quien más fama, mando y rango reúne")
	check(b.units.filter(func(x): return x.general and x.side == BE.Side.DEFENSOR).size() == 1, "un único pelotón del general por bando")
	var g_unit = b.units.filter(func(x): return x.general and x.side == BE.Side.ATACANTE)[0]
	g_unit.soldiers = 0
	b._check_rout(g_unit)
	b._check_end()
	check(b.is_over, "cae el general atacante: la batalla termina")
	var b_own = _battle(false, player, _char("Rival", CH.Role.CABALLERO))
	check(b_own.general_of(b_own.player_side) == player and b_own.is_player_general(), "con tu propio ejército, el general eres tú")

	print("[retirada: irse o cubrir]")
	for stay in [false, true]:
		var r = BM.new()
		r.random_conditions = false
		r.player_leader = player
		r.ally_soldiers = 90
		var holder := [{}]
		r.battle_ended.connect(func(_w, rep): holder[0] = rep)
		r.start_battle(120, 100, false, lord, _char("Enemigo", CH.Role.NOBLEZA_BAJA), "Prueba", NONE, NONE)
		check(r.general_of(r.player_side) == lord and not r.is_player_general(), "en una batalla ajena, el general es tu anfitrión")
		r.pending_retreat = true
		r.answer_retreat(stay)
		if not stay:
			check(r.is_over and r.player_side != holder[0].get("winner_side", -1), "retirarte con el ejército: batalla perdida")
		else:
			check(r.covering and r.active_units(r.player_side).all(func(x): return x.own), "cubres la retirada: solo quedan tus pelotones")
			var guard := 0
			while not r.is_over and guard < 10:
				guard += 1
				r.end_player_turn()
			check(r.is_over and (holder[0].get("covered_retreat", false) or r._soldiers_own() == 0), "tras %d turnos termina (cubierta: %s)" % [BM.COVER_TURNS, holder[0].get("covered_retreat", false)])
	var dz = BM.new()
	dz.random_conditions = false
	dz.player_leader = player
	dz.ally_soldiers = 90
	dz.start_battle(120, 100, false, lord, _char("Enemigo", CH.Role.NOBLEZA_BAJA), "Prueba", NONE, NONE)
	dz.retreat()
	check(dz.deserted, "abandonar el campo sin ser general es desertar")

	print("[negociar la tropa]")
	var ok_seen := false
	var fail_seen := false
	var rel_ok := true
	RD.relations.append(Relationship.new())
	var rel: Relationship = RD.relations[-1]
	rel.person_name = lord.full_name()
	rel.character = lord
	rel.kind = Relationship.Kind.SENOR
	for i in 40:
		var n = BM.new()
		n.random_conditions = false
		n.player_leader = player
		n.ally_soldiers = 90
		n.start_battle(120, 100, false, lord, _char("Enemigo", CH.Role.NOBLEZA_BAJA), "Prueba", NONE, NONE)
		var mine = n.player_unit()
		var want: int = (mine.family() + 1) % 4
		var chance: float = n.negotiation_chance(want)
		rel_ok = rel_ok and chance >= BM.NEGOTIATE_MIN and chance <= BM.NEGOTIATE_MAX
		var aff_before := rel.affinity
		var res: Dictionary = n.negotiate_unit(want)
		if res.ok:
			ok_seen = ok_seen or mine.family() == want
		else:
			fail_seen = true
			rel_ok = rel_ok and rel.affinity == aff_before - BM.NEGOTIATE_FAIL_RELATION
		check(i > 0 or not n.negotiate_unit((want + 1) % 4).ok, "solo se negocia una vez por batalla") if i == 0 else null
	check(ok_seen and fail_seen, "la tirada a veces sale y a veces no")
	check(rel_ok, "probabilidad acotada y el fallo baja la afinidad con el general")
	var player_gen = _battle(false, player, _char("Rival", CH.Role.CABALLERO))
	var pu = player_gen.player_unit()
	check(player_gen.negotiation_chance((pu.family() + 1) % 4) == 1.0 and player_gen.negotiate_unit((pu.family() + 1) % 4).ok, "como general eliges tu tropa sin tirada")

	print("[Consejo de guerra]")
	var WCP = load("res://scripts/ui/war_council_panel.gd")
	check(WCP.block_reason(player) == "", "Nobleza Baja puede reunir el Consejo de guerra")
	check(WCP.block_reason(_char("Soldado", CH.Role.SOLDADO)) != "", "un soldado no")
	check(player in WCP.faction_characters(), "la facción incluye al jugador")
	var panel = WCP.open(root)
	await process_frame
	check(panel != null and panel.is_inside_tree(), "el panel se abre")
	panel.queue_free()
	var comp := _char("Compañero", CH.Role.CABALLERO)
	var cb = BM.new()
	cb.random_conditions = false
	var mine_comps: Array[Character] = [comp]
	cb.start_battle(100, 100, false, player, _char("Rival", CH.Role.CABALLERO), "Prueba", mine_comps, NONE)
	var cu = cb.units.filter(func(x): return x.companion == comp)[0]
	comp.assigned_family = (cu.family() + 2) % 4
	cb.apply_assignments()
	check(cu.family() == comp.assigned_family, "la tropa asignada en el Consejo se aplica al pelotón del compañero")
	comp.assigned_family = BE.Family.PIQUEROS
	var cb2 = BM.new()
	cb2.random_conditions = false
	cb2.start_battle(100, 100, false, player, _char("Rival", CH.Role.CABALLERO), "Prueba", mine_comps, NONE)
	check(cb2.units.filter(func(x): return x.companion == comp)[0].family() == BE.Family.PIQUEROS, "y vale para las batallas siguientes")

	print("[Estrategia: visión, intenciones, terreno, habilidades]")
	var fog = BM.new()
	fog.random_conditions = false
	fog.weather = BE.Weather.NIEBLA
	var sage := _char("Estratega", CH.Role.NOBLEZA_BAJA, 15)
	fog.start_battle(100, 100, false, sage, _char("Rival", CH.Role.CABALLERO, 5), "Prueba")
	check(fog.vision_range_for(BE.Side.ATACANTE) == BM.FOG_VISION + 2, "Estrategia 15 ve 2 casillas más en la niebla (%d)" % fog.vision_range_for(BE.Side.ATACANTE))
	check(fog.vision_range_for(BE.Side.DEFENSOR) == BM.FOG_VISION, "Estrategia 5 no")
	check(fog.intent_range() == BM.INTENT_RANGE_BASE + (15 - BM.INTENT_MIN_STRATEGY) / BM.INTENT_STEP, "alcance de lectura del enemigo con Estrategia 15")
	var e = fog.active_units(BE.Side.DEFENSOR)[0]
	e.cell = fog.active_units(BE.Side.ATACANTE)[0].cell + Vector2i(1, 0) if fog.unit_at(fog.active_units(BE.Side.ATACANTE)[0].cell + Vector2i(1, 0)) == null else e.cell
	check(not fog.visible_intents().is_empty(), "adivinas lo que hará un pelotón enemigo cercano")
	var dull = _battle(false, _char("Torpe", CH.Role.NOBLEZA_BAJA, 5), _char("Rival", CH.Role.CABALLERO))
	check(dull.intent_range() == 0, "con poca Estrategia no lees al enemigo")
	var tu = fog.active_units(BE.Side.ATACANTE)[0]
	tu.companion = null
	tu.captain = sage
	fog.terrain[tu.cell.x][tu.cell.y] = BE.Terrain.BOSQUE
	var expected := 1.25 + clampf((15 - BM.TERRAIN_STRATEGY_PIVOT) * BM.TERRAIN_STRATEGY_PER_POINT, 0.0, BM.TERRAIN_STRATEGY_CAP)
	check(absf(fog.unit_terrain_defense(tu, tu.cell) - expected) < 0.001, "bosque: +25%% y +%d%% por Estrategia" % roundi((expected - 1.25) * 100))
	check("por Estrategia" in fog.terrain_text(tu), "el texto lo explica: «%s»" % fog.terrain_text(tu))
	fog.terrain[tu.cell.x][tu.cell.y] = BE.Terrain.VADO
	check(fog.unit_terrain_defense(tu, tu.cell) > 0.8 and fog.unit_terrain_defense(tu, tu.cell) <= 1.0, "en el vado, la Estrategia mitiga la penalización")
	check(BM.ability_scale(sage) > 1.0 and BM.ability_scale(_char("x", CH.Role.SOLDADO, 5)) == 1.0, "las habilidades de mando rinden más con Estrategia alta (y nunca menos)")

	print("[maestría: batallas y acciones del castillo]")
	var fresh := _char("Novato", CH.Role.CABALLERO)
	var mb = BM.new()
	mb.random_conditions = false
	var fresh_comps: Array[Character] = [fresh]
	mb.start_battle(100, 100, false, player, _char("Rival", CH.Role.CABALLERO), "Prueba", fresh_comps, NONE)
	var fam: int = mb.units.filter(func(x): return x.companion == fresh)[0].family()
	mb._end_battle(mb.player_side, "prueba")
	check(int(fresh.mastery_xp.get(str(fam), 0)) == BM.MASTERY_XP_WIN, "ganar da experiencia de mando de la familia que dirigió (%d)" % int(fresh.mastery_xp.get(str(fam), 0)))
	GM.actions_remaining = 6
	player.gold = 500
	change_scene_to_file("res://scenes/castle_interior/castle_interior.tscn")
	await create_timer(0.5).timeout
	var castle_scene = current_scene
	var acts: Array = castle_scene._command_actions()
	check(acts.any(func(a): return a.label.begins_with("Entrenar con la Tropa")) and acts.any(func(a): return a.label.begins_with("Estudiar Táctica"))
		and acts.any(func(a): return a.label == "Consejo de Guerra"), "el castillo ofrece entrenar, estudiar y el Consejo de guerra")
	var xp_before: int = int(player.mastery_xp.get(str(BE.Family.PIQUEROS), 0))
	var lvl_xp: int = player.xp
	castle_scene._action_drill()
	await process_frame
	var pick: Button = null
	for n in castle_scene.find_children("*", "Button", true, false):
		if n.text.begins_with("Piqueros"):
			pick = n
	pick.pressed.emit()
	await process_frame
	check(int(player.mastery_xp.get(str(BE.Family.PIQUEROS), 0)) > xp_before and player.gold == 500 - castle_scene.DRILL_COST, "entrenar con la tropa sube el mando de piqueros y cuesta %d de oro" % castle_scene.DRILL_COST)
	check(player.xp > lvl_xp or player.level > 1, "y da experiencia de personaje")
	castle_scene._note_drill("entrenar")
	check(not castle_scene._command_actions()[0].unavailable.is_empty(), "tope mensual de %d" % castle_scene.DRILL_PER_MONTH)

	print("[guardado]")
	var DC = load("res://scripts/resources/data_codec.gd")
	player.assigned_family = BE.Family.ARQUERIA
	var copy = DC.decode(JSON.parse_string(JSON.stringify(DC.encode(player))))
	check(copy.mastery(BE.Family.PIQUEROS) == player.mastery(BE.Family.PIQUEROS) and copy.assigned_family == BE.Family.ARQUERIA, "maestría y tropa asignada sobreviven al guardado")
	var old = DC.decode(JSON.parse_string(JSON.stringify(DC.encode(CL.make_test_character("Viejo", CH.Role.SOLDADO)))))
	check(old.mastery(0) == 1 and old.assigned_family == -1, "fichas antiguas: maestría 1 y sin asignar")

	print("RESULTADO: %d FALLAS" % fails)
	quit()
