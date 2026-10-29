extends SceneTree
# Reparto de hombres antes de la batalla: mínimo/máximo por Liderazgo, soldada solo de contratados,
# tu gente gratis, sin oro no se confirma y el reparto por defecto funciona.

var fails := 0

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _led(b, c) -> int:
	for u in b.units:
		if u.side == b.player_side and not u.ally and u.leader() == c:
			return u.soldiers
	return -1

func _run() -> void:
	var GM = root.get_node("GameManager")
	var CS = root.get_node("CombatSetup")
	var MD = root.get_node("MapData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var BM = load("res://scripts/resources/battle_manager.gd")
	var EC = load("res://scripts/resources/event_catalog.gd")

	print("[reglas]")
	var p = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	var comp = CL.make_test_character("Sir Hugo", CH.Role.CABALLERO)
	p.leadership = 12
	comp.leadership = 5
	check(CS.platoon_max(p) == 34 and CS.platoon_max(comp) == 20, "máximo = 10 + 2×Liderazgo (12→34, 5→20)")
	var alloc := {p.full_name(): 30, comp.full_name(): 15}
	check(CS.soldada_cost(alloc, p.full_name(), true) == (15 + 15) * CS.SOLDADA_PER_MAN, "soldada: tus 15 allegados gratis, el resto a 2")
	check(CS.soldada_cost(alloc, p.full_name(), false) == 0, "tu propia gente no cobra")
	var comps: Array[Character] = [comp]
	var d: Dictionary = CS.default_allocation(p, comps, 0, 20)
	check(d[p.full_name()] == 20 and d[comp.full_name()] == CS.PLATOON_MIN, "por defecto: tu leva por rango y el mínimo por compañero (%s)" % d)
	var d2: Dictionary = CS.default_allocation(p, comps, 40, 20)
	check(int(d2[p.full_name()]) + int(d2[comp.full_name()]) <= 40, "con tu gente no se reparte más de la que tienes (%s)" % d2)

	print("[batalla]")
	var b = BM.new()
	b.player_side = BattleEnums.Side.ATACANTE
	b.player_leader = p
	b.ally_soldiers = 100
	b.own_allocation = {p.full_name(): 30, comp.full_name(): 15}
	b.start_battle(100 + 45, 120, false, CL.make_test_character("Anfitrión", CH.Role.NOBLEZA_ALTA), CL.make_test_character("Enemigo", CH.Role.NOBLEZA_ALTA), "X", comps)
	check(_led(b, p) == 30 and _led(b, comp) == 15, "batalla ajena: tu pelotón 30 y el del compañero 15 (%d / %d)" % [_led(b, p), _led(b, comp)])
	var b2 = BM.new()
	b2.player_side = BattleEnums.Side.ATACANTE
	b2.player_leader = p
	b2.own_allocation = {p.full_name(): 34, comp.full_name(): 15}
	b2.start_battle(100, 80, false, p, CL.make_test_character("Enemigo", CH.Role.NOBLEZA_ALTA), "X", comps)
	check(_led(b2, p) == 34 and _led(b2, comp) == 15 and b2.total_soldiers(BattleEnums.Side.ATACANTE) == 100,
		"tu ejército: 34 + 15 y el resto para los capitanes (total %d)" % b2.total_soldiers(BattleEnums.Side.ATACANTE))

	print("[consejo]")
	GM.start_new_game(p, MD.castles[0].castle_id)
	MD.get_castle_by_id(GM.home_castle_id).garrison_size = 100
	var bandits: Dictionary = {}
	for e in EC.EVENTS:
		if e.id == "bandidos":
			bandits = e
	var fight: Dictionary = bandits.options.filter(func(o): return o.has("fight") and o.fight.type == "battle")[0].fight
	change_scene_to_file(CS.begin_event_fight(fight, bandits.title))
	await create_timer(0.8).timeout
	var sc = current_scene
	check(sc._go_btn != null and not sc._go_btn.disabled, "escaramuza con tu guarnición: se confirma sin pagar")
	var mine0: int = sc._allocation.get(p.full_name(), 0)
	check(mine0 >= 1 and sc._alloc_cost() == 0, "reparto por defecto aplicado (tu pelotón %d) y gratis" % mine0)
	# Mismo consejo, pero con hombres contratados y sin oro.
	sc._alloc_hired = true
	p.gold = 0
	sc.change_allocation(p, 5)
	sc._update_allocation_ui()
	check(sc._go_btn.disabled, "contratados y sin oro: no se puede confirmar (coste %d)" % sc._alloc_cost())
	p.gold = 1000
	sc._update_allocation_ui()
	var cost: int = sc._alloc_cost()
	sc._confirm_council()
	check(p.gold == 1000 - cost and sc._council == null, "con oro: se paga la soldada (%d) y empieza la batalla" % cost)
	print("FALLAS: ", fails)
	quit(fails)
