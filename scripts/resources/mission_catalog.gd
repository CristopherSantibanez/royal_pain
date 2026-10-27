extends RefCounted
# Catálogo de encargos según el rol (uso: const MissionCatalog = preload("res://scripts/resources/mission_catalog.gd")).
# Lógica pura: solo datos y funciones estáticas. El estado de cada encargo lo lleva MissionData.
#
# Formato de una plantilla:
#   id, title, text (puede usar {target} y {amount}), roles, months (plazo), weight
#   type: cómo se cumple
#     "pay"            entregar {amount} de oro desde el panel de encargos
#     "actions"        dedicar {amount} acciones (botón en el panel); step: efectos por cada acción
#     "risk"           un intento con probabilidad (chance, stat); fail_effects si sale mal
#     "win_duels"      ganar {amount} duelos de campaña antes del plazo
#     "exhibition"     batirse con un caballero de otro reino ({target}) y vencerlo
#     "garrison"       que la guarnición de tu castillo suba {amount} sobre la actual
#     "castle_gold"    que el tesoro del castillo suba {amount} sobre el actual
#     "affinity"       subir {amount} la afinidad con un señor ({target})
#     "alliance"       aliarte con un señor ({target})
#     "conquer"        conquistar un castillo con tus ejércitos
#   reward / penalty: efectos de EventCatalog (gold, honor, fame, garrison...) y "affinity" (con quien encarga)

const R := Character.Role

const TEMPLATES := [
	# --- Campesino ---
	{"id": "diezmo", "title": "El diezmo del señor", "roles": [R.CAMPESINO], "months": 3, "weight": 1.0,
		"type": "pay", "amount": 30,
		"text": "Tu señor exige el diezmo: entrega {amount} de oro antes de que acabe el plazo.",
		"reward": {"honor": 4, "affinity": 3}, "penalty": {"honor": -5, "affinity": -4}},
	{"id": "cosecha", "title": "La cosecha del señor", "roles": [R.CAMPESINO], "months": 3, "weight": 1.0,
		"type": "actions", "amount": 2, "step": {"gold": 5},
		"text": "Hay que recoger la cosecha de las tierras del señor: dedica {amount} acciones a la siega.",
		"reward": {"gold": 30, "honor": 3, "affinity": 3}, "penalty": {"honor": -3}},
	{"id": "lobos", "title": "Lobos en el redil", "roles": [R.CAMPESINO, R.SOLDADO], "months": 2, "weight": 0.8,
		"type": "risk", "chance": 0.5, "stat": "combat", "fail_effects": {"health": -20},
		"text": "Una manada de lobos diezma el ganado de la aldea. Alguien tiene que darles caza.",
		"reward": {"gold": 30, "fame": 3, "honor": 2}, "penalty": {"honor": -2}},
	# --- Soldado ---
	{"id": "patrulla", "title": "Patrullas en la frontera", "roles": [R.SOLDADO], "months": 3, "weight": 1.0,
		"type": "actions", "amount": 2, "step": {},
		"text": "El capitán necesita hombres en la frontera: cubre {amount} turnos de patrulla.",
		"reward": {"gold": 30, "honor": 4, "affinity": 3}, "penalty": {"honor": -4, "affinity": -3}},
	{"id": "bandidos", "title": "Una partida de bandidos", "roles": [R.SOLDADO, R.CABALLERO], "months": 3, "weight": 1.0,
		"type": "fight", "fail_effects": {"honor": -2},
		"fight": {"type": "battle", "no_rival": true, "enemy_name": "Los bandidos del bosque", "enemy_ratio": 0.9,
			"garrison_share": 0.2, "min_garrison": 20, "foe": {"name": "Cabecilla del bosque", "role": Character.Role.SOLDADO}},
		"text": "Unos bandidos se esconden en el bosque cercano. Sal con una partida de la guarnición y dales caza.",
		"reward": {"gold": 50, "fame": 5, "honor": 3, "affinity": 4}, "penalty": {"honor": -3}},
	{"id": "reclutas", "title": "Instruir a los reclutas", "roles": [R.SOLDADO, R.CABALLERO], "months": 4, "weight": 0.8,
		"type": "actions", "amount": 2, "step": {"garrison": 4},
		"text": "Llegan levas sin experiencia. Dedica {amount} acciones a instruirlas.",
		"reward": {"honor": 3, "affinity": 5}, "penalty": {"affinity": -3}},
	{"id": "duelo_honor", "title": "Defender el honor de la guarnición", "roles": [R.SOLDADO], "months": 4, "weight": 0.7,
		"type": "win_duels", "amount": 1,
		"text": "Los soldados de otra compañía se burlan de los vuestros. Gana {amount} duelo para callarlos.",
		"reward": {"fame": 5, "honor": 3}, "penalty": {"honor": -2}},
	# --- Caballero ---
	{"id": "exhibicion", "title": "Duelo de exhibición", "roles": [R.CABALLERO, R.NOBLEZA_BAJA], "months": 3, "weight": 1.3,
		"type": "exhibition",
		"text": "Tu señor ha concertado un duelo de exhibición contra {target}, caballero de otro reino. La honra de la casa está en juego.",
		"reward": {"fame": 10, "gold": 60, "honor": 4, "affinity": 5}, "penalty": {"honor": -4, "affinity": -5}},
	{"id": "escolta", "title": "Escoltar a un emisario", "roles": [R.CABALLERO], "months": 2, "weight": 1.0,
		"type": "risk", "chance": 0.55, "stat": "strategy", "fail_effects": {"health": -25, "honor": -3},
		"text": "Un emisario de tu señor debe cruzar tierras hostiles. Llévalo sano y salvo.",
		"reward": {"gold": 70, "affinity": 6, "fame": 3}, "penalty": {"affinity": -4}},
	{"id": "torneo_señor", "title": "Brillar en las justas", "roles": [R.CABALLERO], "months": 5, "weight": 0.8,
		"type": "win_duels", "amount": 2,
		"text": "Tu señor quiere que su casa brille: gana {amount} duelos antes del plazo.",
		"reward": {"fame": 8, "gold": 80, "affinity": 4}, "penalty": {"affinity": -3}},
	{"id": "levas", "title": "Reunir levas", "roles": [R.CABALLERO, R.NOBLEZA_BAJA], "months": 4, "weight": 1.0,
		"type": "garrison", "amount": 20,
		"text": "Se avecinan tiempos difíciles: aumenta la guarnición de tu castillo en {amount} soldados.",
		"reward": {"honor": 5, "affinity": 6, "fame": 2}, "penalty": {"affinity": -5}},
	# --- Nobleza ---
	{"id": "impuestos", "title": "Las arcas del reino", "roles": [R.NOBLEZA_BAJA, R.NOBLEZA_ALTA], "months": 4, "weight": 1.0,
		"type": "castle_gold", "amount": 150,
		"text": "La Corona necesita fondos: aumenta el tesoro de tu castillo en {amount} de oro.",
		"reward": {"honor": 4, "affinity": 8, "fame": 4}, "penalty": {"honor": -4, "affinity": -6}},
	{"id": "diplomacia", "title": "Una mano tendida", "roles": [R.NOBLEZA_BAJA, R.NOBLEZA_ALTA, R.REGENTE], "months": 5, "weight": 1.0,
		"type": "affinity", "amount": 20,
		"text": "Conviene acercarse a {target}: mejora vuestra relación en {amount} puntos.",
		"reward": {"fame": 6, "affinity": 8, "honor": 2}, "penalty": {"affinity": -4}},
	{"id": "alianza", "title": "Un pacto de armas", "roles": [R.NOBLEZA_ALTA, R.REGENTE], "months": 6, "weight": 0.8,
		"type": "alliance",
		"text": "Sella una alianza con {target} antes del plazo.",
		"reward": {"fame": 10, "honor": 5, "affinity": 6}, "penalty": {"affinity": -4, "honor": -2}},
	{"id": "conquista", "title": "Ensanchar el reino", "roles": [R.NOBLEZA_ALTA, R.REGENTE], "months": 8, "weight": 0.9,
		"type": "conquer",
		"text": "El reino debe crecer: conquista un castillo con tus ejércitos antes del plazo.",
		"reward": {"fame": 15, "honor": 8, "gold": 150, "affinity": 6}, "penalty": {"honor": -5, "affinity": -6}},
	{"id": "levas_mayores", "title": "Un ejército para la Corona", "roles": [R.NOBLEZA_ALTA, R.REGENTE], "months": 5, "weight": 0.8,
		"type": "garrison", "amount": 40,
		"text": "Aumenta la guarnición de tu castillo en {amount} soldados.",
		"reward": {"honor": 5, "fame": 5, "affinity": 6}, "penalty": {"affinity": -5}},
]

## Plantillas válidas para un rol, elegidas por peso. exclude: ids de encargos ya activos.
static func pick(role: int, exclude: Array) -> Dictionary:
	var pool: Array = TEMPLATES.filter(func(t): return role in t.roles and not t.id in exclude)
	if pool.is_empty():
		return {}
	var total := 0.0
	for t in pool:
		total += t.weight
	var roll := randf() * total
	for t in pool:
		roll -= t.weight
		if roll <= 0.0:
			return t.duplicate(true)
	return pool.back().duplicate(true)
