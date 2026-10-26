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
	return roundi(amount * income_multiplier(character))   # Administrador y demás efectos de ingresos

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

# --- Efectos del catálogo (ContentCatalog) ---
# Cada habilidad, ventaja, desventaja o pieza de equipo puede aportar efectos con nombre
# (ver la lista en content_catalog.gd). Se suman por nombre, así funcionan también las
# fichas guardadas antes de que existieran.

const ContentCatalog = preload("res://scripts/resources/content_catalog.gd")
static var _fx_by_name := {}

static func _fx_table() -> Dictionary:
	if _fx_by_name.is_empty():
		for list in [ContentCatalog.GENERAL_SKILLS, ContentCatalog.COMBAT_SKILLS, ContentCatalog.BATTLE_SKILLS,
				ContentCatalog.ADVANTAGES, ContentCatalog.DISADVANTAGES, ContentCatalog.EQUIPMENT]:
			for e: Dictionary in list:
				_fx_by_name[e.name] = e.get("fx", {})
	return _fx_by_name

## Suma de un efecto entre todo lo que tiene el personaje (0 si nada lo aporta).
static func fx(character: Character, key: String) -> float:
	if character == null:
		return 0.0
	var table := _fx_table()
	var total := 0.0
	for list in [character.general_skills, character.combat_skills, character.battle_skills]:
		for s: Skill in list:
			if s != null:
				total += table.get(s.skill_name, {}).get(key, 0.0)
	for list in [character.advantages, character.disadvantages]:
		for t: CharacterTrait in list:
			if t != null:
				total += table.get(t.trait_name, {}).get(key, 0.0)
	for e: Equipment in character.equipment:
		if e != null:
			total += table.get(e.equipment_name, {}).get(key, 0.0)
	return total

# --- Ayudas para el mundo, la economía y lo social (las usan otros sistemas) ---

## Multiplicador de oro ganado (impuestos, gobierno, trabajo, rentas). Incluye Administrador.
static func income_multiplier(character: Character) -> float:
	var m := 1.0 + fx(character, "income")
	if has(character, ADMINISTRADOR):
		m *= ADMINISTRADOR_BONUS
	return maxf(0.2, m)

## Multiplicador del coste de reclutar (milicia, mercenarios): menor es más barato.
static func recruit_cost_multiplier(character: Character) -> float:
	return clampf(1.0 + fx(character, "recruit"), 0.3, 2.0)

## Multiplicador del gasto de mantener la tropa (paga y comida) de tus castillos.
static func upkeep_multiplier(character: Character) -> float:
	return clampf(1.0 + fx(character, "upkeep"), 0.3, 2.0)

## Multiplicador del efecto de conversar y de los gestos íntimos.
static func social_multiplier(character: Character) -> float:
	return clampf(1.0 + fx(character, "social") + (character.charisma - 10) * 0.02 if character != null else 1.0, 0.3, 2.5)

## Multiplicador del efecto de los regalos.
static func gift_multiplier(character: Character) -> float:
	return clampf(1.0 + fx(character, "gift"), 0.3, 2.5)

## Suma a la probabilidad de éxito de las opciones de evento con riesgo (p. ej. +0.05).
static func event_luck(character: Character) -> float:
	return fx(character, "event_luck")

## Multiplicadores de fama y honor ganados (las pérdidas no se modifican).
static func fame_gain_multiplier(character: Character) -> float:
	return maxf(0.0, 1.0 + fx(character, "fame_gain"))

static func honor_gain_multiplier(character: Character) -> float:
	return maxf(0.0, 1.0 + fx(character, "honor_gain"))

## Vida extra recuperada cada mes, y meses menos de herida grave.
static func heal_bonus(character: Character) -> int:
	return roundi(fx(character, "heal"))

static func wound_reduction(character: Character) -> int:
	return roundi(fx(character, "wound_resist"))

## Castillos extra (saltos) de visión en el mapa.
static func vision_bonus(character: Character) -> int:
	return roundi(fx(character, "vision"))

## Moral extra de los compañeros que luchan a tu lado.
static func companion_loyalty(character: Character) -> int:
	return roundi(fx(character, "loyalty"))
