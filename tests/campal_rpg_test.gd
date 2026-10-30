extends SceneTree
# Fase 4: oficiales por pelotón, cada choque cuerpo a cuerpo es un combate RPG (jugado o «Resolver»),
# bonos de tropa, técnicas con tropa o moral mínimas, resultado → bajas/moral/retirada, deserciones y botín.

const SCENE := "res://scenes/rpg_battle/rpg_battle.tscn"
var fails := 0
var CL
var CH
var BM

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _wait_end(scene, limit := 30.0) -> bool:
	var t := 0.0
	while is_instance_valid(scene) and not scene._ended and t < limit:
		await create_timer(0.1).timeout
		t += 0.1
	return is_instance_valid(scene) and scene._ended

func _unit_of(b, c):
	for u in b.units:
		if u.leader() == c:
			return u
	return null

func _enemy_unit(b):
	for u in b.units:
		if u.side != b.player_side and u.is_active():
			return u
	return null

# Pone a «foe» al lado de «u» (los demás, lejos) y deja a «u» listo para atacar.
func _adjacent(b, u, foe) -> void:
	for o in b.units:
		if o != u and o != foe:
			o.cell = Vector2i(-50, -50)
	u.cell = Vector2i(5, 3)
	foe.cell = Vector2i(6, 3)
	for x in b.GRID_W:
		for y in b.GRID_H:
			b.terrain[x][y] = BattleEnums.Terrain.LLANO
	u.has_acted = false
	u.has_moved = false
	b.is_over = false

func _run() -> void:
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	BM = load("res://scripts/resources/battle_manager.gd")
	var RS = load("res://scenes/rpg_battle/rpg_battle.gd")
	RS.test_delay = 0.0
	RS.test_auto = true
	var GM = root.get_node("GameManager")
	var LD = root.get_node("LoyaltyData")
	var RD = root.get_node("RelationsData")
	var p = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	GM.player_character = p

	print("[oficiales]")
	var comp = CL.make_test_character("Sir Hugo", CH.Role.CABALLERO)
	var o1 = CL.make_test_character("Dama Inés", CH.Role.CABALLERO)
	var o2 = CL.make_test_character("Sir Bruno", CH.Role.CABALLERO)
	var b = BM.new()
	b.player_side = BattleEnums.Side.ATACANTE
	b.player_leader = p
	b.faction_officers = {"player": [o1, o2]}
	var comps: Array[Character] = [comp]
	b.start_battle(60, 60, false, p, CL.make_test_character("Enemigo", CH.Role.NOBLEZA_ALTA), "X", comps)
	var pu = _unit_of(b, p)
	check(pu != null and o1 in pu.officers and o2 in pu.officers, "los oficiales van con tu pelotón (%s)" % [pu.officers.map(func(c): return c.full_name()) if pu else "sin pelotón"])
	check(not b.player_is_officer and b.player_unit() == pu, "con séquito, encabezas tu pelotón")
	var inv = BM.new()
	inv.player_side = BattleEnums.Side.ATACANTE
	inv.player_leader = p
	inv.ally_soldiers = 100
	inv.start_battle(100, 120, false, CL.make_test_character("Anfitrión", CH.Role.NOBLEZA_ALTA), CL.make_test_character("Enemigo", CH.Role.NOBLEZA_ALTA), "X")
	var host = null
	for u in inv.units:
		if p in u.officers:
			host = u
	check(inv.player_is_officer and host != null and host.leader() != p and inv.player_unit() == null,
		"sin séquito en una batalla ajena, tu señor te pone de oficial (%s)" % [host.leader().full_name() if host else "-"])

	print("[bonos de tropa y técnicas con requisitos]")
	var t1 = CL.make_test_character("Jinete", CH.Role.CABALLERO)
	var plain := RpgBattleManager.new()
	plain.setup([t1], [CL.make_test_character("X", CH.Role.CABALLERO)])
	var hp0: int = plain.fighters[0].max_hp
	var agi0: float = plain.fighters[0].s.agilidad
	t1.set_meta("campal_troops", {"soldiers": 30, "type": BattleEnums.UnitType.CABALLERIA, "family": BattleEnums.Family.CABALLERIA, "morale": 70, "foe_family": 0})
	var boosted := RpgBattleManager.new()
	boosted.setup([t1], [CL.make_test_character("X", CH.Role.CABALLERO)])
	check(boosted.fighters[0].max_hp > hp0 and boosted.fighters[0].s.agilidad > agi0, "30 jinetes: más PV (%d→%d) y Agilidad" % [hp0, boosted.fighters[0].max_hp])
	var carga: Dictionary = SkillTreeCatalog.node("acon_carga")
	var tgate: Dictionary = SkillTreeCatalog.node("acon_imperio")
	t1.set_meta("campal_troops", {"soldiers": 10, "morale": 30, "family": 0, "foe_family": 0, "type": 0})
	check(not CampalEncounters.technique_allowed(t1, carga) and not CampalEncounters.technique_allowed(t1, tgate), "10 soldados y moral 30: sin «Carga general» ni «Sueño de imperio»")
	t1.set_meta("campal_troops", {"soldiers": 25, "morale": 60, "family": 0, "foe_family": 0, "type": 0})
	check(CampalEncounters.technique_allowed(t1, carga) and CampalEncounters.technique_allowed(t1, tgate), "25 soldados y moral 60: sí")
	t1.remove_meta("campal_troops")
	check(CampalEncounters.technique_allowed(t1, carga), "fuera de las campales no se exige")

	print("[choques]")
	var foe = _enemy_unit(b)
	b.interactive_encounters = true
	var pending := [0]
	b.encounter_pending.connect(func(_e): pending[0] += 1)
	_adjacent(b, pu, foe)
	check(b.attack(pu, foe) and pending[0] == 1 and b.pending_encounters.size() == 1, "tu pelotón choca: el combate se juega en la pantalla RPG")
	var enc: Dictionary = b.pending_encounters[0]
	check(p in enc.a and o1 in enc.a and enc.a.size() <= CampalEncounters.MAX_PARTY and enc.b.size() >= 2, "jefe+oficiales contra jefe+escolta (%d contra %d)" % [enc.a.size(), enc.b.size()])
	var sc = load(SCENE).instantiate()
	sc.side_a = enc.a
	sc.side_b = enc.b
	sc.player_character = enc.a[0]
	sc.enemy_character = enc.b[0]
	sc.embedded = true
	root.add_child(sc)
	check(await _wait_end(sc), "el choque incrustado termina")
	var res: Dictionary = sc.last_result.duplicate()
	sc.queue_free()
	var before := [pu.soldiers + foe.soldiers]
	b.resolve_encounter(enc, res)
	check(b.pending_encounters.is_empty() and pu.soldiers + foe.soldiers < before[0], "el resultado se traduce en bajas (ganó el bando %d)" % int(res.get("winner", -1)))
	# Resolver: misma regla, sin pantalla.
	pu.soldiers = 20
	pu.morale = 70
	foe.soldiers = 20
	foe.morale = 70
	pu.routed = false
	foe.routed = false
	_adjacent(b, pu, foe)
	b.attack(pu, foe)
	var enc2: Dictionary = b.pending_encounters[0]
	b.auto_resolve_pending(enc2)
	check(b.pending_encounters.is_empty() and (pu.soldiers < 20 or foe.soldiers < 20), "«Resolver» aplica el choque solo")
	# Choque ajeno: se resuelve solo.
	var cap_unit = null
	for u in b.units:
		if u.side == b.player_side and u.leader() != null and u.leader().has_meta("captain"):
			cap_unit = u
	foe.soldiers = 20
	foe.routed = false
	foe.morale = 70
	cap_unit.officers.clear()
	_adjacent(b, cap_unit, foe)
	b.attack(cap_unit, foe)
	check(b.pending_encounters.is_empty() and (cap_unit.soldiers < cap_unit.max_soldiers or foe.soldiers < 20), "un choque ajeno se resuelve solo")

	print("[resultado → bajas, moral y retirada]")
	var lost_cas := 0
	var fled_cas := 0
	var lost_mor := 0
	var fled_mor := 0
	var big_wins := 0
	for i in 30:
		for mode in ["lost", "fled"]:
			cap_unit.soldiers = 20
			cap_unit.morale = 70
			cap_unit.routed = false
			foe.soldiers = 20
			foe.morale = 70
			foe.routed = false
			var e := CampalEncounters.make(b, cap_unit, foe, 1)
			var r := {"winner": 1, "retreated": 0 if mode == "fled" else -1, "ko": [], "dead": [], "hp": {}}
			b.resolve_encounter(e, r)
			if mode == "lost":
				lost_cas += 20 - cap_unit.soldiers
				lost_mor += 70 - cap_unit.morale
			else:
				fled_cas += 20 - cap_unit.soldiers
				fled_mor += 70 - cap_unit.morale
	check(fled_cas < lost_cas and fled_mor < lost_mor, "retirarse a tiempo cuesta menos que perder (bajas %d<%d, moral %d<%d)" % [fled_cas, lost_cas, fled_mor, lost_mor])
	# Desigual: 40 contra 8 se pierde casi siempre (huir importa).
	for i in 20:
		cap_unit.soldiers = 8
		foe.soldiers = 40
		var e := CampalEncounters.make(b, cap_unit, foe, 1)
		if int(CampalEncounters.auto_fight(b, e).get("winner", -1)) == 1:
			big_wins += 1
		CampalEncounters.clear_troops(e.a + e.b)
	check(big_wins >= 15, "8 contra 40: el grande gana el choque %d/20" % big_wins)

	print("[traición en la batalla]")
	RD.retinue.append(comp.full_name())
	LD.loyalty[comp.full_name()] = 5
	check(LD.is_disloyal(comp), "Sir Hugo es desleal")
	var cu = _unit_of(b, comp)
	cu.soldiers = maxi(cu.soldiers, 5)
	cu.routed = false
	b.defect_chance_override = 1.0
	for u in b.units:
		if u.side != b.player_side:
			u.soldiers = u.max_soldiers
	var old_side: int = cu.side
	b._check_defections()
	check(cu.side != old_side and b.defections >= 1 and not cu.own, "un pelotón con jefe desleal se pasa al enemigo")
	b.abandon_chance_override = 1.0
	LD.loyalty[o1.full_name()] = 5
	pu.officers.assign([o1, o2])
	var e3 := CampalEncounters.make(b, pu, foe, 1)
	check(not o1 in e3.a and not e3.notes.is_empty(), "un oficial desleal abandona el choque (%s)" % [e3.notes])
	CampalEncounters.clear_troops(e3.a + e3.b)

	print("[botín]")
	p.gold = 0
	LD.loyalty[comp.full_name()] = 60
	for u in b.units:
		if u.side != b.player_side:
			u.soldiers = 0
	var loot := CampalEncounters.battle_loot(b, true)
	check(p.gold > 0 and "séquito" in loot, "victoria: oro y reparto con el séquito (%s)" % loot)
	check(CampalEncounters.battle_loot(b, false).is_empty(), "sin victoria no hay botín")
	check(root.get_node("Settings").auto_resolve_others, "Ajustes: «Resolver solos los choques ajenos» activado por defecto")
	print("FALLOS: %d" % fails)
	quit(fails)
