extends RefCounted
# Catálogo de sucesos del mundo (uso: const WorldEventCatalog = preload("res://scripts/resources/world_event_catalog.gd")).
# Lógica pura: datos y funciones estáticas, sin autoloads.
#
# WORLD_EVENTS: le pasan al mundo sin pedir decisión. scope "kingdom" (un reino al azar) o "all".
#   Efectos sobre castillos: garrison_factor, food, gold (sumas por castillo).
#   winter_only: solo de noviembre a febrero.
# PLAYER_EVENTS: sucesos globales que piden una decisión al jugador. Mismo formato que
#   EventCatalog (title, text, roles, options...) con "global": true. Efectos de EventCatalog.

const R := Character.Role
const WINTER := [11, 12, 1, 2]

const WORLD_EVENTS := [
	{"id": "peste", "scope": "kingdom", "garrison_factor": 0.85,
		"text": "La peste se ceba con %s: sus guarniciones pierden uno de cada siete hombres."},
	{"id": "buena_cosecha", "scope": "kingdom", "food": 80,
		"text": "Cosecha abundante en %s: los graneros rebosan."},
	{"id": "mala_cosecha", "scope": "kingdom", "food": -70,
		"text": "Las lluvias pudren la cosecha de %s. Se teme al hambre."},
	{"id": "bandidos", "scope": "all", "gold": -20,
		"text": "Una ola de bandidos asola los caminos: todos los castillos pierden oro en escoltas y saqueos."},
	{"id": "auge_comercial", "scope": "kingdom", "gold": 60,
		"text": "Las caravanas eligen las rutas de %s: su tesoro crece."},
	{"id": "invierno_crudo", "scope": "all", "food": -35, "winter_only": true,
		"text": "Un invierno cruel congela los caminos: todos los castillos consumen sus reservas."},
	{"id": "revuelta", "scope": "kingdom", "garrison_factor": 0.9,
		"text": "Una revuelta campesina en %s obliga a la guarnición a dispersarse."},
	{"id": "incendio", "scope": "kingdom", "gold": -60, "food": -30,
		"text": "Un incendio arrasa los almacenes de %s."},
	{"id": "mina", "scope": "kingdom", "gold": 90,
		"text": "Se descubre una veta de plata en las tierras de %s."},
	{"id": "cruzada_lejana", "scope": "all", "garrison_factor": 0.93,
		"text": "Muchos caballeros parten a una guerra santa lejana: las guarniciones de todos los reinos menguan."},
]

const PLAYER_EVENTS := [
	{
		"id": "g_cruzada", "global": true, "title": "Llamada a la cruzada",
		"text": "Los heraldos recorren los reinos: la Corona convoca a la nobleza a una guerra santa en tierras lejanas.",
		"roles": [R.CABALLERO, R.NOBLEZA_BAJA, R.NOBLEZA_ALTA, R.DUQUE, R.REGENTE],
		"options": [
			{"label": "Enviar oro para la causa (80)", "requires": {"gold": 80}, "effects": {"gold": -80, "honor": 6, "fame": 4},
				"result": "Tu donativo se pregona en todas las iglesias."},
			{"label": "Enviar a tus mejores hombres", "effects": {"garrison": -15, "honor": 8, "fame": 8},
				"result": "Quince de los tuyos parten hacia el este. Tu nombre viaja con ellos."},
			{"label": "Excusarte", "effects": {"honor": -4},
				"result": "Alegas asuntos urgentes. En la corte se murmura."},
		],
	},
	{
		"id": "g_peste", "global": true, "title": "La peste en los caminos",
		"text": "Una peste avanza de aldea en aldea. Una columna de refugiados llega a tus puertas.",
		"roles": [], "premise": {"governs": true},
		"options": [
			{"label": "Cerrar las puertas", "effects": {"castle_food": -30, "honor": -3},
				"result": "Los refugiados acampan bajo las murallas. Algunos mueren allí."},
			{"label": "Acoger a los refugiados", "chance": 0.5, "chance_stat": "strategy",
				"success": {"effects": {"honor": 6, "fame": 4}, "result": "Organizas una cuarentena ejemplar: nadie enferma dentro."},
				"failure": {"effects": {"garrison": -12, "health": -20, "honor": 2}, "result": "La enfermedad entra con ellos. Tú mismo caes con fiebre."}},
		],
	},
	{
		"id": "g_hambruna", "global": true, "title": "Hambruna",
		"text": "Tras una mala cosecha, el hambre se extiende entre los campesinos de la comarca.",
		"roles": [], "premise": {"governs": true},
		"options": [
			{"label": "Abrir los graneros", "effects": {"castle_food": -60, "honor": 6, "fame": 3},
				"result": "El pueblo come gracias a ti y no lo olvidará."},
			{"label": "Vender el grano caro", "effects": {"castle_gold": 70, "honor": -6},
				"result": "El tesoro engorda; las aldeas, no."},
		],
	},
	{
		"id": "g_torneo_real", "global": true, "title": "El gran torneo de la Corona",
		"text": "La Corona celebra un gran torneo en la capital. Acuden campeones de todos los reinos.",
		"roles": [R.SOLDADO, R.CABALLERO, R.NOBLEZA_BAJA, R.NOBLEZA_ALTA, R.INAFILIADO],
		"options": [
			{"label": "Participar (inscripción 30)", "requires": {"gold": 30, "healthy": true}, "chance": 0.4, "chance_stat": "combat",
				"success": {"effects": {"gold": 90, "fame": 12, "honor": 4}, "result": "¡Llegas a la final y te aclaman en la tribuna real!"},
				"failure": {"effects": {"gold": -30, "health": -30}, "result": "Caes en la segunda justa con un golpe en las costillas."}},
			{"label": "Asistir como espectador", "effects": {"honor": 1},
				"result": "Disfrutas de las justas y estrechas algunas manos."},
		],
	},
	{
		"id": "g_cometa", "global": true, "title": "Un cometa en el cielo",
		"text": "Un cometa de larga cola cruza el cielo durante semanas. Los augures discuten su significado.",
		"roles": [],
		"options": [
			{"label": "Dar limosna a la iglesia y rezar (20)", "requires": {"gold": 20}, "effects": {"gold": -20, "honor": 3},
				"result": "Los clérigos agradecen tu piedad."},
			{"label": "Proclamarlo un buen augurio para ti", "chance": 0.5, "chance_stat": "charisma",
				"success": {"effects": {"fame": 6}, "result": "La gente empieza a llamarte «el del cometa»."},
				"failure": {"effects": {"honor": -4}, "result": "Te acusan de soberbia y de tentar a la providencia."}},
		],
	},
	{
		"id": "g_mercenarios", "global": true, "title": "Lanzas en venta",
		"text": "Una compañía de mercenarios licenciada tras una guerra ofrece sus servicios.",
		"roles": [R.CABALLERO, R.NOBLEZA_BAJA, R.NOBLEZA_ALTA, R.DUQUE, R.REGENTE], "premise": {"governs": true},
		"options": [
			{"label": "Contratarlos (100 de oro)", "requires": {"gold": 100}, "effects": {"gold": -100, "garrison": 25},
				"result": "Veinticinco veteranos refuerzan tu guarnición."},
			{"label": "Engañarlos para que sigan su camino", "chance": 0.45, "chance_stat": "strategy",
				"success": {"effects": {"gold": 30}, "result": "Les vendes un mapa falso y víveres a precio de oro."},
				"failure": {"effects": {"garrison": -10, "honor": -3}, "result": "Descubren el engaño y saquean tus establos antes de irse."}},
			{"label": "Rechazarlos", "effects": {},
				"result": "Se marchan a ofrecer sus lanzas a otro señor."},
		],
	},
	{
		"id": "g_salteadores", "global": true, "title": "Salteadores en los caminos",
		"text": "Bandas de salteadores cortan los caminos de la comarca y ahogan el comercio.",
		"roles": [R.SOLDADO, R.CABALLERO, R.NOBLEZA_BAJA, R.NOBLEZA_ALTA],
		"options": [
			{"label": "Organizar batidas (escaramuza)", "requires": {"garrison": 25}, "effects": {},
				"result": "Sales con tus mejores hombres a limpiar los caminos.",
				"fight": {"type": "battle", "no_rival": true, "enemy_name": "Los salteadores", "enemy_ratio": 1.0,
					"foe": {"name": "Cabecilla de los salteadores", "role": Character.Role.SOLDADO},
					"win": {"effects": {"fame": 5, "honor": 3, "gold": 40}, "result": "Cuelgas a los cabecillas y recuperas parte del botín."},
					"lose": {"effects": {"honor": -2}, "result": "Te emboscan en un desfiladero y debes retirarte."}}},
			{"label": "Pagar escoltas para las caravanas (40)", "requires": {"gold": 40}, "effects": {"gold": -40, "honor": 1},
				"result": "El comercio sigue fluyendo, a un precio."},
		],
	},
	{
		"id": "g_embajada", "global": true, "title": "Una embajada de tierras lejanas",
		"text": "Llega una embajada de un reino de ultramar con regalos exóticos y mucha curiosidad.",
		"roles": [R.NOBLEZA_BAJA, R.NOBLEZA_ALTA, R.DUQUE, R.REGENTE], "premise": {"governs": true},
		"options": [
			{"label": "Agasajarla con un banquete (60)", "requires": {"gold": 60}, "effects": {"gold": -60, "fame": 6, "honor": 2},
				"result": "Los embajadores hablarán de tu hospitalidad en su tierra."},
			{"label": "Recibirla con cortesía y sin gastos", "effects": {"honor": 1},
				"result": "Una visita correcta, sin más."},
		],
	},
	{
		"id": "g_predicador", "global": true, "title": "Un predicador incendiario",
		"text": "Un fraile predica contra los abusos de los señores y las plazas se llenan para escucharlo.",
		"roles": [],
		"options": [
			{"label": "Darle limosna y escucharlo (20)", "requires": {"gold": 20}, "effects": {"gold": -20, "honor": 3, "fame": 2},
				"result": "El pueblo te tiene por alguien justo."},
			{"label": "Denunciarlo ante el párroco", "effects": {"honor": -3},
				"result": "El fraile se marcha maldiciendo tu nombre."},
		],
	},
	{
		"id": "g_invierno", "global": true, "title": "Se anuncia un invierno terrible",
		"text": "Los viejos aseguran que el invierno que viene será de los que no se olvidan.",
		"roles": [], "premise": {"governs": true},
		"options": [
			{"label": "Hacer acopio de víveres (40)", "requires": {"gold": 40}, "effects": {"gold": -40, "castle_food": 60},
				"result": "Llenas los graneros a tiempo."},
			{"label": "Confiar en la suerte", "effects": {"castle_food": -40},
				"result": "Los viejos tenían razón."},
		],
	},
	{
		"id": "g_hambre_aldea", "global": true, "title": "El hambre llega a tu mesa",
		"text": "La mala cosecha vacía los mercados de la comarca: el pan cuesta el triple y en los caminos se ven familias enteras pidiendo.",
		"roles": [], "premise": {"governs": false},
		"options": [
			{"label": "Comprar pan aunque sea caro (20)", "requires": {"gold": 20}, "effects": {"gold": -20},
				"result": "Pasas el mal trago con la bolsa más ligera."},
			{"label": "Compartir lo poco que tienes (10)", "requires": {"gold": 10}, "effects": {"gold": -10, "honor": 4},
				"result": "Los que comieron gracias a ti no lo olvidan."},
			{"label": "Apretarte el cinturón", "effects": {"health": -10},
				"result": "Un mes de hambre te deja flaco y débil."},
		],
	},
]

## Suceso del mundo al azar para este mes (o {} si ninguno encaja).
static func pick_world_event(month: int) -> Dictionary:
	var pool: Array = WORLD_EVENTS.filter(func(e): return not e.get("winter_only", false) or month in WINTER)
	return pool.pick_random().duplicate(true) if not pool.is_empty() else {}

## Suceso global con decisión, válido para el rol del jugador (o {}).
## ctx: situación del jugador (EventCatalog.situation); vacío = se calcula.
static func pick_player_event(character: Character, exclude_id: String = "", ctx: Dictionary = {}) -> Dictionary:
	if character == null:
		return {}
	if ctx.is_empty():
		ctx = EventCatalog.situation(character)
	var pool: Array = PLAYER_EVENTS.filter(func(e):
		return EventCatalog.fits_role(e, character) and EventCatalog.fits_situation(e, ctx) and e.id != exclude_id)
	return pool.pick_random().duplicate(true) if not pool.is_empty() else {}

## Aplica un suceso del mundo a los castillos. Devuelve el texto de la noticia.
static func apply_world_event(e: Dictionary, castles: Array[Castle], kingdom: int) -> String:
	for c: Castle in castles:
		if e.scope == "kingdom" and c.kingdom != kingdom:
			continue
		if e.has("garrison_factor"):
			c.garrison_size = maxi(1, int(c.garrison_size * e.garrison_factor))
		c.food = maxi(0, c.food + int(e.get("food", 0)))
		c.gold = maxi(0, c.gold + int(e.get("gold", 0)))
	var text: String = e.text
	return text % KingdomEnums.kingdom_name(kingdom) if text.contains("%s") else text
