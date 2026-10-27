class_name KingdomAI
# Lógica pura de los reinos controlados por la IA: recibe datos y devuelve decisiones.
# No referencia autoloads (evita ciclos de dependencias entre GameManager/ArmyData/MapData).

# --- Constantes de balance (ajustables sin tocar la lógica) ---
const GRACE_MONTHS := 3               # meses iniciales sin ataques de la IA
const ATTACK_CHANCE := 0.2            # probabilidad mensual de que un castillo elegible ataque
const MIN_GARRISON_TO_ATTACK := 60
const MOBILIZE_FRACTION := 0.4
const MAX_ACTIVE_AI_ARMIES := 4
const ATTACK_CONFIDENCE := 0.7        # solo ataca si su ejército supera este % de la defensa estimada
const WALL_FACTOR := 1.5
const AUTO_WALL_FACTOR := 1.6   # al resolverse sola: un poco más que en la estimación de la IA, para igualar el asedio táctico (≈35–40% con 1,5× la guarnición)
const BuildingCatalog = preload("res://scripts/resources/building_catalog.gd")
const AI_BUILD_CHANCE := 0.15      # probabilidad mensual de que un señor de la IA ordene una obra
const AI_BUILD_RESERVE := 120      # oro que la IA deja siempre en las arcas para pagar a la tropa
const RECRUIT_PER_MONTH := 2
const GARRISON_CAP := 200
const LOSER_ATTACKER_SURVIVAL := 0.3
const HOSTILE_TARGET_FACTOR := 0.6    # un señor hostil ve los castillos del jugador como más débiles (los prefiere)
const RECONQUEST_TARGET_FACTOR := 0.5  # recuperar un castillo propio perdido es prioritario
const WAR_ATTACK_CHANCE := 0.4         # en guerra (o para reconquistar) la IA ataca más a menudo...
const WAR_CONFIDENCE := 0.45           # ...y se arriesga con menos ventaja
# Contra el jugador: un señor hostil o en guerra con él moviliza más tropas y se arriesga más;
# los demás (no aliados) también lo tantean, algo menos confiados que contra otro reino.
const PLAYER_ENEMY_MOBILIZE := 0.55
const PLAYER_ENEMY_CONFIDENCE := 0.45
const PLAYER_TARGET_CONFIDENCE := 0.55
const PLAYER_SIDE_UNPLAYED_FACTOR := 0.9   # una defensa que el jugador no dirige rinde algo menos
# Incursiones: aunque no tenga ventaja clara, un vecino no aliado a veces pone a prueba al jugador
# (prob. por castillo que ya decidió atacar este mes). Mantiene viva la defensa y castiga dejar el hogar vacío.
const PLAYER_RAID_CHANCE := 0.35
# Dificultad creciente: con los años los reinos se arman y se vuelven más agresivos.
const AGGRESSION_GROWTH_PER_YEAR := 0.25   # +25% de probabilidad de ataque por año de partida...
const MAX_AGGRESSION := 2.0                # ...hasta el doble
const PLAYER_ENEMY_RAID_CHANCE := 0.7

# --- Economía mensual de los castillos ---
const CASTLE_TAX_INCOME := 10          # oro que el castillo recauda solo cada mes
const UPKEEP_PER_SOLDIERS := 10        # 1 de oro al mes por cada 10 soldados (redondeado hacia arriba)
const FOOD_PER_SOLDIERS := 5           # 1 de comida al mes por cada 5 soldados
const FOOD_PRODUCTION := 20            # comida que producen las tierras del castillo cada mes...
const WINTER_FOOD_PRODUCTION := 8      # ...menos en invierno
const STARVATION_LOSS := 0.10          # sin comida, la guarnición pierde este % al mes
const UNPAID_DESERTION := 0.05         # sin oro para la paga, deserta este %

# Devuelve una lista de ataques: [{from_id, to_id, size}]
# Relaciones: los reinos aliados nunca atacan castillos del jugador; los hostiles los prefieren.
# Entre reinos de la IA solo hay ataques si están en guerra (wars, ver KingdomDiplomacy),
# salvo para reconquistar un castillo que era suyo. Sin "wars" (null) cualquiera puede atacar.
# player_war_kingdoms: reinos cuyos señores están en guerra declarada con el jugador.
static func plan_attacks(castles: Array[Castle], armies: Array[Army], player_kingdom: int, months_elapsed: int, player_name: String,
		player_castle_ids: Array = [], allied_kingdoms: Array = [], hostile_kingdoms: Array = [],
		wars = null, player_war_kingdoms: Array = []) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	if months_elapsed < GRACE_MONTHS:
		return plans

	var by_id := {}
	for c: Castle in castles:
		by_id[c.castle_id] = c

	var active_ai := 0
	var targeted := {}
	for a: Army in armies:
		if a.owner_name != player_name:
			active_ai += 1
		if a.destination_castle_id != "":
			targeted[a.destination_castle_id] = true
		if a.pending_battle:
			targeted[a.current_castle_id] = true

	var candidates := castles.duplicate()
	candidates.shuffle()
	for c: Castle in candidates:
		if active_ai >= MAX_ACTIVE_AI_ARMIES:
			break
		if c.kingdom == player_kingdom or c.owner_name == player_name:
			continue
		var player_enemy: bool = c.kingdom in player_war_kingdoms or c.kingdom in hostile_kingdoms
		var in_war: bool = (wars != null and _kingdom_at_war(wars, c.kingdom)) or c.kingdom in player_war_kingdoms
		var aggression: float = minf(1.0 + months_elapsed / 12.0 * AGGRESSION_GROWTH_PER_YEAR, MAX_AGGRESSION)
		if c.garrison_size < MIN_GARRISON_TO_ATTACK or randf() >= (WAR_ATTACK_CHANCE if in_war else ATTACK_CHANCE) * aggression:
			continue

		var base_size: int = int(c.garrison_size * MOBILIZE_FRACTION)
		var size := base_size
		var best: Castle = null
		var best_defense := INF
		var best_score := INF
		var best_confidence := ATTACK_CONFIDENCE
		var best_is_player := false
		for neighbor_id in c.connected_castle_ids:
			var n: Castle = by_id.get(neighbor_id)
			if n == null or n.kingdom == c.kingdom or targeted.has(n.castle_id):
				continue
			var is_player_castle := n.castle_id in player_castle_ids
			if is_player_castle and c.kingdom in allied_kingdoms:
				continue
			var reconquest := n.original_kingdom == c.kingdom
			# Las tierras sin señor (Isla Neutral) se pueden tomar sin declarar la guerra.
			var unclaimed := n.kingdom == KingdomEnums.Kingdom.NEUTRAL
			var needs_war := not is_player_castle and not reconquest and not unclaimed
			if needs_war and wars != null and not KingdomDiplomacy.at_war(wars, c.kingdom, n.kingdom):
				continue
			var defense: float = n.garrison_size * WALL_FACTOR * (1.0 + n.wall_bonus())
			var score := defense * (HOSTILE_TARGET_FACTOR if is_player_castle and c.kingdom in hostile_kingdoms else 1.0)
			if reconquest:
				score *= RECONQUEST_TARGET_FACTOR
			if score < best_score:
				best_score = score
				best_defense = defense
				best = n
				var hot := reconquest or (wars != null and KingdomDiplomacy.at_war(wars, c.kingdom, n.kingdom))
				best_confidence = WAR_CONFIDENCE if hot else ATTACK_CONFIDENCE
				size = base_size
				best_is_player = is_player_castle
				if is_player_castle:
					best_confidence = PLAYER_ENEMY_CONFIDENCE if player_enemy else PLAYER_TARGET_CONFIDENCE
					if player_enemy:
						size = int(c.garrison_size * PLAYER_ENEMY_MOBILIZE)
		if best == null:
			continue
		if size < best_defense * best_confidence:
			var raid := best_is_player and randf() < (PLAYER_ENEMY_RAID_CHANCE if player_enemy else PLAYER_RAID_CHANCE)
			if not raid:
				continue

		plans.append({"from_id": c.castle_id, "to_id": best.castle_id, "size": size})
		targeted[best.castle_id] = true
		active_ai += 1
	return plans

# Resolución rápida de una batalla sin tablero (IA contra IA, o defensa no jugada).
# defender_factor < 1 cuando el defensor es el jugador y no dirige la batalla.
static func auto_resolve(attacker_size: int, defender_size: int, defender_factor: float = 1.0, attacker_factor: float = 1.0) -> Dictionary:
	if defender_size <= 0:
		return {"attacker_won": true, "attacker_survivors": attacker_size, "defender_survivors": 0}
	var a_power: float = attacker_size * attacker_factor * randf_range(0.8, 1.2)
	var d_power: float = defender_size * AUTO_WALL_FACTOR * defender_factor * randf_range(0.8, 1.2)
	if a_power > d_power:
		return {
			"attacker_won": true,
			"attacker_survivors": maxi(1, int(attacker_size * (1.0 - 0.6 * d_power / a_power))),
			"defender_survivors": 0,
		}
	return {
		"attacker_won": false,
		"attacker_survivors": int(attacker_size * LOSER_ATTACKER_SURVIVAL),
		"defender_survivors": maxi(1, int(defender_size * (1.0 - 0.6 * a_power / d_power))),
	}

static func recruit(castles: Array[Castle]) -> void:
	for c: Castle in castles:
		var gain := RECRUIT_PER_MONTH + int(c.building_value("cuartel", "recruits"))   # el Cuartel acelera el reclutamiento
		c.garrison_size = mini(GARRISON_CAP, c.garrison_size + gain) if c.garrison_size < GARRISON_CAP else c.garrison_size

# Paga, comida y recaudación de cada castillo. Devuelve los castillos que sufrieron hambre o
# deserciones este mes: [{castle, lost, reason}] (para las noticias).
# player_castle_ids / player_upkeep: los castillos del jugador pagan su tropa con el multiplicador
# de sus rasgos y habilidades (ver SkillEffects.upkeep_multiplier).
static func castle_economy(castles: Array[Castle], winter: bool, player_castle_ids: Array = [],
		player_upkeep: float = 1.0) -> Array[Dictionary]:
	var troubles: Array[Dictionary] = []
	for c: Castle in castles:
		c.gold += CASTLE_TAX_INCOME + int(c.building_value("mercado", "income"))   # el Mercado recauda más
		var factor := player_upkeep if c.castle_id in player_castle_ids else 1.0
		var upkeep: int = ceili(c.garrison_size / float(UPKEEP_PER_SOLDIERS) * factor)
		var unpaid := upkeep > c.gold
		c.gold = maxi(0, c.gold - upkeep)
		c.food = maxi(0, c.food + (WINTER_FOOD_PRODUCTION if winter else FOOD_PRODUCTION) - c.garrison_size / FOOD_PER_SOLDIERS)
		var loss := 0.0
		var reason := ""
		if c.food <= 0:
			loss = STARVATION_LOSS
			reason = "hambre"
		elif unpaid:
			loss = UNPAID_DESERTION
			reason = "falta de paga"
		if loss > 0.0 and c.garrison_size > 0:
			var lost := maxi(1, int(c.garrison_size * loss))
			c.garrison_size -= lost
			troubles.append({"castle": c, "lost": lost, "reason": reason})
	return troubles

# Los señores de la IA ordenan obras cuando les sobra oro (una a la vez, como el jugador).
# Devuelve los castillos que empezaron una obra este mes.
static func plan_constructions(castles: Array[Castle], skip_castle_ids: Array = []) -> Array[Castle]:
	var started: Array[Castle] = []
	for c: Castle in castles:
		if c.is_building() or c.castle_id in skip_castle_ids or c.kingdom == KingdomEnums.Kingdom.NEUTRAL:
			continue
		if randf() > AI_BUILD_CHANCE:
			continue
		# Prefiere murallas si linda con enemigos; si no, lo más barato que pueda pagar con holgura.
		var options: Array = []
		for id: String in BuildingCatalog.ORDER:
			var next := BuildingCatalog.level_data(id, c.building_level(id) + 1)
			if not next.is_empty() and c.gold >= int(next.cost) + AI_BUILD_RESERVE:
				options.append({"id": id, "cost": int(next.cost) - (100 if id == "murallas" else 0)})
		if options.is_empty():
			continue
		options.sort_custom(func(a, b): return a.cost < b.cost)
		c.start_construction(options[0].id)
		started.append(c)
	return started

static func _kingdom_at_war(wars: Dictionary, kingdom: int) -> bool:
	for key: String in wars.keys():
		var parts := key.split("|")
		if int(parts[0]) == kingdom or int(parts[1]) == kingdom:
			return true
	return false
