class_name SkillEffects
# Nombres de las habilidades con efecto mecánico y sus valores. Lógica pura (sin autoloads).
# Los nombres deben coincidir con el catálogo de GameData.

# --- Generales ---
const PASO_INVERNAL := "Paso Invernal"
const RECLUTADOR_NATO := "Reclutador Nato"
const ADMINISTRADOR := "Administrador"
const VIAJERO := "Viajero"

# --- Combate (duelo) ---
const DESARME_FULMINANTE := "Desarme Fulminante"
const PIEL_DE_HIERRO := "Piel de Hierro"
const GOLPE_CERTERO := "Golpe Certero"

# --- Valores (ajustables sin tocar la lógica) ---
const ADMINISTRADOR_BONUS := 1.25
const RECLUTADOR_COST_FACTOR := 0.67
const RECLUTADOR_GAIN_FACTOR := 1.5
const RECLUTADOR_MOBILIZE_BONUS := 0.1
const VIAJERO_MAX_HOPS := 2
const WINTER_MONTHS := [12, 1, 2]
const WINTER_MARCH_TURNS := 2
const PIEL_DE_HIERRO_FACTOR := 0.7
const CRIT_CHANCE := 0.05
const GOLPE_CERTERO_CRIT_CHANCE := 0.2
const CRIT_MULTIPLIER := 1.5

static func has(character: Character, skill_name: String) -> bool:
	if character == null:
		return false
	for list in [character.general_skills, character.combat_skills, character.battle_skills]:
		for s: Skill in list:
			if s != null and s.skill_name == skill_name:
				return true
	return false

static func is_winter(month: int) -> bool:
	return month in WINTER_MONTHS

# Turnos que tarda una marcha según el mes y el comandante.
static func march_turns(month: int, commander: Character) -> int:
	if is_winter(month) and not has(commander, PASO_INVERNAL):
		return WINTER_MARCH_TURNS
	return 1

static func income(amount: int, character: Character) -> int:
	return roundi(amount * ADMINISTRADOR_BONUS) if has(character, ADMINISTRADOR) else amount

static func max_march_hops(character: Character) -> int:
	return VIAJERO_MAX_HOPS if has(character, VIAJERO) else 1

# Castillos alcanzables en una marcha desde origin_id (vecinos directos, o a 2 saltos con Viajero).
static func march_destinations(origin_id: String, castles: Array[Castle], hops: int) -> Array[String]:
	var by_id := {}
	for c: Castle in castles:
		by_id[c.castle_id] = c
	var visited := {origin_id: true}
	var frontier: Array[String] = [origin_id]
	var result: Array[String] = []
	for i in range(hops):
		var next: Array[String] = []
		for id in frontier:
			var c: Castle = by_id.get(id)
			if c == null:
				continue
			for n in c.connected_castle_ids:
				if not visited.has(n):
					visited[n] = true
					next.append(n)
					result.append(n)
		frontier = next
	return result
