class_name BattleManager
extends RefCounted

signal log_message(text: String)
signal state_updated
signal battle_ended(winner_side: int, report: Dictionary)

# --- Constantes de balance (ajustables sin tocar la lógica) ---
const GRID_W := 12
const GRID_H := 8
const MAX_TURNS := 12               # si se agota, el asedio fracasa y gana el defensor
const SOLDIERS_PER_UNIT := 20
const MAX_UNITS_PER_SIDE := 6
const WALL_COLUMNS := 2
const AI_ENGAGE_DISTANCE := 4       # el defensor amurallado solo sale si el enemigo está así de cerca
const BASE_MORALE := 70
const RETALIATION_FACTOR := 0.4

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# Habilidades de batalla con efecto mecánico (por nombre, ver GameData._load_battle_skills)
const SKILL_GRITO_GUERRA := "Grito de Guerra"
const SKILL_TACTICA_DEFENSIVA := "Táctica Defensiva"
const SKILL_CARGA_LETAL := "Carga Letal"

var terrain: Array = []              # terrain[x][y] -> BattleEnums.Terrain
var units: Array[BattleUnit] = []
var attacker_cmd: Character
var defender_cmd: Character
var player_side: int = BattleEnums.Side.ATACANTE
var has_walls: bool = true
var location_name: String = ""
var turn: int = 1
var is_over: bool = false

var _initial_soldiers := {}

# --- Inicio ---

func start_battle(attacker_size: int, defender_size: int, walls: bool, a_cmd: Character, d_cmd: Character, place_name: String) -> void:
	attacker_cmd = a_cmd
	defender_cmd = d_cmd
	has_walls = walls
	location_name = place_name
	turn = 1
	is_over = false
	units.clear()

	_generate_terrain()
	_create_units(BattleEnums.Side.ATACANTE, attacker_size)
	_create_units(BattleEnums.Side.DEFENSOR, defender_size)
	_initial_soldiers = {
		BattleEnums.Side.ATACANTE: total_soldiers(BattleEnums.Side.ATACANTE),
		BattleEnums.Side.DEFENSOR: total_soldiers(BattleEnums.Side.DEFENSOR),
	}

	log_message.emit("¡Comienza la batalla por %s! %d atacantes contra %d defensores." % [
		location_name, _initial_soldiers[BattleEnums.Side.ATACANTE], _initial_soldiers[BattleEnums.Side.DEFENSOR]])
	if _has_skill(attacker_cmd, SKILL_GRITO_GUERRA):
		log_message.emit("%s lanza un Grito de Guerra: la moral de sus tropas se eleva." % attacker_cmd.full_name())

	# Si un lado no tiene tropas, la batalla se decide de inmediato.
	_check_end()
	state_updated.emit()

func _generate_terrain() -> void:
	terrain.clear()
	for x in range(GRID_W):
		var column: Array = []
		for y in range(GRID_H):
			var t: int = BattleEnums.Terrain.LLANO
			if has_walls and x >= GRID_W - WALL_COLUMNS:
				t = BattleEnums.Terrain.MURALLA
			elif x >= 2 and x < GRID_W - WALL_COLUMNS - 1:
				# Las zonas de despliegue quedan despejadas; el centro tiene terreno variado.
				var r := randf()
				if r < 0.15:
					t = BattleEnums.Terrain.BOSQUE
				elif r < 0.27:
					t = BattleEnums.Terrain.COLINA
			column.append(t)
		terrain.append(column)

func _create_units(side: int, total: int) -> void:
	if total <= 0:
		return
	var count: int = clampi(ceili(total / float(SOLDIERS_PER_UNIT)), 1, MAX_UNITS_PER_SIDE)
	var types := _composition(count)
	var per_unit: int = total / count
	var remainder: int = total % count

	var commander := _commander(side)
	var start_morale: int = BASE_MORALE + (commander.leadership if commander != null else 5)
	if _has_skill(commander, SKILL_GRITO_GUERRA):
		start_morale += 15
	start_morale = clampi(start_morale, 0, 100)

	# Infantería y caballería en primera línea, arqueros detrás.
	var front_col: int = 1 if side == BattleEnums.Side.ATACANTE else GRID_W - 2
	var back_col: int = 0 if side == BattleEnums.Side.ATACANTE else GRID_W - 1
	var front: Array[BattleUnit] = []
	var back: Array[BattleUnit] = []

	for i in range(count):
		var u := BattleUnit.new()
		u.side = side
		u.type = types[i]
		u.soldiers = per_unit + (1 if i < remainder else 0)
		u.max_soldiers = u.soldiers
		u.morale = start_morale
		units.append(u)
		if u.type == BattleEnums.UnitType.ARQUEROS:
			back.append(u)
		else:
			front.append(u)

	_place_column(front, front_col)
	_place_column(back, back_col)

func _composition(count: int) -> Array[int]:
	var archers: int = roundi(count * 0.3)
	var cavalry: int = roundi(count * 0.2)
	var infantry: int = count - archers - cavalry
	if infantry < 1:
		infantry = 1
		if archers > 0:
			archers -= 1
		else:
			cavalry -= 1
	var result: Array[int] = []
	for i in range(infantry): result.append(BattleEnums.UnitType.INFANTERIA)
	for i in range(archers): result.append(BattleEnums.UnitType.ARQUEROS)
	for i in range(cavalry): result.append(BattleEnums.UnitType.CABALLERIA)
	return result

func _place_column(group: Array[BattleUnit], column: int) -> void:
	var start_y: int = (GRID_H - group.size()) / 2
	for i in range(group.size()):
		group[i].cell = Vector2i(column, start_y + i)

# --- Consultas ---

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID_W and cell.y < GRID_H

func terrain_at(cell: Vector2i) -> int:
	return terrain[cell.x][cell.y]

func unit_at(cell: Vector2i) -> BattleUnit:
	for u: BattleUnit in units:
		if u.is_active() and u.cell == cell:
			return u
	return null

func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func active_units(side: int) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for u: BattleUnit in units:
		if u.side == side and u.is_active():
			result.append(u)
	return result

func total_soldiers(side: int) -> int:
	# Incluye pelotones en huida: esos soldados se reagrupan después de la batalla.
	var sum := 0
	for u: BattleUnit in units:
		if u.side == side:
			sum += u.soldiers
	return sum

func is_player_unit(u: BattleUnit) -> bool:
	return u != null and u.side == player_side

func can_move(u: BattleUnit) -> bool:
	return not is_over and u.is_active() and not u.has_moved and not u.has_acted

func can_attack(u: BattleUnit) -> bool:
	return not is_over and u.is_active() and not u.has_acted

func move_cost(u: BattleUnit, cell: Vector2i) -> int:
	var cavalry := u.type == BattleEnums.UnitType.CABALLERIA
	match terrain_at(cell):
		BattleEnums.Terrain.BOSQUE: return 3 if cavalry else 2
		BattleEnums.Terrain.COLINA: return 2
		BattleEnums.Terrain.MURALLA: return 3 if cavalry else 2
	return 1

func effective_move_range(u: BattleUnit) -> int:
	# Las tropas muy fatigadas avanzan más lento.
	if u.fatigue >= 70:
		return maxi(1, u.move_range() - 1)
	return u.move_range()

func effective_attack_range(u: BattleUnit) -> int:
	var r := u.attack_range()
	if u.type == BattleEnums.UnitType.ARQUEROS and terrain_at(u.cell) in [BattleEnums.Terrain.COLINA, BattleEnums.Terrain.MURALLA]:
		r += 1   # la altura da alcance extra a los arqueros
	return r

func reachable_cells(u: BattleUnit) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not can_move(u):
		return result
	var budget := effective_move_range(u)
	var best := {u.cell: 0}
	var frontier: Array[Vector2i] = [u.cell]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for dir in DIRS:
			var next: Vector2i = current + dir
			if not in_bounds(next) or unit_at(next) != null:
				continue
			var cost: int = best[current] + move_cost(u, next)
			if cost > budget:
				continue
			if best.has(next) and best[next] <= cost:
				continue
			best[next] = cost
			frontier.append(next)
	for cell in best.keys():
		if cell != u.cell:
			result.append(cell)
	return result

func targets_in_range(u: BattleUnit) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	if not u.is_active():
		return result
	var r := effective_attack_range(u)
	for other: BattleUnit in units:
		if other.side != u.side and other.is_active() and distance(u.cell, other.cell) <= r:
			result.append(other)
	return result

# --- Acciones ---

func move_unit(u: BattleUnit, cell: Vector2i) -> bool:
	if not cell in reachable_cells(u):
		return false
	u.cell = cell
	u.has_moved = true
	u.fatigue = mini(100, u.fatigue + (8 if u.type == BattleEnums.UnitType.CABALLERIA else 5))
	state_updated.emit()
	return true

func attack(attacker: BattleUnit, target: BattleUnit) -> bool:
	if not can_attack(attacker) or not target in targets_in_range(attacker):
		return false

	var dist := distance(attacker.cell, target.cell)
	var casualties := _compute_casualties(attacker, target, dist, true)
	_apply_casualties(target, casualties)
	var text := "%s (%s) ataca a %s (%s): %d bajas." % [
		BattleEnums.unit_type_name(attacker.type), _side_label(attacker.side),
		BattleEnums.unit_type_name(target.type), _side_label(target.side), casualties]

	# Respuesta cuerpo a cuerpo: el defensor devuelve parte del golpe si sigue en pie.
	if dist == 1 and target.is_active() and target.type != BattleEnums.UnitType.ARQUEROS:
		var counter := int(_compute_casualties(target, attacker, dist, true) * RETALIATION_FACTOR)
		if counter > 0:
			_apply_casualties(attacker, counter)
			text += " Responden causando %d bajas." % counter

	attacker.has_acted = true
	attacker.has_moved = true
	attacker.fatigue = mini(100, attacker.fatigue + 10)
	log_message.emit(text)

	_check_rout(target)
	_check_rout(attacker)
	_check_end()
	state_updated.emit()
	return true

func end_player_turn() -> void:
	if is_over:
		return
	var ai_side := _other_side(player_side)

	_rest_side(player_side)
	_reset_side(ai_side)
	_run_ai(ai_side)
	if is_over:
		return
	_rest_side(ai_side)

	turn += 1
	if turn > MAX_TURNS:
		_end_battle(BattleEnums.Side.DEFENSOR, "El asedio se prolonga demasiado y los atacantes deben levantar el campamento.")
		return
	_reset_side(player_side)
	log_message.emit("— Turno %d de %d —" % [turn, MAX_TURNS])
	state_updated.emit()

func retreat() -> void:
	if is_over:
		return
	_end_battle(_other_side(player_side), "Tus tropas se retiran del campo de batalla.")

# --- Cálculo de combate ---

func _compute_casualties(attacker: BattleUnit, target: BattleUnit, dist: int, with_variance: bool) -> int:
	var strength: float = attacker.soldiers * _base_power(attacker.type)
	strength *= _matchup(attacker.type, target.type, dist)
	if attacker.type == BattleEnums.UnitType.CABALLERIA and _has_skill(_commander(attacker.side), SKILL_CARGA_LETAL):
		strength *= 1.25
	strength *= 0.5 + attacker.morale / 200.0          # 0.5 .. 1.0
	strength *= 1.0 - attacker.fatigue / 250.0         # 1.0 .. 0.6
	var cmd := _commander(attacker.side)
	if cmd != null:
		strength *= 1.0 + (cmd.leadership + cmd.strategy) / 100.0

	var t := terrain_at(target.cell)
	var defense: float = _terrain_defense(t)
	if t in [BattleEnums.Terrain.COLINA, BattleEnums.Terrain.MURALLA] and _has_skill(_commander(target.side), SKILL_TACTICA_DEFENSIVA):
		defense *= 1.2

	var value := strength / defense
	if with_variance:
		value *= randf_range(0.85, 1.15)
	return clampi(roundi(value), 1, maxi(1, target.soldiers))

func _base_power(t: int) -> float:
	match t:
		BattleEnums.UnitType.INFANTERIA: return 0.30
		BattleEnums.UnitType.ARQUEROS: return 0.25
		BattleEnums.UnitType.CABALLERIA: return 0.35
	return 0.3

func _matchup(a: int, d: int, dist: int) -> float:
	# Piedra-papel-tijera: caballería > arqueros, infantería > caballería, arqueros > infantería a distancia.
	if a == BattleEnums.UnitType.ARQUEROS and dist == 1:
		return 0.6
	if a == BattleEnums.UnitType.CABALLERIA and d == BattleEnums.UnitType.ARQUEROS:
		return 1.5
	if a == BattleEnums.UnitType.INFANTERIA and d == BattleEnums.UnitType.CABALLERIA:
		return 1.5
	if a == BattleEnums.UnitType.ARQUEROS and d == BattleEnums.UnitType.INFANTERIA:
		return 1.3
	if a == BattleEnums.UnitType.CABALLERIA and d == BattleEnums.UnitType.INFANTERIA:
		return 0.8
	return 1.0

func _terrain_defense(t: int) -> float:
	match t:
		BattleEnums.Terrain.BOSQUE: return 1.25
		BattleEnums.Terrain.COLINA: return 1.2
		BattleEnums.Terrain.MURALLA: return 1.5
	return 1.0

func _apply_casualties(u: BattleUnit, amount: int) -> void:
	u.soldiers = maxi(0, u.soldiers - amount)
	var loss_ratio: float = amount / float(maxi(1, u.max_soldiers))
	u.morale = maxi(0, u.morale - int(loss_ratio * 60.0) - 5)

func _check_rout(u: BattleUnit) -> void:
	if u.routed:
		return
	if u.soldiers <= 0:
		u.routed = true
		log_message.emit("¡%s (%s) ha sido aniquilado!" % [BattleEnums.unit_type_name(u.type), _side_label(u.side)])
	elif u.morale < BattleUnit.ROUT_MORALE:
		u.routed = true
		log_message.emit("¡%s (%s) rompe filas y huye!" % [BattleEnums.unit_type_name(u.type), _side_label(u.side)])
	else:
		return
	# Ver huir a los compañeros desmoraliza al resto del bando.
	for ally: BattleUnit in active_units(u.side):
		ally.morale = maxi(0, ally.morale - 5)

func _rest_side(side: int) -> void:
	for u: BattleUnit in active_units(side):
		if not u.has_moved and not u.has_acted:
			u.fatigue = maxi(0, u.fatigue - 15)
			u.morale = mini(100, u.morale + 3)

func _reset_side(side: int) -> void:
	for u: BattleUnit in units:
		if u.side == side:
			u.reset_turn()

# --- IA (controla el bando que no es del jugador) ---

func _run_ai(side: int) -> void:
	for u: BattleUnit in active_units(side):
		if is_over:
			return
		if not u.is_active():
			continue
		var targets := targets_in_range(u)
		if targets.is_empty():
			var nearest := _nearest_enemy(u)
			if nearest == null:
				continue
			var engaged := distance(u.cell, nearest.cell) <= AI_ENGAGE_DISTANCE
			# Tras la muralla, el defensor espera; la caballería sale a cazar igual.
			if engaged or not has_walls or u.type == BattleEnums.UnitType.CABALLERIA or side == BattleEnums.Side.ATACANTE:
				var cell := _ai_pick_cell(u, nearest)
				if cell != u.cell:
					move_unit(u, cell)
			targets = targets_in_range(u)
		if not targets.is_empty():
			attack(u, _ai_best_target(u, targets))

func _nearest_enemy(u: BattleUnit) -> BattleUnit:
	var best: BattleUnit = null
	var best_dist := 9999
	for other: BattleUnit in active_units(_other_side(u.side)):
		var d := distance(u.cell, other.cell)
		if d < best_dist:
			best_dist = d
			best = other
	return best

func _ai_pick_cell(u: BattleUnit, target: BattleUnit) -> Vector2i:
	var best_cell := u.cell
	var best_score := _ai_cell_score(u, u.cell, target)
	for cell in reachable_cells(u):
		var s := _ai_cell_score(u, cell, target)
		if s < best_score:
			best_score = s
			best_cell = cell
	return best_cell

func _ai_cell_score(u: BattleUnit, cell: Vector2i, target: BattleUnit) -> float:
	# Menor es mejor: quedar justo al alcance máximo del objetivo, preferiblemente en terreno defensivo.
	var d := distance(cell, target.cell)
	var r := u.attack_range()
	var score: float = float(r - d) if d <= r else 100.0 + d
	score -= (_terrain_defense(terrain_at(cell)) - 1.0) * 2.0
	return score

func _ai_best_target(u: BattleUnit, targets: Array[BattleUnit]) -> BattleUnit:
	var best: BattleUnit = targets[0]
	var best_value := -1.0
	for t: BattleUnit in targets:
		# Prioriza el daño esperado y rematar pelotones con poca moral.
		var value := float(_compute_casualties(u, t, distance(u.cell, t.cell), false)) + (100 - t.morale) * 0.1
		if value > best_value:
			best_value = value
			best = t
	return best

# --- Fin de la batalla ---

func _check_end() -> void:
	if is_over:
		return
	if active_units(BattleEnums.Side.DEFENSOR).is_empty():
		_end_battle(BattleEnums.Side.ATACANTE, "Los defensores de %s han caído." % location_name)
	elif active_units(BattleEnums.Side.ATACANTE).is_empty():
		_end_battle(BattleEnums.Side.DEFENSOR, "El ejército atacante ha sido derrotado.")

func _end_battle(winner_side: int, reason: String) -> void:
	is_over = true
	var report := {
		"winner_side": winner_side,
		"reason": reason,
		"turns": turn,
		"attacker_initial": _initial_soldiers.get(BattleEnums.Side.ATACANTE, 0),
		"defender_initial": _initial_soldiers.get(BattleEnums.Side.DEFENSOR, 0),
		"attacker_survivors": total_soldiers(BattleEnums.Side.ATACANTE),
		"defender_survivors": total_soldiers(BattleEnums.Side.DEFENSOR),
	}
	log_message.emit(reason)
	state_updated.emit()
	battle_ended.emit(winner_side, report)

# --- Utilidades ---

func _other_side(side: int) -> int:
	return BattleEnums.Side.DEFENSOR if side == BattleEnums.Side.ATACANTE else BattleEnums.Side.ATACANTE

func _commander(side: int) -> Character:
	return attacker_cmd if side == BattleEnums.Side.ATACANTE else defender_cmd

func _side_label(side: int) -> String:
	return "tuyo" if side == player_side else "enemigo"

func _has_skill(cmd: Character, skill_name: String) -> bool:
	if cmd == null:
		return false
	for s: Skill in cmd.battle_skills:
		if s != null and s.skill_name == skill_name:
			return true
	return false
