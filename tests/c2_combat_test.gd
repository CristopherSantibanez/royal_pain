extends SceneTree
# Pruebas de combos del duelo, duelo a muerte, órdenes, clima, habilidades de mando y mapas variados.

var DM
var CE
var BM
var BE
var BU
var CL
var CH
var fails := 0
var passes := 0

func _initialize() -> void:
	_run.call_deferred()

func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("FAIL: ", label)

func _knight(n: String) -> Character:
	var c: Character = CL.make_test_character(n, CH.Role.CABALLERO)
	c.combat = 8
	c.defense = 6
	return c

func _run() -> void:
	DM = load("res://scripts/resources/duel_manager.gd")
	CE = load("res://scripts/resources/combat_enums.gd")
	BM = load("res://scripts/resources/battle_manager.gd")
	BE = load("res://scripts/resources/battle_enums.gd")
	BU = load("res://scripts/resources/battle_unit.gd")
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	seed(3)
	_duel_tests()
	_setup_tests()
	_terrain_tests()
	_order_tests()
	_weather_tests()
	_ability_tests()
	print("combat_test: %d ok, %d fallos" % [passes, fails])
	quit()

# --- Duelo ---
func _duel_tests() -> void:
	var got := {"contra": 0, "acecho": 0, "desequilibrio": 0}
	var contra_parried := 0
	var predictable_seen := false
	for i in 300:
		var a := _knight("A")
		var b := _knight("B")
		var d = DM.new()
		d.start_duel(a, b)
		# B prepara una parada o esquiva; A ataca. Luego A empuja.
		d.take_turn(b, [CE.ActionType.CONTRAATACAR, CE.ActionType.ESQUIVAR].pick_random())
		if d.is_over: continue
		d.take_turn(a, CE.ActionType.ATACAR)
		if d.is_over: continue
		for k in got:
			if d.advantage.get(b, "") == k:
				got[k] += 1
		if d.advantage.get(b, "") == "contra":
			check(not d.advantage_text(b).is_empty(), "texto de ventaja")
			# A intenta parar la contra: no debe funcionar.
			d.take_turn(a, CE.ActionType.CONTRAATACAR)
			if d.is_over: continue
			var hp_a := a.current_health
			d.take_turn(b, CE.ActionType.ATACAR)
			if a.current_health == hp_a and not d.is_over:
				contra_parried += 1
			check(d.advantage.get(b, "") != "contra", "la contra se gasta al usarla")
		if not d.is_over:
			d.posture[b] = CE.Posture.OFENSIVA   # Defensiva no deja empujar
			d.take_turn(b, CE.ActionType.EMPUJAR)
		if not d.is_over and d.unbalanced.get(a, false):
			got["desequilibrio"] += 1
			check(d.advantage.get(b, "") == "desequilibrio", "empujar da desequilibrio")
		# Previsible: dos ataques seguidos en Defensiva.
		if not d.is_over:
			d.posture[a] = CE.Posture.DEFENSIVA
			d.last_actions[a] = [CE.ActionType.ATACAR, CE.ActionType.ATACAR]
			if d.is_predictable(a):
				predictable_seen = true
			d.posture[a] = CE.Posture.OFENSIVA
			check(not d.is_predictable(a), "en Ofensiva no es previsible")
	check(got.contra > 0, "parar da contra (%d)" % got.contra)
	check(got.acecho > 0, "esquivar da acecho (%d)" % got.acecho)
	check(got.desequilibrio > 0, "empujar desequilibra (%d)" % got.desequilibrio)
	check(contra_parried == 0, "la contra no se puede parar (%d)" % contra_parried)
	check(predictable_seen, "tercer ataque previsible")

# --- CombatSetup ---
func _setup_tests() -> void:
	var cs = root.get_node("CombatSetup")
	var gm = root.get_node("GameManager")
	var p := _knight("Jugador")
	cs.duel_to_death = true
	cs.start_campaign_duel(p, _knight("R"))
	check(cs.duel_to_death == false, "start_campaign_duel reinicia duel_to_death")
	gm.player_character = p
	var scene: String = cs.begin_event_fight({"type": "duel", "to_death": true, "foe": {}}, "Prueba")
	check(scene.ends_with("combat.tscn") and cs.duel_to_death, "begin_event_fight activa el duelo a muerte")
	cs.clear()
	check(cs.duel_to_death == false, "clear reinicia duel_to_death")
	cs.pending_outcome = {}
	gm.player_character = null

# --- Mapas ---
func _passable_path(b) -> bool:
	var start := Vector2i(1, 0)
	var seen := {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		if c.x >= BM.GRID_W - 3:
			return true
		for dir in BM.DIRS:
			var n: Vector2i = c + dir
			if b.in_bounds(n) and not seen.has(n) and b.terrain_at(n) != BE.Terrain.RIO:
				seen[n] = true
				frontier.append(n)
	return false

func _terrain_tests() -> void:
	var features := {}
	for i in 240:
		var b = BM.new()
		b.biome = i % 12
		var walls := i % 4 != 0
		b.start_battle(80, 60, walls, _knight("C1"), _knight("C2"), "X")
		var wall_cells := 0
		var deploy_ok := true
		for x in BM.GRID_W:
			for y in BM.GRID_H:
				var t: int = b.terrain[x][y]
				if t == BE.Terrain.MURALLA:
					wall_cells += 1
				if (x <= 1 or x >= BM.GRID_W - 2) and not t in [BE.Terrain.LLANO, BE.Terrain.MURALLA]:
					deploy_ok = false
		check(deploy_ok, "zonas de despliegue despejadas")
		check((wall_cells > 0) == walls, "muralla solo en asedios")
		check(_passable_path(b), "siempre hay paso de un lado a otro (%s)" % b.map_feature)
		if not walls:
			check(b.map_feature.is_empty(), "escaramuza en campo abierto")
		features[b.map_feature.split(" ")[1] if not b.map_feature.is_empty() else "-"] = true
		for u in b.units:
			check(b.terrain_at(u.cell) != BE.Terrain.RIO, "ningún pelotón en el río")
	for f in ["río", "aldea", "bosque", "loma"]:
		check(features.has(f), "aparece el rasgo " + f)

func _duel_board(walls := false):
	var b = BM.new()
	b.random_conditions = false
	b.start_battle(40, 40, walls, _knight("C1"), _knight("C2"), "X")
	for x in BM.GRID_W:
		for y in BM.GRID_H:
			b.terrain[x][y] = BE.Terrain.LLANO
	return b

func _unit(b, side: int, type: int, cell: Vector2i):
	var u = BU.new()
	u.side = side
	u.type = type
	u.soldiers = 60
	u.max_soldiers = 60
	u.morale = 70
	u.cell = cell
	b.units.append(u)
	return u

# --- Órdenes ---
func _order_tests() -> void:
	var b = _duel_board()
	b.units.clear()
	var inf = _unit(b, BE.Side.ATACANTE, BE.UnitType.INFANTERIA, Vector2i(4, 3))
	var foe = _unit(b, BE.Side.DEFENSOR, BE.UnitType.INFANTERIA, Vector2i(5, 3))
	var base: int = b.preview_attack(foe, inf).casualties
	check(b.set_order(inf, BE.Order.MANTENER), "dar Mantener")
	check(not b.can_move(inf), "Mantener impide moverse")
	check(b.preview_attack(foe, inf).casualties < base, "Mantener reduce bajas")
	b.set_order(inf, BE.Order.MANTENER)
	check(inf.order == BE.Order.NINGUNA, "repetir la orden la anula")
	var normal: int = b.preview_attack(inf, foe).casualties
	b.set_order(inf, BE.Order.CARGAR)
	check(b.preview_attack(inf, foe).casualties > normal, "Cargar aumenta el daño")
	b.attack(inf, foe)
	check(inf.order == BE.Order.NINGUNA, "la carga se gasta al golpear")
	var arch = _unit(b, BE.Side.ATACANTE, BE.UnitType.ARQUEROS, Vector2i(2, 5))
	check(not b.set_order(arch, BE.Order.CARGAR), "los arqueros no cargan")
	var w = _unit(b, BE.Side.ATACANTE, BE.UnitType.INFANTERIA, Vector2i(6, 1))
	w.morale = 40
	check(b.withdraw(w), "replegarse")
	check(w.cell.x < 6 and w.morale == 50 and w.has_acted, "se repliega hacia atrás, +10 moral y gasta el turno")

# --- Clima y hora ---
func _weather_tests() -> void:
	var b = _duel_board()
	b.units.clear()
	var arch = _unit(b, BE.Side.ATACANTE, BE.UnitType.ARQUEROS, Vector2i(2, 3))
	var cav = _unit(b, BE.Side.ATACANTE, BE.UnitType.CABALLERIA, Vector2i(2, 5))
	var foe = _unit(b, BE.Side.DEFENSOR, BE.UnitType.INFANTERIA, Vector2i(5, 3))
	var clear: int = b.preview_attack(arch, foe).casualties
	var r: int = b.effective_attack_range(arch)
	var m: int = b.effective_move_range(cav)
	b.weather = BE.Weather.LLUVIA
	check(b.preview_attack(arch, foe).casualties < clear, "la lluvia debilita a los arqueros")
	b.weather = BE.Weather.NIEBLA
	check(b.effective_attack_range(arch) == r - 1, "la niebla quita alcance")
	b.weather = BE.Weather.NIEVE
	check(b.effective_move_range(cav) == m - 1, "la nieve frena a la caballería")
	b.weather = BE.Weather.DESPEJADO
	b.time_of_day = BE.TimeOfDay.NOCHE
	var far = _unit(b, BE.Side.DEFENSOR, BE.UnitType.INFANTERIA, Vector2i(11, 0))
	check(not b.is_visible_to(BE.Side.ATACANTE, far), "de noche no se ve lo lejano")
	check(b.is_visible_to(BE.Side.ATACANTE, foe), "de noche se ve lo cercano")
	check(not b.conditions_text().is_empty(), "texto de condiciones")
	var rolled := {}
	for i in 200:
		var bb = BM.new()
		bb.biome = i % 12
		bb.start_battle(40, 40, true, _knight("C1"), _knight("C2"), "X")
		rolled[bb.weather] = true
	check(rolled.size() >= 3, "el clima varía (%d tipos)" % rolled.size())

# --- Habilidades de mando ---
func _ability_tests() -> void:
	var gd = root.get_node("GameData")
	var cmd := _knight("Cmd")
	cmd.battle_skills.clear()
	for sk in gd.battle_skills:
		if sk.skill_name in ["Grito de Guerra", "Lluvia de Flechas"]:
			cmd.battle_skills.append(sk)
	var b = BM.new()
	b.random_conditions = false
	b.player_side = BE.Side.ATACANTE
	b.start_battle(80, 80, false, cmd, _knight("C2"), "X")
	var ids: Array = b.abilities_of(cmd)
	check("grito" in ids and "flechas" in ids, "habilidades desde las de batalla")
	var before: Array = b.active_units(BE.Side.ATACANTE).map(func(u): return u.morale)
	check(b.use_ability(cmd, "grito", BE.Side.ATACANTE), "usar Grito de guerra")
	var after: Array = b.active_units(BE.Side.ATACANTE).map(func(u): return u.morale)
	check(after[0] == mini(100, before[0] + BM.GRITO_MORALE), "Grito de guerra sube la moral")
	check(not b.use_ability(cmd, "flechas", BE.Side.ATACANTE), "una sola habilidad por personaje y batalla")
	# Muro de escudos: menos bajas hasta el siguiente turno propio.
	var cmd2 := _knight("Cmd2")
	cmd2.battle_skills.clear()
	for sk in gd.battle_skills:
		if sk.skill_name == "Muro de Escudos":
			cmd2.battle_skills.append(sk)
	var b2 = _duel_board()
	b2.defender_cmd = cmd2
	b2.units.clear()
	var mine = _unit(b2, BE.Side.DEFENSOR, BE.UnitType.INFANTERIA, Vector2i(5, 3))
	var foe = _unit(b2, BE.Side.ATACANTE, BE.UnitType.INFANTERIA, Vector2i(4, 3))
	var base: int = b2.preview_attack(foe, mine).casualties
	check(b2.use_ability(cmd2, "muro", BE.Side.DEFENSOR), "usar Muro de escudos")
	check(b2.preview_attack(foe, mine).casualties < base, "el muro reduce las bajas")
	b2._reset_side(BE.Side.DEFENSOR)
	check(b2.preview_attack(foe, mine).casualties == base, "el muro termina en el turno propio siguiente")
