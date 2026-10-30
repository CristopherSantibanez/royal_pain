extends SceneTree
# Premisas de los sucesos: cada rol y situación recibe sucesos que encajan con su vida.
# Un no afiliado no abre graneros, un campesino no gobierna un castillo, sin señor no hay órdenes del señor.

var fails := 0
var GM; var MD; var RD; var SE; var CL; var CH; var EC; var WEC

# Sucesos cuya premisa es gobernar un castillo (graneros, tesoro, guarnición, justicia, recibir visitas).
const GOVERNANCE := ["saqueadores", "disputa", "incendio", "voluntarios", "g_peste", "g_hambruna",
	"g_mercenarios", "g_embajada", "g_invierno", "soc_peticion_grano", "soc_visita"]
const LANDED := ["recaudador", "cosecha_parcela", "juicio_combate"]
const LIEGE := ["soc_elogio", "soc_reproche", "soc_orden", "soc_banquete"]
const MIN_MONTHLY := 4

func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok  ", what)
	else:
		fails += 1
		print("  FALLA ", what)

func _initialize() -> void:
	_run.call_deferred()

func _setup(role: int, at_home: bool, liege: bool, owns: bool) -> Variant:
	var p = CL.make_test_character("Prueba Sucesos", CH.Role.NOBLEZA_BAJA if role == CH.Role.INAFILIADO else role)
	p.fame = 300
	p.gold = 500
	GM.start_new_game(p, MD.castles[0].castle_id)
	p.role = role
	for c in MD.castles:
		if c.owner_name == p.full_name():
			c.owner_name = "Otro Señor"
	if owns:
		MD.castles[1].owner_name = p.full_name()
	if not at_home:
		GM.home_castle_id = ""
	RD.liege_name = MD.castles[0].owner_name if liege else ""
	GM.pending_event = {}
	GM.event_queue.clear()
	return p

func _scenario(label: String, role: int, at_home: bool, liege: bool, owns: bool, expect: Dictionary) -> void:
	var p = _setup(role, at_home, liege, owns)
	var ctx: Dictionary = EC.situation(p)
	for k in expect:
		check(bool(ctx[k]) == bool(expect[k]), "%s: %s = %s" % [label, k, expect[k]])
	var seen := {}
	for i in range(3000):
		var e: Dictionary = EC.roll_monthly(p)
		if not e.is_empty():
			seen[e.id] = true
		var g: Dictionary = WEC.pick_player_event(p)
		if not g.is_empty():
			seen[g.id] = true
		if i < 300:
			SE.cooldowns = {}
			var l: Dictionary = SE.lord_event("")
			if not l.is_empty():
				seen[str(l.get("id", ""))] = true
			for deed in ["victoria", "deshonra"]:
				l = SE.lord_event(deed)
				if not l.is_empty():
					seen[str(l.get("id", ""))] = true
	var bad: Array = []
	for id in seen:
		if (not ctx.governs and id in GOVERNANCE) or (not ctx.landed and id in LANDED) or (not ctx.has_liege and id in LIEGE):
			bad.append(id)
	check(bad.is_empty(), "%s: ningún suceso fuera de lugar %s" % [label, bad])
	var monthly: int = EC.eligible_events(p, ctx).size()
	var global_n: int = WEC.PLAYER_EVENTS.filter(func(e): return EC.fits_role(e, p) and EC.fits_situation(e, ctx)).size()
	print("  [%s] mensuales elegibles: %d, globales: %d, vistos: %d" % [label, monthly, global_n, seen.size()])
	check(monthly >= MIN_MONTHLY, "%s: al menos %d sucesos mensuales (%d)" % [label, MIN_MONTHLY, monthly])

func _run() -> void:
	GM = root.get_node("GameManager"); MD = root.get_node("MapData"); RD = root.get_node("RelationsData")
	SE = root.get_node("SocialEvents")
	CL = load("res://scripts/resources/character_loader.gd"); CH = load("res://scripts/resources/character.gd")
	EC = load("res://scripts/resources/event_catalog.gd"); WEC = load("res://scripts/resources/world_event_catalog.gd")
	seed(4242)
	var R = CH.Role
	_scenario("No afiliado", R.INAFILIADO, false, false, false, {"governs": false, "landed": false, "wanderer": true, "has_liege": false})
	_scenario("Campesino", R.CAMPESINO, true, true, false, {"governs": false, "landed": true, "wanderer": false})
	_scenario("Soldado", R.SOLDADO, true, true, false, {"governs": false, "landed": true})
	_scenario("Caballero", R.CABALLERO, true, true, false, {"governs": false, "landed": true, "has_liege": true})
	_scenario("Caballero con castillo", R.CABALLERO, true, true, true, {"governs": true})
	_scenario("Nobleza Baja en casa", R.NOBLEZA_BAJA, true, true, false, {"governs": true, "has_liege": true})
	_scenario("Nobleza Baja sin tierra", R.NOBLEZA_BAJA, false, false, false, {"governs": false, "landed": false, "has_liege": false})
	_scenario("Nobleza Alta", R.NOBLEZA_ALTA, true, true, false, {"governs": true})
	_scenario("Duque", R.DUQUE, true, true, false, {"governs": true})
	_scenario("Regente", R.REGENTE, true, false, false, {"governs": true, "has_liege": false})
	print("RESULTADO: %s (%d fallos)" % ["OK" if fails == 0 else "FALLA", fails])
	quit(1 if fails > 0 else 0)
