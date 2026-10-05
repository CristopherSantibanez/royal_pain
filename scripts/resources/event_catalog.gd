class_name EventCatalog
# Catálogo de eventos mensuales (con decisión del jugador) y anuales (globales).
# Lógica pura: recibe personaje/castillos y devuelve resultados; no referencia autoloads.
#
# Formato de un evento mensual:
#   id, title, text, roles ([] = cualquiera), bias {Personality: peso}, options [...]
# Formato de una opción:
#   {label, requires?: {gold, castle_gold}, effects: {...}, result: "texto"}
#   o con azar: {label, chance, chance_stat?, success: {effects, result}, failure: {effects, result}}
# Efectos posibles: gold, honor, combat, leadership, charisma, strategy, defense,
#   castle_gold, castle_food, garrison, health (puede causar una herida grave)

const MONTHLY_EVENT_CHANCE := 0.6
const CHANCE_PER_STAT_POINT := 0.03   # cada punto de la stat por encima/debajo de 10 ajusta la probabilidad

const R := Character.Role
const P := Character.Personality

const EVENTS := [
	{
		"id": "recaudador", "title": "El recaudador abusivo",
		"text": "Un recaudador del señor exige un tributo extra, alegando deudas que nunca contrajiste.",
		"roles": [R.CAMPESINO, R.SOLDADO], "bias": {},
		"options": [
			{"label": "Pagar sin protestar", "effects": {"gold": -15},
				"result": "Pagas. El recaudador se marcha satisfecho."},
			{"label": "Negarte en público", "chance": 0.5, "chance_stat": "charisma",
				"success": {"effects": {"honor": 6}, "result": "Los vecinos te apoyan y el recaudador retrocede."},
				"failure": {"effects": {"gold": -30, "honor": -3}, "result": "Te multan por insolencia y pagas el doble."}},
		],
	},
	{
		"id": "bandidos", "title": "Bandidos en el camino",
		"text": "Una partida de bandidos asalta a unos viajeros cerca de las murallas.",
		"roles": [R.SOLDADO, R.CABALLERO, R.NOBLEZA_BAJA, R.NOBLEZA_ALTA], "bias": {P.ARROGANTE: 1.5},
		"options": [
			{"label": "Enfrentarlos", "chance": 0.55, "chance_stat": "combat",
				"success": {"effects": {"gold": 40, "honor": 6}, "result": "Los pones en fuga y recuperas parte del botín."},
				"failure": {"effects": {"honor": -4, "health": -40}, "result": "Te superan en número y debes retirarte malherido."}},
			{"label": "Avisar a la guardia y no intervenir", "effects": {"honor": -2},
				"result": "La guardia llega tarde. Algunos murmuran que no hiciste nada."},
		],
	},
	{
		"id": "peregrino", "title": "Un peregrino enfermo",
		"text": "Un peregrino exhausto pide refugio y algo de comida a tu puerta.",
		"roles": [], "bias": {P.PIADOSO: 2.0},
		"options": [
			{"label": "Acogerlo y cuidarlo", "requires": {"gold": 10}, "effects": {"gold": -10, "honor": 5},
				"result": "El peregrino se recupera y bendice tu nombre allá donde va."},
			{"label": "Cerrarle la puerta", "effects": {"honor": -2},
				"result": "El peregrino sigue su camino. Nadie lo olvida del todo."},
		],
	},
	{
		"id": "maestro_armas", "title": "Un maestro de armas errante",
		"text": "Un veterano de muchas campañas ofrece adiestrarte a cambio de una buena paga.",
		"roles": [R.SOLDADO, R.CABALLERO, R.NOBLEZA_BAJA], "bias": {P.ARROGANTE: 1.5, P.AMBICIOSO: 1.3},
		"options": [
			{"label": "Pagar el adiestramiento (40 de oro)", "requires": {"gold": 40}, "effects": {"gold": -40, "combat": 1},
				"result": "Semanas de práctica dura mejoran tu manejo de la espada."},
			{"label": "Rechazar la oferta", "effects": {},
				"result": "El veterano se encoge de hombros y sigue su camino."},
		],
	},
	{
		"id": "soborno", "title": "Una bolsa bajo la mesa",
		"text": "Un mercader te ofrece una generosa bolsa si favoreces sus negocios frente a la competencia.",
		"roles": [R.CABALLERO, R.NOBLEZA_BAJA, R.NOBLEZA_ALTA], "bias": {P.AMBICIOSO: 2.0, P.ASTUTO: 1.5, P.LEAL: 0.5},
		"options": [
			{"label": "Aceptar el soborno", "effects": {"gold": 80, "honor": -10},
				"result": "El oro es bueno; la reputación, no tanto."},
			{"label": "Rechazarlo con dignidad", "effects": {"honor": 5},
				"result": "El mercader se marcha ofendido, pero tu palabra vale más que su oro."},
		],
	},
	{
		"id": "insulto", "title": "Un insulto en la taberna",
		"text": "Un rival te humilla en público, poniendo en duda tu valor.",
		"roles": [R.SOLDADO, R.CABALLERO], "bias": {P.ARROGANTE: 2.0, P.PRUDENTE: 0.6},
		"options": [
			{"label": "Responder con firmeza", "chance": 0.6, "chance_stat": "charisma",
				"success": {"effects": {"honor": 5}, "result": "Tus palabras dejan en ridículo al provocador."},
				"failure": {"effects": {"honor": -3}, "result": "La taberna entera se ríe... de ti."}},
			{"label": "Ignorarlo y marcharte", "effects": {"honor": -2},
				"result": "Evitas la pelea, pero el rumor de tu cobardía corre."},
		],
	},
	{
		"id": "disputa", "title": "Disputa de tierras",
		"text": "Dos familias se disputan un campo. Una de ellas es rica y te ofrece un regalo si fallas a su favor.",
		"roles": [R.NOBLEZA_BAJA, R.NOBLEZA_ALTA, R.REGENTE], "bias": {P.LEAL: 1.3, P.ASTUTO: 1.3},
		"options": [
			{"label": "Juzgar con justicia", "effects": {"honor": 6},
				"result": "Tu fallo es justo y el pueblo lo celebra."},
			{"label": "Favorecer a la familia rica", "effects": {"gold": 50, "honor": -6},
				"result": "Recibes tu regalo. La otra familia jura no olvidarlo."},
		],
	},
	{
		"id": "incendio", "title": "Incendio en el granero",
		"text": "Un incendio arrasa parte de los graneros del castillo.",
		"roles": [R.CABALLERO, R.NOBLEZA_BAJA, R.NOBLEZA_ALTA, R.REGENTE], "bias": {},
		"options": [
			{"label": "Pagar la reconstrucción (60 de oro del castillo)", "requires": {"castle_gold": 60},
				"effects": {"castle_gold": -60, "honor": 2}, "result": "Los graneros se reconstruyen antes del invierno."},
			{"label": "Dejarlo como está", "effects": {"castle_food": -40},
				"result": "Se pierde buena parte de las reservas de comida."},
		],
	},
	{
		"id": "torneo_local", "title": "Torneo en la villa",
		"text": "Se celebra un pequeño torneo en una villa cercana. Hay premio para el vencedor.",
		"roles": [R.CABALLERO], "bias": {P.ARROGANTE: 1.5, P.AMBICIOSO: 1.5},
		"options": [
			{"label": "Inscribirte", "chance": 0.5, "chance_stat": "combat",
				"success": {"effects": {"gold": 60, "honor": 8}, "result": "¡Vences el torneo y te aclaman!"},
				"failure": {"effects": {"honor": -3, "health": -35}, "result": "Caes del caballo en la segunda justa y te rompes varias costillas."}},
			{"label": "No participar", "effects": {},
				"result": "Otros se llevan la gloria esta vez."},
		],
	},
	{
		"id": "reliquia", "title": "El vendedor de reliquias",
		"text": "Un viajero vende lo que asegura es un fragmento de la vara de un santo.",
		"roles": [], "bias": {P.PIADOSO: 2.0, P.ASTUTO: 0.6},
		"options": [
			{"label": "Comprarla (30 de oro)", "requires": {"gold": 30}, "chance": 0.35, "chance_stat": "strategy",
				"success": {"effects": {"gold": -30, "honor": 10}, "result": "La reliquia resulta auténtica y atrae a los fieles."},
				"failure": {"effects": {"gold": -30}, "result": "Era un trozo de leña vieja. Te han engañado."}},
			{"label": "Echar al charlatán", "effects": {},
				"result": "El viajero huye con sus baratijas."},
		],
	},
	{
		"id": "voluntarios", "title": "Jóvenes voluntarios",
		"text": "Un grupo de jóvenes de las aldeas se ofrece para servir en la guarnición.",
		"roles": [R.NOBLEZA_BAJA, R.NOBLEZA_ALTA, R.REGENTE], "bias": {},
		"options": [
			{"label": "Equiparlos (30 de oro del castillo)", "requires": {"castle_gold": 30},
				"effects": {"castle_gold": -30, "garrison": 15}, "result": "La guarnición crece con quince nuevos soldados."},
			{"label": "Enviarlos de vuelta al campo", "effects": {"castle_food": 10},
				"result": "Vuelven a sus campos; al menos habrá más cosecha."},
		],
	},
	{
		"id": "libro_estrategia", "title": "Un tratado de guerra",
		"text": "Llega a tus manos una copia de un antiguo tratado sobre el arte de la guerra.",
		"roles": [R.SOLDADO, R.CABALLERO, R.NOBLEZA_BAJA, R.NOBLEZA_ALTA, R.REGENTE], "bias": {P.PRUDENTE: 1.5},
		"options": [
			{"label": "Estudiarlo a fondo", "effects": {"strategy": 1},
				"result": "Sus lecciones afinan tu mente táctica."},
			{"label": "Venderlo a un monasterio", "effects": {"gold": 25},
				"result": "Los monjes pagan bien por el manuscrito."},
		],
	},
	{
		"id": "cosecha_parcela", "title": "Buena cosecha en tu parcela",
		"text": "Tu pequeña parcela ha dado más de lo esperado este mes.",
		"roles": [R.CAMPESINO], "bias": {},
		"options": [
			{"label": "Venderla en el mercado", "effects": {"gold": 20},
				"result": "Vuelves del mercado con la bolsa más pesada."},
			{"label": "Donarla a la iglesia", "effects": {"honor": 6},
				"result": "El párroco menciona tu generosidad en el sermón."},
		],
	},
	{
		"id": "conspiracion", "title": "Rumores de conspiración",
		"text": "Se susurra que algunos nobles traman contra ti en secreto.",
		"roles": [R.NOBLEZA_ALTA, R.REGENTE], "bias": {P.PRUDENTE: 1.5, P.ASTUTO: 1.5},
		"options": [
			{"label": "Pagar espías para investigar (50 de oro)", "requires": {"gold": 50}, "chance": 0.6, "chance_stat": "strategy",
				"success": {"effects": {"gold": -50, "leadership": 1, "honor": 4}, "result": "Desenmascaras a los conspiradores y tu autoridad se fortalece."},
				"failure": {"effects": {"gold": -50, "honor": -3}, "result": "Los espías no encuentran nada y los rumores crecen."}},
			{"label": "Ignorar las habladurías", "effects": {"honor": -2},
				"result": "Los rumores no cesan del todo."},
		],
	},
]

const ANNUAL_EVENTS := [
	{"text": "Año de cosecha abundante: los graneros de todos los reinos se llenan.", "castle_food": 60},
	{"text": "Mala cosecha en todo el continente: escasea la comida.", "castle_food": -50},
	{"text": "Una peste recorre los reinos: las guarniciones pierden un 15% de sus hombres.", "garrison_factor": 0.85},
	{"text": "Las rutas comerciales prosperan: el oro fluye hacia todos los castillos.", "castle_gold": 50},
	{"text": "Un año tranquilo, sin grandes sucesos.", },
]

# --- Eventos mensuales ---

static func roll_monthly(character: Character) -> Dictionary:
	if character == null or randf() >= MONTHLY_EVENT_CHANCE:
		return {}
	var pool: Array = []
	var weights: Array[float] = []
	var total := 0.0
	for e: Dictionary in EVENTS:
		var roles: Array = e.roles
		if not roles.is_empty() and not character.role in roles:
			continue
		var w: float = e.bias.get(character.personality, 1.0)
		pool.append(e)
		weights.append(w)
		total += w
	if pool.is_empty():
		return {}
	var pick := randf() * total
	for i in range(pool.size()):
		pick -= weights[i]
		if pick <= 0.0:
			return pool[i].duplicate(true)
	return pool[pool.size() - 1].duplicate(true)

static func can_choose(option: Dictionary, character: Character, castle: Castle) -> bool:
	var req: Dictionary = option.get("requires", {})
	if req.has("gold") and character.gold < req.gold:
		return false
	if req.has("castle_gold") and (castle == null or castle.gold < req.castle_gold):
		return false
	return true

static func requirement_text(option: Dictionary) -> String:
	var req: Dictionary = option.get("requires", {})
	var parts: Array[String] = []
	if req.has("gold"): parts.append("%d de oro propio" % req.gold)
	if req.has("castle_gold"): parts.append("%d de oro del castillo" % req.castle_gold)
	return "Requiere " + " y ".join(parts) if not parts.is_empty() else ""

static func success_chance(option: Dictionary, character: Character) -> float:
	var chance: float = option.get("chance", 1.0)
	var stat: String = option.get("chance_stat", "")
	if stat != "":
		chance += (int(character.get(stat)) - 10) * CHANCE_PER_STAT_POINT
	return clampf(chance, 0.05, 0.95)

# Aplica la opción elegida y devuelve el texto del resultado.
static func apply_option(event: Dictionary, index: int, character: Character, castle: Castle) -> String:
	var options: Array = event.get("options", [])
	if index < 0 or index >= options.size():
		return ""
	var option: Dictionary = options[index]
	var outcome: Dictionary = option
	if option.has("chance"):
		outcome = option.success if randf() < success_chance(option, character) else option.failure

	var text: String = outcome.get("result", "")
	var summary := _apply_effects(outcome.get("effects", {}), character, castle)
	if summary != "":
		text += "\n(" + summary + ")"
	if RoleProgression.check_dishonor_demotion(character):
		var old_role: int = character.role
		RoleProgression.apply_dishonor_demotion(character)
		text += "\nCaes en deshonra: de %s a %s." % [Character.role_name_for(old_role), character.role_name()]
	return text

static func _apply_effects(effects: Dictionary, character: Character, castle: Castle) -> String:
	var parts: Array[String] = []
	for key: String in effects.keys():
		var amount: int = effects[key]
		match key:
			"gold":
				character.gold = maxi(0, character.gold + amount)
				parts.append("Oro %+d" % amount)
			"honor":
				character.honor = clampi(character.honor + amount, 0, 100)
				parts.append("Honor %+d" % amount)
			"combat", "leadership", "charisma", "strategy", "defense":
				character.set(key, clampi(int(character.get(key)) + amount, 1, 20))
				parts.append("%s %+d" % [_stat_label(key), amount])
			"castle_gold":
				if castle != null:
					castle.gold = maxi(0, castle.gold + amount)
					parts.append("Oro del castillo %+d" % amount)
			"castle_food":
				if castle != null:
					castle.food = maxi(0, castle.food + amount)
					parts.append("Comida del castillo %+d" % amount)
			"health":
				character.current_health = clampi(character.current_health + amount, 0, character.max_health)
				parts.append("Vida %+d" % amount)
				var wound := character.after_fight_recovery()
				if wound != "":
					parts.append(wound)
			"garrison":
				if castle != null:
					castle.garrison_size = maxi(0, castle.garrison_size + amount)
					parts.append("Guarnición %+d" % amount)
	return ", ".join(parts)

static func _stat_label(key: String) -> String:
	match key:
		"combat": return "Combate"
		"leadership": return "Liderazgo"
		"charisma": return "Carisma"
		"strategy": return "Estrategia"
		"defense": return "Defensa"
	return key

# --- Eventos anuales (se aplican solos a todos los castillos) ---

static func roll_annual(castles: Array[Castle]) -> String:
	var e: Dictionary = ANNUAL_EVENTS.pick_random()
	for c: Castle in castles:
		c.food = maxi(0, c.food + int(e.get("castle_food", 0)))
		c.gold = maxi(0, c.gold + int(e.get("castle_gold", 0)))
		if e.has("garrison_factor"):
			c.garrison_size = int(c.garrison_size * e.garrison_factor)
	return e.text
