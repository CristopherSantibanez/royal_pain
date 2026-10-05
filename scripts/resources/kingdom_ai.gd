class_name KingdomAI
# Lógica pura de los reinos controlados por la IA: recibe datos y devuelve decisiones.
# No referencia autoloads (evita ciclos de dependencias entre GameManager/ArmyData/MapData).

# --- Constantes de balance (ajustables sin tocar la lógica) ---
const GRACE_MONTHS := 3               # meses iniciales sin ataques de la IA
const ATTACK_CHANCE := 0.2            # probabilidad mensual de que un castillo elegible ataque
const MIN_GARRISON_TO_ATTACK := 60
const MOBILIZE_FRACTION := 0.4
const MAX_ACTIVE_AI_ARMIES := 2
const ATTACK_CONFIDENCE := 0.7        # solo ataca si su ejército supera este % de la defensa estimada
const WALL_FACTOR := 1.5
const RECRUIT_PER_MONTH := 2
const GARRISON_CAP := 200
const LOSER_ATTACKER_SURVIVAL := 0.3

# Devuelve una lista de ataques: [{from_id, to_id, size}]
static func plan_attacks(castles: Array[Castle], armies: Array[Army], player_kingdom: int, months_elapsed: int, player_name: String) -> Array[Dictionary]:
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
		if c.garrison_size < MIN_GARRISON_TO_ATTACK or randf() >= ATTACK_CHANCE:
			continue

		var size: int = int(c.garrison_size * MOBILIZE_FRACTION)
		var best: Castle = null
		var best_defense := INF
		for neighbor_id in c.connected_castle_ids:
			var n: Castle = by_id.get(neighbor_id)
			if n == null or n.kingdom == c.kingdom or targeted.has(n.castle_id):
				continue
			var defense: float = n.garrison_size * WALL_FACTOR
			if defense < best_defense:
				best_defense = defense
				best = n
		if best == null or size < best_defense * ATTACK_CONFIDENCE:
			continue

		plans.append({"from_id": c.castle_id, "to_id": best.castle_id, "size": size})
		targeted[best.castle_id] = true
		active_ai += 1
	return plans

# Resolución rápida de una batalla sin tablero (IA contra IA, o defensa no jugada).
static func auto_resolve(attacker_size: int, defender_size: int) -> Dictionary:
	if defender_size <= 0:
		return {"attacker_won": true, "attacker_survivors": attacker_size, "defender_survivors": 0}
	var a_power: float = attacker_size * randf_range(0.8, 1.2)
	var d_power: float = defender_size * WALL_FACTOR * randf_range(0.8, 1.2)
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
		c.garrison_size = mini(GARRISON_CAP, c.garrison_size + RECRUIT_PER_MONTH) if c.garrison_size < GARRISON_CAP else c.garrison_size
