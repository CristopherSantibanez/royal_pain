extends SceneTree
# Edificios (obras por meses y efectos) y lugares para explorar (aparición, visita, combate, guardado).

var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func check(cond: bool, msg: String) -> void:
	print(("OK   " if cond else "FAIL ") + msg)
	if not cond:
		fails += 1

func _run() -> void:
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var EX = root.get_node("ExplorationData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var BC = load("res://scripts/resources/building_catalog.gd")
	var KAI = load("res://scripts/resources/kingdom_ai.gd")
	var SP = load("res://scripts/ui/shop_panel.gd")
	var WP = load("res://scripts/ui/works_panel.gd")
	var SS = load("res://scripts/resources/save_system.gd")

	# --- Obras: un caballero no puede; la nobleza sí ---
	var knight = CL.make_test_character("Sir Prueba", CH.Role.CABALLERO)
	GM.start_new_game(knight, MD.castles[0].castle_id)
	var home = MD.get_castle_by_id(GM.home_castle_id)
	home.gold = 2000
	check(WP.build_block_reason(knight, home, "mercado") != "", "caballero no puede ordenar obras: " + WP.build_block_reason(knight, home, "mercado"))

	var noble = CL.make_test_character("Don Prueba", CH.Role.NOBLEZA_BAJA)
	GM.start_new_game(noble, MD.castles[0].castle_id)
	home = MD.get_castle_by_id(GM.home_castle_id)
	home.gold = 3000
	home.garrison_size = 60
	home.food = 900
	check(WP.build_block_reason(noble, home, "mercado") == "", "noble puede ordenar obras")
	var before_gold: int = home.gold
	home.start_construction("mercado")
	check(home.gold == before_gold - 120 and home.construction_months_left == 2, "obra cobra 120 y dura 2 meses")
	check(WP.build_block_reason(noble, home, "murallas").begins_with("Ya hay una obra"), "una sola obra a la vez")
	GM.turn_advanced.emit(1, 1)
	check(home.building_level("mercado") == 0 and home.construction_months_left == 1, "a mitad de obra")
	GM.turn_advanced.emit(2, 1)
	check(home.building_level("mercado") == 1 and not home.is_building(), "mercado terminado (nivel 1)")

	# Efecto del mercado: ingresos +12 respecto a un castillo igual sin mercado
	var a = home.duplicate()
	var b = home.duplicate()
	b.buildings = {}
	a.garrison_size = 0; b.garrison_size = 0; a.gold = 100; b.gold = 100
	var arr: Array[Castle] = [a, b]
	KAI.castle_economy(arr, false)
	check(a.gold - b.gold == 12, "mercado da +12 de oro al mes (%d vs %d)" % [a.gold, b.gold])

	# Murallas, cuartel, herrería y capilla
	for id in ["murallas", "cuartel", "herreria", "capilla"]:
		home.buildings[id] = 3
	check(is_equal_approx(home.wall_bonus(), 0.45), "murallas 3 => wall_bonus 0.45")
	var c1 = home.duplicate(); c1.garrison_size = 50
	var c2 = home.duplicate(); c2.garrison_size = 50; c2.buildings = {}
	var arr2: Array[Castle] = [c1, c2]
	KAI.recruit(arr2)
	check(c1.garrison_size - c2.garrison_size == 3, "cuartel 3 => +3 reclutas al mes")
	GM.current_castle = home
	var stock = SP.monthly_stock(knight, home.castle_id)
	check(stock.any(func(e): return e.tier == 3), "herrería 3 trae piezas ★★★ a un caballero")
	var item = stock[0]
	var base_price := roundi(item.price * clampf(1.0 - (noble.charisma - 10) * 0.02, 0.8, 1.2))
	check(SP.buy_price(item, noble) < base_price, "herrería abarata precios (%d < %d)" % [SP.buy_price(item, noble), base_price])
	noble.current_health = 40
	var honor_before: int = noble.honor
	GM.turn_advanced.emit(3, 1)
	check(noble.current_health >= 55, "capilla cura (+15) además del descanso: vida %d" % noble.current_health)
	check(noble.honor >= honor_before, "capilla no resta honor")

	# La IA también construye
	for c in MD.castles:
		if c != home:
			c.gold = 1500
	for i in 10:
		GM.turn_advanced.emit(4 + i, 1)
	var ai_works := 0
	for c in MD.castles:
		if c != home and (c.is_building() or not c.buildings.is_empty()):
			ai_works += 1
	check(ai_works > 0, "la IA ordena obras (%d castillos)" % ai_works)

	# --- Lugares ---
	EX.reset()
	var site = EX.spawn_site("monasterio", home.castle_id)
	check(not site.is_empty() and EX.sites.size() == 1, "aparece un lugar")
	check(EX.site_position(site).distance_to(home.position_on_map) <= 115.0, "cerca de su castillo")
	var torre = EX.spawn_site("torre_negra", home.castle_id)
	var camp = EX.spawn_site("campamento_bandido", home.castle_id)
	GM.actions_remaining = 3
	var xp_before: int = noble.xp + noble.level * 100000
	noble.current_health = 10
	var r = EX.visit(site.uid, 0)
	check(r.ok and EX.find(site.uid).is_empty(), "visita al monasterio: " + str(r.get("text", "")).replace("\n", " "))
	check(noble.xp + noble.level * 100000 > xp_before, "explorar da experiencia")
	check(GM.actions_remaining == 2, "explorar gasta una acción")
	noble.current_health = noble.max_health
	noble.wound_months = 0
	var r2 = EX.visit(torre.uid, 0)
	check(r2.ok and r2.fight.get("to_death", false), "torre negra ofrece duelo a muerte")
	var r3 = EX.visit(camp.uid, 0)
	check(r3.ok and r3.fight.get("type", "") == "battle", "campamento: escaramuza")
	GM.actions_remaining = 0
	var s4 = EX.spawn_site("mina", home.castle_id)
	check(not EX.visit(s4.uid, 0).ok, "sin acciones no se explora")

	# Caducan
	var months: int = int(s4.months_left)
	for i in months:
		GM.turn_advanced.emit(1, 2)
	check(EX.find(s4.uid).is_empty(), "el lugar desaparece al cabo de %d meses" % months)

	# Recompensa de objeto
	var EC = load("res://scripts/resources/event_catalog.gd")
	var n_items: int = noble.equipment.size()
	var gold_b: int = noble.gold
	var txt: String = EC._apply_effects({"item": 2, "xp": 10}, noble, home)
	check(noble.equipment.size() > n_items or noble.gold > gold_b or txt.contains("Encuentras"), "efecto item: " + txt)

	# --- Guardado ---
	EX.reset()
	EX.spawn_site("ruinas", home.castle_id)
	EX.spawn_site("cueva", home.castle_id)
	home.start_construction("establos")
	home.buildings["murallas"] = 2
	var saved_sites = EX.sites.duplicate(true)
	check(SS.save_game("1") == OK, "guarda en ranura 1 (carpeta de pruebas)")
	EX.reset()
	home.buildings = {}
	home.construction_id = ""
	check(SS.load_game("1"), "carga la ranura 1")
	var home2 = MD.get_castle_by_id(GM.home_castle_id)
	check(home2.building_level("murallas") == 2 and home2.construction_id == "establos", "edificios y obra en curso tras cargar")
	check(EX.sites.size() == 2 and EX.sites[0].type == saved_sites[0].type and is_equal_approx(float(EX.sites[0].x), float(saved_sites[0].x)), "lugares tras cargar")
	SS.delete_save("1")

	print("RESULTADO: %s (%d fallos)" % ["OK" if fails == 0 else "FALLOS", fails])
	quit()
