extends SceneTree
# Fase 3A: núcleo del combate RPG (estadísticas, debilidades, turno extra, línea de turnos, árbol,
# enemigos y retratos, cambiar/abandonar, guardado de learned_skills).

var fails := 0

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _char(ft: int, lvl: int = 1, attr: int = 5) -> Character:
	var c := Character.new()
	c.first_name = "P%d" % randi()
	c.fighter_type = ft
	c.level = lvl
	c.combat = attr
	c.defense = attr
	c.strategy = attr
	c.leadership = attr
	c.charisma = attr
	return c

func _learn_chain(c: Character, id: String) -> bool:
	var n := SkillTreeCatalog.node(id)
	for r in n.req:
		if not SkillTreeCatalog.knows(c, r):
			_learn_chain(c, r)
	return SkillTreeCatalog.knows(c, id) or SkillTreeCatalog.learn(c, id)

func _bm(a: Array, b: Array, opts: Dictionary = {}) -> RpgBattleManager:
	var bm := RpgBattleManager.new()
	opts["seed"] = opts.get("seed", 3)
	bm.setup(a, b, opts)
	return bm

func _run() -> void:
	seed(7)
	var F := CharacterEnums.FighterType
	var DT := RpgStats.DamageType
	var AC := RpgStats.ArmorClass
	var AF := RpgStats.Affinity
	print("[estadísticas]")
	var d := _char(F.DUELISTA)
	var s := RpgStats.compute(d)
	check(s.pv == 70 and is_equal_approx(s.fuerza, 12.5) and is_equal_approx(s.defensa, 8.0), "fórmulas PV/Fuerza/Defensa nivel 1 (%d, %.2f, %.1f)" % [s.pv, s.fuerza, s.defensa])
	check(is_equal_approx(s.agilidad, 18.0) and s.armor == AC.SIN and s.weapon == DT.ESTOCADA, "Agilidad, armadura por rol y arma por tipo")
	var t := _char(F.TANQUE)
	check(RpgStats.compute(t).pv > s.pv and RpgStats.compute(_char(F.DUELISTA, 10)).pv > s.pv, "tanque y nivel suben los PV")
	print("[debilidades]")
	# Círculo: una debilidad por arma; Placas resiste todo salvo Contundente; el resto, neutro.
	var weak_of := {DT.TAJO: AC.SIN, DT.ESTOCADA: AC.MALLA, DT.CONTUNDENTE: AC.PLACAS, DT.PROYECTIL: AC.CUERO}
	var table_ok := true
	for dt in weak_of:
		for ac in [AC.SIN, AC.CUERO, AC.MALLA, AC.PLACAS]:
			var want: int = AF.DEBIL if ac == weak_of[dt] else (AF.RESISTE if ac == AC.PLACAS else AF.NORMAL)
			if RpgStats.affinity(dt, ac) != want:
				table_ok = false
	check(table_ok, "tabla fija (círculo de debilidades, Placas resiste)")
	check(RpgStats.affinity(DT.PROYECTIL, AC.CUERO, true) == AF.NORMAL, "el escudo mejora un paso ante Proyectil")
	# Débil sin la pasiva → solo más daño, no hay acción extra (derribado: acierto seguro y débil a todo).
	var a := _char(F.TANQUE, 5, 8)
	var e := EnemyCatalog.make_enemy("infanteria_pesada", 5)
	var bm := _bm([a], [e])
	var fa: RpgBattleManager.Fighter = bm.fighter_of(a)
	var fe: RpgBattleManager.Fighter = bm.fighter_of(e)
	fa.next_time = 0.0
	fa.s.crit = -1.0
	fa.s.fx.erase("brecha")
	var who := bm.next_turn()
	fe.statuses["derribado"] = {"turns": 1, "src": fa, "power": 0.0}
	var info := bm.act(who, {"type": "atacar", "target": fe})
	check(info.hits[0].aff == AF.DEBIL and not info.get("extra", false) and bm.current == null, "golpe débil sin «brecha» → sin acción extra")
	# Con la pasiva «brecha» → una acción extra, solo una por turno.
	a = _char(F.TANQUE, 5, 8)
	e = EnemyCatalog.make_enemy("infanteria_pesada", 5)
	bm = _bm([a], [e])
	fa = bm.fighter_of(a)
	fe = bm.fighter_of(e)
	fa.next_time = 0.0
	fa.s.crit = -1.0
	fa.s.fx["brecha"] = 1.0
	who = bm.next_turn()
	fe.statuses["derribado"] = {"turns": 1, "src": fa, "power": 0.0}
	info = bm.act(who, {"type": "atacar", "target": fe})
	check(info.get("extra", false) and bm.next_turn() == fa, "golpe débil con «brecha» → acción extra del mismo luchador")
	fe.statuses["derribado"] = {"turns": 1, "src": fa, "power": 0.0}
	info = bm.act(fa, {"type": "atacar", "target": fe})
	check(not info.get("extra", false) and bm.current == null, "como mucho 1 acción extra por turno")
	check(SkillTreeCatalog.node("due_brecha").get("fx", {}).get("brecha", 0) > 0 and SkillTreeCatalog.node("ase_brecha").get("fx", {}).get("brecha", 0) > 0
		and SkillTreeCatalog.EQUIPMENT_NODES.get("Estoque", "") == "due_brecha" and SkillTreeCatalog.UNIQUE_FX.sangrado.get("brecha", 0) > 0, "«brecha»: nodos, Estoque y Misericordia de Toledo")
	# Resiste → solo menos daño: ni pierde el ritmo ni se retrasa.
	var res_ok := false
	for i in 20:
		var b := _char(F.DUELISTA, 5, 8)
		b.set_meta(RpgStats.META_DAMAGE, DT.TAJO)
		var e2 := EnemyCatalog.make_enemy("caballero_pesado", 5)
		var bm2 := _bm([b], [e2], {"seed": i})
		var fb: RpgBattleManager.Fighter = bm2.fighter_of(b)
		fb.next_time = 0.0
		fb.s.crit = -1.0
		var before := bm2.next_turn()
		var expected := bm2.now + fb.interval()
		var inf2 := bm2.act(before, {"type": "atacar", "target": bm2.fighter_of(e2)})
		if inf2.hits.size() > 0 and inf2.hits[0].hit:
			res_ok = not inf2.get("lost", false) and is_equal_approx(fb.next_time, expected) and inf2.hits[0].aff == AF.RESISTE
			break
	check(res_ok, "golpe resistido → menos daño, sin perder ni retrasar el turno")
	print("[línea de turnos]")
	var slow := _char(F.TANQUE, 1, 3)
	var fast := _char(F.ASESINO, 1, 12)
	var mid := _char(F.DUELISTA, 1, 7)
	var bm3 := _bm([slow, fast], [mid])
	var tl := bm3.timeline(4)
	check(tl[0].c == fast and tl.size() == 4, "el más ágil va primero en la línea")
	check(bm3.next_turn().c == fast, "next_turn sigue la línea")
	print("[árbol]")
	var bad := []
	for n: Dictionary in SkillTreeCatalog.NODES:
		if n.tree == SkillTreeCatalog.TREE_BOSS:
			continue
		var c := _char(F.DUELISTA if n.tree == SkillTreeCatalog.TREE_COMMON else n.tree, 20)
		SkillTreeCatalog.ensure_kit(c)
		var has_effect: bool = float(n.get("pow", 0)) > 0 or not n.get("st", []).is_empty() or n.has("heal") or not n.get("fx", {}).is_empty()
		if not _learn_chain(c, n.id) or not has_effect:
			bad.append(n.id)
	check(bad.is_empty(), "todos los nodos se aprenden y tienen efecto %s" % [bad])
	for ft in F.values():
		check(SkillTreeCatalog.nodes_of_tree(ft).size() in [15, 16], "%s: 15-16 nodos" % CharacterEnums.fighter_type_name(ft))
	var low := _char(F.DUELISTA, 1)
	check(not SkillTreeCatalog.can_learn(low, "due_corazon") and not SkillTreeCatalog.can_learn(low, "tan_mazazo"), "requisitos de nivel/árbol")
	var npc := _char(F.ASESINO, 8)
	SkillTreeCatalog.auto_learn(npc)
	check(SkillTreeCatalog.points_free(npc) == 0 and SkillTreeCatalog.available_techniques(npc).size() >= 3, "auto_learn gasta los puntos (%d técnicas)" % SkillTreeCatalog.available_techniques(npc).size())
	var p0: int = RpgStats.compute(npc).pv
	npc.learned_skills.append("com_aguante")
	check(RpgStats.compute(npc).pv > p0, "una pasiva cambia las estadísticas")
	print("[enemigos]")
	var bandit := EnemyCatalog.make_enemy("bandido", 5)
	check(bandit.portrait != null and str(bandit.get_meta("portrait_path")) == "res://assets/portraits/roles/bandido.png", "sin carpeta: retrato del rol")
	var boss := EnemyCatalog.make_enemy("capitan_bandido", 5)
	check(RpgStats.compute(boss).actions == 2 and RpgStats.compute(boss).pv > RpgStats.compute(bandit).pv * 1.5, "mini jefe: 2 acciones y más PV")
	EnemyCatalog._folder_cache["prueba"] = ["x1", "x2"]
	var used := {}
	var p1 := EnemyCatalog.pick_portrait("prueba", used)
	var p2 := EnemyCatalog.pick_portrait("prueba", used)
	check(p1 != p2 and EnemyCatalog.pick_portrait("prueba", used) in ["x1", "x2"], "no repite retrato en un encuentro mientras queden")
	EnemyCatalog._folder_cache.erase("prueba")
	var party := EnemyCatalog.make_party("camino", 4, 1)
	check(party.size() == 3 and party[0].full_name() != party[1].full_name(), "plantilla de grupo con nombres distintos")
	print("[cambiar y abandonar]")
	var team: Array = []
	for i in 5:
		team.append(_char(F.DUELISTA, 3, 6))
	var bm4 := _bm(team, [EnemyCatalog.make_enemy("soldado", 3)])
	check(bm4.active_of(0).size() == 4 and bm4.reserve_of(0).size() == 1, "4 activos + reserva")
	var f4: RpgBattleManager.Fighter = bm4.fighter_of(team[0])
	f4.next_time = 0.0
	bm4.next_turn()
	var res: RpgBattleManager.Fighter = bm4.reserve_of(0)[0]
	bm4.act(f4, {"type": "cambiar", "reserve": res})
	check(res.active and not f4.active and bm4.current == null, "cambiar gasta el turno")
	var bm5 := _bm([_char(F.DUELISTA, 3)], [EnemyCatalog.make_enemy("soldado", 3)], {"can_flee": false})
	var f5 := bm5.next_turn()
	if f5.side == 1:
		bm5.act(f5, {"type": "defender"})
		f5 = bm5.next_turn()
	bm5.act(f5, {"type": "abandonar", "mode": "retirarse"})
	check(not bm5.ended, "sin huida posible no se retira")
	f5 = bm5.next_turn()
	if f5.side == 1:
		bm5.act(f5, {"type": "defender"})
		f5 = bm5.next_turn()
	bm5.act(f5, {"type": "abandonar", "mode": "rendirse"})
	check(bm5.ended and bm5.result.winner == 1 and bm5.result.surrendered == 0, "rendirse acaba el combate")
	var heroes := [_char(F.BERSERKER, 8, 10), _char(F.DEFENSOR, 8, 10), _char(F.DUELISTA, 8, 10)]
	for h: Character in heroes:
		h.role = Character.Role.CABALLERO   # Malla: resiste el Tajo de los bandidos
	var bm6 := _bm(heroes, EnemyCatalog.make_party("camino", 3, 0), {"to_the_death": true})
	var r6 := bm6.run_auto()
	check(r6.winner == 0 and not r6.xp.is_empty() and r6.dead.size() >= 2, "combate automático: gana, experiencia y muertos en lucha a muerte (%s, %d xp, %d muertos)" % [r6.winner, r6.xp.size(), r6.dead.size()])
	print("[guardado]")
	var sv := _char(F.ESTRATEGA, 6)
	SkillTreeCatalog.auto_learn(sv)
	var DC = load("res://scripts/resources/data_codec.gd")
	var back: Character = DC.from_json(DC.to_json(sv))
	check(back != null and Array(back.learned_skills) == Array(sv.learned_skills) and back.learned_skills.size() > 0, "learned_skills se guarda y se carga")
	print("FALLAS: %d" % fails if fails else "TODO OK")
	quit()
