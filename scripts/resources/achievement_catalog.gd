extends RefCounted
# Libro de hazañas: logros que dan recompensas (no terminan la partida).
# Uso: const AchievementCatalog = preload("res://scripts/resources/achievement_catalog.gd")
#
# Cada hazaña: id, cat (categoría), title, desc, y o bien
#   stat + target  -> se cumple cuando contexto[stat] >= target (ver AchievementData.context()),
#   goal_role      -> la antigua meta de ese rol inicial (VictoryRules.evaluate); solo se ve si empezaste con él.
# reward: {gold, fame, honor, xp, points (de atributo), unique (pieza ★★★★)}.
# roles (opcional): solo visible si el rol inicial está en la lista. featured: roles que la destacan en Nueva Partida.

const CATEGORIES := ["Destino", "Armas", "Gobierno", "Linaje", "Fama", "Riqueza", "Viaje"]

const ACHIEVEMENTS := [
	# --- Destino: la antigua meta de cada rol inicial ---
	{"id": "goal_campesino", "cat": "Destino", "goal_role": Character.Role.CAMPESINO, "title": "De la nada",
		"reward": {"points": 2, "fame": 10, "gold": 150}},
	{"id": "goal_soldado", "cat": "Destino", "goal_role": Character.Role.SOLDADO, "title": "Campeón",
		"reward": {"points": 2, "fame": 10, "gold": 150}},
	{"id": "goal_caballero", "cat": "Destino", "goal_role": Character.Role.CABALLERO, "title": "Conquistador",
		"reward": {"points": 2, "fame": 10, "gold": 250}},
	{"id": "goal_nobleza_baja", "cat": "Destino", "goal_role": Character.Role.NOBLEZA_BAJA, "title": "Señor de la guerra",
		"reward": {"points": 2, "fame": 10, "gold": 400}},
	{"id": "goal_nobleza_alta", "cat": "Destino", "goal_role": Character.Role.NOBLEZA_ALTA, "title": "La Corona",
		"reward": {"points": 3, "fame": 15, "unique": true}},
	{"id": "goal_mercenario", "cat": "Destino", "goal_role": Character.Role.MERCENARIO, "title": "Espada de alquiler",
		"reward": {"points": 2, "fame": 10, "gold": 200}},
	{"id": "goal_capitan", "cat": "Destino", "goal_role": Character.Role.CAPITAN, "title": "La Compañía Libre",
		"reward": {"points": 2, "fame": 10, "gold": 300}},
	{"id": "goal_condotiero", "cat": "Destino", "goal_role": Character.Role.CONDOTIERO, "title": "Un señorío propio",
		"reward": {"points": 3, "fame": 10, "gold": 300}},

	# --- Armas ---
	{"id": "primera_sangre", "cat": "Armas", "stat": "duels_won", "target": 1, "title": "Primera sangre",
		"desc": "Gana tu primer duelo.", "reward": {"gold": 30, "xp": 20},
		"featured": [Character.Role.SOLDADO, Character.Role.MERCENARIO]},
	{"id": "espadachin", "cat": "Armas", "stat": "duels_won", "target": 5, "title": "Espadachín",
		"desc": "Gana 5 duelos.", "reward": {"fame": 3, "xp": 60}},
	{"id": "leyenda_armas", "cat": "Armas", "stat": "duels_won", "target": 25, "title": "Leyenda de las armas",
		"desc": "Gana 25 duelos.", "reward": {"points": 2, "fame": 10, "unique": true}},
	{"id": "veterano", "cat": "Armas", "stat": "level", "target": 5, "title": "Veterano",
		"desc": "Alcanza el nivel 5.", "reward": {"gold": 60}},
	{"id": "maestro", "cat": "Armas", "stat": "level", "target": 10, "title": "Maestro de armas",
		"desc": "Alcanza el nivel 10.", "reward": {"points": 1, "fame": 5}},

	# --- Gobierno ---
	{"id": "primer_castillo", "cat": "Gobierno", "stat": "owned_castles", "target": 1, "title": "Señor de un castillo",
		"desc": "Ten un castillo a tu nombre.", "reward": {"honor": 3, "fame": 5},
		"featured": [Character.Role.CABALLERO, Character.Role.CONDOTIERO]},
	{"id": "tres_castillos", "cat": "Gobierno", "stat": "owned_castles", "target": 3, "title": "Tres torres",
		"desc": "Ten 3 castillos a tu nombre.", "reward": {"points": 1, "gold": 200}},
	{"id": "constructor", "cat": "Gobierno", "stat": "building_level", "target": 1, "title": "Constructor",
		"desc": "Termina una obra en tu castillo.", "reward": {"gold": 80},
		"featured": [Character.Role.NOBLEZA_BAJA]},
	{"id": "gran_obra", "cat": "Gobierno", "stat": "building_level", "target": 3, "title": "La gran obra",
		"desc": "Lleva un edificio de tu castillo al nivel 3.", "reward": {"honor": 5, "fame": 5}},
	{"id": "duque", "cat": "Gobierno", "stat": "rank", "target": 5, "title": "Vuestra Gracia",
		"desc": "Alcanza el rango de Duque o superior.", "reward": {"fame": 10, "gold": 200},
		"featured": [Character.Role.NOBLEZA_ALTA]},
	{"id": "hegemonia", "cat": "Gobierno", "stat": "kingdom_share", "target": 50, "title": "Hegemonía",
		"desc": "Que tu reino controle la mitad de los castillos del mundo.", "reward": {"fame": 10, "gold": 300}},

	# --- Linaje ---
	{"id": "boda", "cat": "Linaje", "stat": "married", "target": 1, "title": "Unión de casas",
		"desc": "Cásate.", "reward": {"honor": 5}},
	{"id": "primogenito", "cat": "Linaje", "stat": "children", "target": 1, "title": "Primogénito",
		"desc": "Ten tu primer hijo.", "reward": {"gold": 50}},
	{"id": "familia_numerosa", "cat": "Linaje", "stat": "children", "target": 4, "title": "Casa numerosa",
		"desc": "Ten 4 hijos.", "reward": {"fame": 5, "honor": 3}},
	{"id": "mayoria_edad", "cat": "Linaje", "stat": "adult_children", "target": 1, "title": "Un heredero adulto",
		"desc": "Que uno de tus hijos llegue a la mayoría de edad.", "reward": {"xp": 50}},
	{"id": "dinastia", "cat": "Linaje", "stat": "generations", "target": 2, "title": "Dinastía",
		"desc": "Que un heredero de tu sangre tome el relevo de la casa.", "reward": {"points": 2, "fame": 5}},

	# --- Fama ---
	{"id": "conocido", "cat": "Fama", "stat": "fame", "target": 25, "title": "De boca en boca",
		"desc": "Alcanza 25 de fama.", "reward": {"gold": 50}},
	{"id": "celebre", "cat": "Fama", "stat": "fame", "target": 60, "title": "Célebre",
		"desc": "Alcanza 60 de fama.", "reward": {"points": 1}},
	{"id": "intachable", "cat": "Fama", "stat": "honor", "target": 90, "title": "Honor intachable",
		"desc": "Alcanza 90 de honor.", "reward": {"fame": 5}},
	{"id": "sequito", "cat": "Fama", "stat": "retinue", "target": 3, "title": "Leales hasta el fin",
		"desc": "Reúne un séquito de 3 personas.", "reward": {"honor": 3, "gold": 50}},

	# --- Riqueza ---
	{"id": "bolsa_llena", "cat": "Riqueza", "stat": "gold", "target": 500, "title": "Bolsa llena",
		"desc": "Reúne 500 de oro.", "reward": {"fame": 2}},
	{"id": "tesoro", "cat": "Riqueza", "stat": "gold", "target": 3000, "title": "Un tesoro digno de reyes",
		"desc": "Reúne 3000 de oro.", "reward": {"points": 1, "fame": 5}},
	{"id": "encargos", "cat": "Riqueza", "stat": "missions_done", "target": 5, "title": "Hombre de palabra",
		"desc": "Cumple 5 encargos o contratos.", "reward": {"gold": 100, "honor": 2},
		"featured": [Character.Role.CAMPESINO, Character.Role.MERCENARIO, Character.Role.CAPITAN]},
	{"id": "pieza_unica", "cat": "Riqueza", "stat": "unique_items", "target": 1, "title": "Reliquia legendaria",
		"desc": "Hazte con una pieza única (★★★★).", "reward": {"fame": 5}},

	# --- Viaje ---
	{"id": "viajero", "cat": "Viaje", "stat": "visited_castles", "target": 4, "title": "Viajero",
		"desc": "Visita 4 castillos distintos.", "reward": {"gold": 40, "xp": 30},
		"featured": [Character.Role.CAMPESINO]},
	{"id": "trotamundos", "cat": "Viaje", "stat": "visited_kingdoms", "target": 5, "title": "Trotamundos",
		"desc": "Visita castillos de 5 reinos distintos.", "reward": {"points": 1, "fame": 3}},
]

const ROLE_GOAL_IDS := {
	Character.Role.CAMPESINO: "goal_campesino", Character.Role.SOLDADO: "goal_soldado",
	Character.Role.CABALLERO: "goal_caballero", Character.Role.NOBLEZA_BAJA: "goal_nobleza_baja",
	Character.Role.NOBLEZA_ALTA: "goal_nobleza_alta", Character.Role.MERCENARIO: "goal_mercenario",
	Character.Role.CAPITAN: "goal_capitan", Character.Role.CONDOTIERO: "goal_condotiero",
}

static func find(id: String) -> Dictionary:
	for a: Dictionary in ACHIEVEMENTS:
		if a.id == id:
			return a
	return {}

## Hazañas que se ven en una partida empezada con ese rol (las de destino, solo la propia).
static func visible_for(starting_role: int) -> Array:
	return ACHIEVEMENTS.filter(func(a: Dictionary) -> bool:
		if a.has("goal_role"):
			return a.goal_role == starting_role
		return not a.has("roles") or starting_role in a.roles)

## La meta de destino de un rol, y las hazañas que ese rol destaca (para Nueva Partida).
static func featured_for(starting_role: int) -> Array:
	var out: Array = []
	var goal := find(ROLE_GOAL_IDS.get(starting_role, ""))
	if not goal.is_empty():
		out.append(goal)
	for a: Dictionary in ACHIEVEMENTS:
		if starting_role in a.get("featured", []):
			out.append(a)
	return out

static func title_of(a: Dictionary) -> String:
	return a.title

static func description_of(a: Dictionary) -> String:
	if a.has("goal_role"):
		return VictoryRules.goal_description(a.goal_role)
	return a.get("desc", "")

static func reward_text(reward: Dictionary) -> String:
	var parts: Array[String] = []
	if reward.get("gold", 0) > 0:
		parts.append("+%d oro" % reward.gold)
	if reward.get("fame", 0) > 0:
		parts.append("+%d fama" % reward.fame)
	if reward.get("honor", 0) > 0:
		parts.append("+%d honor" % reward.honor)
	if reward.get("xp", 0) > 0:
		parts.append("+%d exp." % reward.xp)
	if reward.get("points", 0) > 0:
		parts.append("+%d %s de atributo" % [reward.points, "punto" if reward.points == 1 else "puntos"])
	if reward.get("unique", false):
		parts.append("una pieza única")
	return ", ".join(parts)
