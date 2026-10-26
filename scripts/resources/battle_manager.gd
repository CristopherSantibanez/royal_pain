class_name BattleManager
extends RefCounted

signal log_message(text: String)
signal state_updated
signal battle_ended(winner_side: int, report: Dictionary)
# Eventos puntuales para animaciones y sonido (no cambian la simulación).
signal unit_attacked(attacker: BattleUnit, target: BattleUnit, casualties: int, counter: int, ranged: bool)
signal unit_routed(unit: BattleUnit, annihilated: bool)

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
const GRITO_GUERRA_MORALE := 5
const CARGA_LETAL_FACTOR := 1.4
const CARGA_MIN_DISTANCE := 2         # con Carga Letal, la caballería que carga 2+ casillas no recibe respuesta
const TACTICA_DEFENSIVA_FACTOR := 1.3
const TACTICA_DEFENSIVA_WALL_MORALE := 5
const COMMANDER_DIVISOR := 200.0      # bonus del comandante: 1 + (Liderazgo + Estrategia) / este valor

# --- Compañeros al mando de pelotones (séquito del jugador o cortesanos del señor enemigo) ---
const COMPANION_DIVISOR := 100.0      # bonus del pelotón: (Combate + Liderazgo del compañero) / este valor
const COMPANION_MORALE_DIVISOR := 2   # moral inicial extra: Liderazgo del compañero / este valor
const FACTION_MORALE_PENALTY := 10    # los prestados por el señor no luchan con la misma entrega
const FACTION_DESERT_MORALE := 45     # si el pelotón cae por debajo de esta moral, el de facción se retira
const WOUND_CHANCE_ANNIHILATED := 0.6
const WOUND_CHANCE_ROUTED := 0.25
const COMPANION_WOUND_MONTHS := 2

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
var wounded_companions: Array[String] = []   # nombres de compañeros heridos en esta batalla

# --- Inicio ---

func start_battle(attacker_size: int, defender_size: int, walls: bool, a_cmd: Character, d_cmd: Character, place_name: String,
		player_companions: Array[Character] = [], enemy_companions: Array[Character] = []) -> void:
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
	wounded_companions.clear()
	_assign_companions(player_side, player_companions)
	_assign_companions(_other_side(player_side), enemy_companions)
	_assign_captains(BattleEnums.Side.ATACANTE)
	_assign_captains(BattleEnums.Side.DEFENSOR)
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
		start_morale += GRITO_GUERRA_MORALE
	# Táctica Defensiva: tras la muralla, los defensores se sienten más seguros.
	if side == BattleEnums.Side.DEFENSOR and has_walls and _has_skill(commander, SKILL_TACTICA_DEFENSIVA):
		start_morale += TACTICA_DEFENSIVA_WALL_MORALE
	start_morale += roundi(SkillEffects.fx(commander, "morale_start"))
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
	var r := u.move_range()
	if u.type == BattleEnums.UnitType.CABALLERIA:
		r += roundi(_unit_fx(u, "cav_move"))
	# Las tropas muy fatigadas avanzan más lento.
	if u.fatigue >= 70:
		return maxi(1, r - 1)
	return r

func effective_attack_range(u: BattleUnit) -> int:
	var r := u.attack_range()
	if u.type == BattleEnums.UnitType.ARQUEROS:
		r += roundi(_unit_fx(u, "arch_range"))
		if terrain_at(u.cell) in [BattleEnums.Terrain.COLINA, BattleEnums.Terrain.MURALLA]:
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
	u.last_move_distance = distance(u.cell, cell)
	u.cell = cell
	u.has_moved = true
	u.fatigue = mini(100, u.fatigue + _fatigue_gain(u, 8 if u.type == BattleEnums.UnitType.CABALLERIA else 5))
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

	# Respuesta cuerpo a cuerpo: el defensor devuelve parte del golpe si sigue en pie
	# (salvo ante una carga de caballería con Carga Letal).
	var counter := 0
	if _is_charge(attacker):
		text += " ¡La carga los arrolla sin darles tiempo a responder!"
	elif dist == 1 and target.is_active() and target.type != BattleEnums.UnitType.ARQUEROS:
		counter = int(_compute_casualties(target, attacker, dist, true) * _retaliation(target))
		if counter > 0:
			_apply_casualties(attacker, counter)
			text += " Responden causando %d bajas." % counter
	unit_attacked.emit(attacker, target, casualties, counter, dist > 1)

	attacker.has_acted = true
	attacker.has_moved = true
	attacker.fatigue = mini(100, attacker.fatigue + _fatigue_gain(attacker, 10))
	log_message.emit(text)

	_check_rout(target)
	_check_rout(attacker)
	_check_end()
	state_updated.emit()
	return true

# Vista previa sin azar de un ataque: bajas esperadas para el objetivo y la respuesta que sufriría el atacante.
func preview_attack(attacker: BattleUnit, target: BattleUnit) -> Dictionary:
	var dist := distance(attacker.cell, target.cell)
	var casualties := _compute_casualties(attacker, target, dist, false)
	var counter := 0
	if dist == 1 and casualties < target.soldiers and target.type != BattleEnums.UnitType.ARQUEROS and not _is_charge(attacker):
		counter = int(_compute_casualties(target, attacker, dist, false) * _retaliation(target))
	return {"casualties": casualties, "counter": counter}

func _is_charge(attacker: BattleUnit) -> bool:
	return attacker.type == BattleEnums.UnitType.CABALLERIA and attacker.last_move_distance >= CARGA_MIN_DISTANCE \
		and _has_skill(_commander(attacker.side), SKILL_CARGA_LETAL)

## Proporción de soldados perdidos por ambos bandos (0 al empezar), para la intensidad de la música.
func casualty_fraction() -> float:
	var initial: int = _initial_soldiers.get(BattleEnums.Side.ATACANTE, 0) + _initial_soldiers.get(BattleEnums.Side.DEFENSOR, 0)
	if initial <= 0:
		return 0.0
	var now := total_soldiers(BattleEnums.Side.ATACANTE) + total_soldiers(BattleEnums.Side.DEFENSOR)
	return 1.0 - float(now) / initial

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
		strength *= CARGA_LETAL_FACTOR
	strength *= 0.5 + attacker.morale / 200.0          # 0.5 .. 1.0
	strength *= 1.0 - attacker.fatigue / 250.0         # 1.0 .. 0.6
	var cmd := _commander(attacker.side)
	if cmd != null:
		strength *= 1.0 + (cmd.leadership + cmd.strategy) / COMMANDER_DIVISOR
	# Habilidades, rasgos y equipo del comandante y del compañero al mando del pelotón.
	strength *= maxf(0.3, 1.0 + _unit_fx(attacker, "unit_power") + _unit_fx(attacker, _type_power_key(attacker.type)))
	if attacker.companion != null:
		strength *= 1.0 + (attacker.companion.combat + attacker.companion.leadership) / COMPANION_DIVISOR

	var t := terrain_at(target.cell)
	var defense: float = _terrain_defense(t)
	if t in [BattleEnums.Terrain.COLINA, BattleEnums.Terrain.MURALLA] and _has_skill(_commander(target.side), SKILL_TACTICA_DEFENSIVA):
		defense *= TACTICA_DEFENSIVA_FACTOR
	if t != BattleEnums.Terrain.LLANO:
		defense *= 1.0 + _unit_fx(target, "terrain_def")
	if t == BattleEnums.Terrain.MURALLA:
		strength *= 1.0 + _unit_fx(attacker, "wall_assault")

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
	var loss := (loss_ratio * 60.0 + 5) * clampf(1.0 + _unit_fx(u, "morale_loss"), 0.2, 2.0)
	u.morale = maxi(0, u.morale - int(loss))
	# Un compañero prestado por el señor no arriesga la vida por un pelotón que se hunde.
	if u.companion != null and u.companion.has_meta("faction_companion") and u.morale < FACTION_DESERT_MORALE and u.soldiers > 0:
		log_message.emit("%s abandona el mando de su pelotón." % u.companion.full_name())
		u.companion = null

func _check_rout(u: BattleUnit) -> void:
	if u.routed:
		return
	if u.soldiers <= 0:
		u.routed = true
		log_message.emit("¡%s (%s) ha sido aniquilado!" % [BattleEnums.unit_type_name(u.type), _side_label(u.side)])
		unit_routed.emit(u, true)
		_wound_companion(u, WOUND_CHANCE_ANNIHILATED)
	elif u.morale < BattleUnit.ROUT_MORALE:
		u.routed = true
		log_message.emit("¡%s (%s) rompe filas y huye!" % [BattleEnums.unit_type_name(u.type), _side_label(u.side)])
		unit_routed.emit(u, false)
		_wound_companion(u, WOUND_CHANCE_ROUTED)
	else:
		return
	# Ver huir a los compañeros desmoraliza al resto del bando.
	for ally: BattleUnit in active_units(u.side):
		ally.morale = maxi(0, ally.morale - 5)

func _rest_side(side: int) -> void:
	for u: BattleUnit in active_units(side):
		if not u.has_moved and not u.has_acted:
			u.fatigue = maxi(0, u.fatigue - 15)
			u.morale = mini(100, u.morale + 3 + roundi(_unit_fx(u, "rally")))

func _reset_side(side: int) -> void:
	for u: BattleUnit in units:
		if u.side == side:
			u.reset_turn()

# --- IA (controla el bando que no es del jugador) ---

func _run_ai(side: int) -> void:
	# Primero disparan los arqueros (ablandan), después carga la caballería y por último la infantería.
	var order := active_units(side)
	order.sort_custom(func(a: BattleUnit, b: BattleUnit): return AI_ORDER[a.type] < AI_ORDER[b.type])
	for u: BattleUnit in order:
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
	score -= (_terrain_defense(terrain_at(cell)) - 1.0) * AI_TERRAIN_WEIGHT
	# Los arqueros no se dejan alcanzar por la infantería o la caballería enemigas.
	if u.type == BattleEnums.UnitType.ARQUEROS:
		for enemy: BattleUnit in active_units(_other_side(u.side)):
			if enemy.type != BattleEnums.UnitType.ARQUEROS and distance(cell, enemy.cell) <= enemy.move_range():
				score += AI_ARCHER_DANGER
	return score

func _ai_best_target(u: BattleUnit, targets: Array[BattleUnit]) -> BattleUnit:
	var best: BattleUnit = targets[0]
	var best_value := -1.0
	for t: BattleUnit in targets:
		# Prioriza el daño esperado, rematar pelotones debilitados (fuego concentrado) y evitar respuestas caras.
		var preview := preview_attack(u, t)
		var value := float(preview.casualties) + (100 - t.morale) * 0.15
		value += (1.0 - float(t.soldiers) / maxi(1, t.max_soldiers)) * AI_FOCUS_WEIGHT
		if preview.casualties >= t.soldiers:
			value += AI_FINISH_BONUS
		value -= preview.counter * 0.8
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
		"wounded_companions": wounded_companions.duplicate(),
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

# --- Efectos y compañeros ---

const AI_ORDER := {BattleEnums.UnitType.ARQUEROS: 0, BattleEnums.UnitType.CABALLERIA: 1, BattleEnums.UnitType.INFANTERIA: 2}
const AI_TERRAIN_WEIGHT := 3.0
const AI_ARCHER_DANGER := 3.0
const AI_FOCUS_WEIGHT := 6.0
const AI_FINISH_BONUS := 8.0

# Suma de un efecto del comandante del bando y del compañero al mando del pelotón.
func _unit_fx(u: BattleUnit, key: String) -> float:
	var value := SkillEffects.fx(_commander(u.side), key)
	if u.companion != null:
		value += SkillEffects.fx(u.companion, key)
	return value

func _type_power_key(t: int) -> String:
	match t:
		BattleEnums.UnitType.ARQUEROS: return "arch_power"
		BattleEnums.UnitType.CABALLERIA: return "cav_power"
	return "inf_power"

func _retaliation(u: BattleUnit) -> float:
	return RETALIATION_FACTOR * maxf(0.0, 1.0 + _unit_fx(u, "retaliation"))

func _fatigue_gain(u: BattleUnit, base: int) -> int:
	return maxi(1, roundi(base * clampf(1.0 + _unit_fx(u, "fatigue"), 0.2, 2.0)))

# Cada compañero dirige el pelotón que mejor le va: caballería al más combativo,
# arqueros al mejor estratega, infantería al resto. Sube la fuerza y la moral del pelotón.
func _assign_companions(side: int, companions: Array[Character]) -> void:
	var free: Array[BattleUnit] = []
	for u: BattleUnit in units:
		if u.side == side:
			free.append(u)
	var commander := _commander(side)
	for c: Character in companions:
		if c == null or free.is_empty() or c.is_wounded():
			continue
		var preferred := BattleEnums.UnitType.INFANTERIA
		if c.combat >= c.strategy + 2:
			preferred = BattleEnums.UnitType.CABALLERIA
		elif c.strategy >= c.combat + 2:
			preferred = BattleEnums.UnitType.ARQUEROS
		var unit: BattleUnit = free[0]
		for u: BattleUnit in free:
			if u.type == preferred:
				unit = u
				break
		free.erase(unit)
		unit.companion = c
		var morale_bonus := c.leadership / COMPANION_MORALE_DIVISOR + SkillEffects.companion_loyalty(commander)
		if c.has_meta("faction_companion"):
			morale_bonus -= FACTION_MORALE_PENALTY
		unit.morale = clampi(unit.morale + morale_bonus, 0, 100)
		log_message.emit("%s dirige un pelotón de %s (%s)." % [c.full_name(), BattleEnums.unit_type_name(unit.type).to_lower(), _side_label(side)])

# Cada pelotón tiene a alguien al mando: el comandante encabeza el mayor pelotón sin compañero
# (caballería si la hay) y el resto lo dirigen capitanes de tropa, con el retrato de su oficio.
func _assign_captains(side: int) -> void:
	var commander := _commander(side)
	var free: Array[BattleUnit] = []
	for u: BattleUnit in units:
		if u.side == side and u.companion == null:
			free.append(u)
	free.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
		return (a.type == BattleEnums.UnitType.CABALLERIA) and not (b.type == BattleEnums.UnitType.CABALLERIA) or a.soldiers > b.soldiers)
	for i in free.size():
		if i == 0 and commander != null:
			free[i].captain = commander
		else:
			free[i].captain = _make_captain(free[i].type)

func _make_captain(type: int) -> Character:
	var c := Character.new()
	var cavalry := type == BattleEnums.UnitType.CABALLERIA
	c.first_name = "Capitán de caballería" if cavalry else "Capitán de arqueros" if type == BattleEnums.UnitType.ARQUEROS else "Capitán de infantería"
	c.role = Character.Role.CABALLERO if cavalry else Character.Role.SOLDADO
	var portrait_path := "res://assets/portraits/roles/%s.png" % ("caballero" if cavalry else "soldado")
	if ResourceLoader.exists(portrait_path):
		c.portrait = load(portrait_path)
	return c

func companions_of(side: int) -> Array[Character]:
	var result: Array[Character] = []
	for u: BattleUnit in units:
		if u.side == side and u.companion != null:
			result.append(u.companion)
	return result

func _wound_companion(u: BattleUnit, chance: float) -> void:
	if u.companion == null or randf() >= chance:
		return
	u.companion.wound_months = maxi(u.companion.wound_months, COMPANION_WOUND_MONTHS)
	wounded_companions.append(u.companion.full_name())
	log_message.emit("%s cae herido en la refriega." % u.companion.full_name())

func _has_skill(cmd: Character, skill_name: String) -> bool:
	if cmd == null:
		return false
	for s: Skill in cmd.battle_skills:
		if s != null and s.skill_name == skill_name:
			return true
	return false
