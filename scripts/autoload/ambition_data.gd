extends Node
# Autoload — ambiciones de los PNJ (IA de utilidad, ver AmbitionCatalog).
# Cada PNJ seguido persigue una ambición (poder, amor, venganza, riqueza y fe) que madura mes a mes.
# Al madurar: o te implica (complot u oferta como evento con decisión: unirte, delatar, aprovecharte…)
# o se resuelve entre PNJ y lo ves en la crónica.

const AmbitionCatalog = preload("res://scripts/resources/ambition_catalog.gd")

signal ambitions_changed

# --- Quién persigue ambiciones ---
const MAX_TRACKED := 28                 # PNJ con ambición activa a la vez
const COOLDOWN_MONTHS := [4, 10]        # tras resolver una ambición, descanso antes de la siguiente
const UTILITY_NOISE := 0.2              # ±20% de azar sobre la nota: dos PNJ iguales no piensan igual
const MIN_UTILITY := 0.15               # por debajo, el PNJ no persigue nada este mes

# --- Ritmo de complots que te implican ---
const PLOT_MIN_GAP_MONTHS := 2          # meses mínimos entre dos complots/ofertas
const PLOT_PRESENT_CHANCE := 0.5        # prob. de presentarlo en cuanto madura (si no hay espera)
const PLOT_HOLD_MONTHS := 3             # meses que espera su turno antes de resolverse sin ti
const INVOLVE_CHANCE := {               # prob. de que una ambición sin destinatario fijo te busque a ti
	"usurpar": 0.6, "casar_hijos": 0.5, "ascender": 0.6, "rivalidad": 0.35,
	"enriquecerse": 0.3, "fe": 0.3, "torneo": 0.45,
}

# --- Noticias entre PNJ ---
const NPC_NEWS_PER_YEAR := 5            # desenlaces entre PNJ que llegan a la crónica cada año

# --- Umbrales y cantidades ---
const REVENGE_GRUDGE := 40              # rencor desde el que alguien quiere vengarse de ti
const LOVE_PROPOSAL_AFFECTION := 45
const RISE_MIN_AFFECTION := 30
const RIVAL_ALLY_MIN := 30              # intimidad o afinidad para pedirte ayuda contra un rival
const SHAME_HONOR_DROP := 8             # bajada de honor en un mes que deja un secreto
const SECRET_MONTHS := 24               # meses que un secreto sirve para chantajear
const USURP_BASE_CHANCE := 0.35
const USURP_STRATEGY_STEP := 0.02
const USURP_JOIN_BONUS := 0.25          # tu ayuda en la conjura
const USURP_EXECUTE_CHANCE := 0.5       # conjura fallida: el cabecilla acaba en el cadalso
const ASSASSINATION_CHANCE := 0.06      # rivalidad entre PNJ que acaba en asesinato
const ASSASSIN_ATTEMPT_CHANCE := 0.25   # un némesis cruel intenta matarte en vez de humillarte
const HOARD_GOLD := [60, 150]
const DOWRY_GOLD := 80
const INVEST_GOLD := 60
const INVEST_RETURN := 1.7
const INVEST_SUCCESS := 0.65
const INVEST_MONTHS := [3, 6]
const DONATION_GOLD := 40
const PILGRIM_GOLD := 20
const BLACKMAIL_GOLD := 70
const PROTECTION_GOLD := 30
const BRIBE_PEACE_GOLD := 40
const SABOTAGE_GOLD := 60
const MAX_CHAPEL_LEVEL := 3

var ambitions: Dictionary = {}          # nombre -> {id, kind, progress, rate, target, held}
var cooldown: Dictionary = {}           # nombre -> mes de partida a partir del cual elige otra
var married_npcs: Dictionary = {}       # cortesanos casados -> cónyuge (los señores, en WorldEvents)
var investments: Array = []             # [{due, amount, partner}]
var secrets: Array = []                 # [{month, text}] bajezas del jugador que alguien puede usar
var last_plot_month := -100
var plot_owner := ""                    # quién tiene su complot en la cola (uno a la vez)
var news_year := 0
var news_count := 0
var last_honor := -1
var stats := {"plots": 0, "npc_news": 0, "fizzled": 0}   # para simulaciones

func _ready() -> void:
	GameManager.game_started.connect(func(_c: Character): reset())
	GameManager.turn_advanced.connect(_on_month_passed)
	GameManager.event_option_chosen.connect(_on_option_chosen)

func reset() -> void:
	ambitions.clear()
	cooldown.clear()
	married_npcs.clear()
	investments.clear()
	secrets.clear()
	last_plot_month = -100
	plot_owner = ""
	news_year = 0
	news_count = 0
	last_honor = -1
	stats = {"plots": 0, "npc_news": 0, "fizzled": 0}

# --- Consultas ---

## Ambición activa de un PNJ ("" si ninguna).
func ambition_of(person_name: String) -> String:
	return str(ambitions.get(person_name, {}).get("id", ""))

## Texto corto para fichas y tooltips: «Ambición: Casarse (Amor y familia)».
func ambition_text(person_name: String) -> String:
	var id := ambition_of(person_name)
	if id.is_empty():
		return ""
	return "Ambición: %s (%s)" % [AmbitionCatalog.title_of(id), AmbitionCatalog.KIND_NAMES.get(AmbitionCatalog.kind_of(id), "")]

# --- Paso del mes ---

func _on_month_passed(_month: int, year: int) -> void:
	if not GameManager.is_game_active or GameManager.player_character == null:
		return
	if year != news_year:
		news_year = year
		news_count = 0
	var now := GameManager.months_elapsed()
	_note_shame(now)
	_pay_investments(now)
	_prune()
	_assign(now)
	for person_name: String in ambitions.keys():
		var a: Dictionary = ambitions[person_name]
		if a.progress < 1.0:
			a.progress += a.rate
			continue
		_mature(person_name, a, now)
	ambitions_changed.emit()

## Quien murió, cayó preso o dejó de existir deja de conspirar.
func _prune() -> void:
	for person_name: String in ambitions.keys():
		var r := RelationsData.get_relation(person_name)
		if r == null or r.character == null or CaptureData.is_prisoner(person_name) or CaptureData.is_serf(person_name):
			ambitions.erase(person_name)
			if plot_owner == person_name:
				plot_owner = ""

## Rellena hasta MAX_TRACKED con los PNJ más relevantes para ti y les da una ambición.
func _assign(now: int) -> void:
	if ambitions.size() >= MAX_TRACKED:
		return
	var candidates: Array = []
	for r: Relationship in RelationsData.relations:
		if r.character == null or ambitions.has(r.person_name) or int(cooldown.get(r.person_name, -1)) > now:
			continue
		if r.kind == Relationship.Kind.PUEBLO or CaptureData.is_prisoner(r.person_name) or CaptureData.is_serf(r.person_name):
			continue
		candidates.append([_relevance(r), r])
	candidates.sort_custom(func(a, b): return a[0] > b[0])
	for entry in candidates:
		if ambitions.size() >= MAX_TRACKED:
			break
		var r: Relationship = entry[1]
		var choice := choose(r)
		if choice.is_empty():
			cooldown[r.person_name] = now + COOLDOWN_MONTHS[0]
			continue
		var months: Array = AmbitionCatalog.months_range(choice.id)
		ambitions[r.person_name] = {"id": choice.id, "kind": AmbitionCatalog.kind_of(choice.id),
			"progress": 0.0, "rate": 1.0 / randi_range(int(months[0]), int(months[1])),
			"target": choice.get("target", ""), "held": 0}

## Cuánto le importa al jugador lo que haga este PNJ (para elegir a quién seguir).
func _relevance(r: Relationship) -> float:
	var score := randf() * 0.5
	match r.kind:
		Relationship.Kind.SENOR: score += 2.0 + (1.0 if r.person_name == RelationsData.liege_name else 0.0)
		Relationship.Kind.CONYUGE: score += 3.0
		Relationship.Kind.RIVAL_DUELO: score += 1.5
	if r.person_name in RelationsData.retinue:
		score += 2.0
	score += absf(r.grudge) / 40.0 + r.affection / 50.0 + absf(r.affinity) / 60.0
	if r.kingdom == RelationsData.zone_kingdom():
		score += 0.5
	return score

# --- IA de utilidad ---

## Puntúa todas las ambiciones posibles para este PNJ y devuelve {id, target?} con la mejor (o {}).
func choose(r: Relationship) -> Dictionary:
	var best := {}
	var best_score := MIN_UTILITY
	for option: Dictionary in score_all(r):
		var s: float = option.score * randf_range(1.0 - UTILITY_NOISE, 1.0 + UTILITY_NOISE)
		if s > best_score:
			best_score = s
			best = option
	return best

## Todas las ambiciones con su nota (sin azar): [{id, score, target?}].
func score_all(r: Relationship) -> Array[Dictionary]:
	var c := r.character
	var p := c.personality
	var is_lord := r.kind == Relationship.Kind.SENOR and not RelationsData.castles_of(r.person_name).is_empty()
	var out: Array[Dictionary] = []
	var power := AmbitionCatalog.drive(p, AmbitionCatalog.KIND_POWER)
	var love := AmbitionCatalog.drive(p, AmbitionCatalog.KIND_LOVE)
	var revenge := AmbitionCatalog.drive(p, AmbitionCatalog.KIND_REVENGE)
	var wealth := AmbitionCatalog.drive(p, AmbitionCatalog.KIND_WEALTH)
	# Poder: subir de rango (quien aún no es noble) o conspirar contra quien manda (señores intrigantes).
	if not is_lord and c.rank() < Character.rank_of(Character.Role.NOBLEZA_BAJA):
		out.append({"id": "ascender", "score": power * (0.4 + 0.6 * AmbitionCatalog.ramp(c.leadership + c.charisma, 10, 30))})
	if is_lord and SCHEMER(p) > 0.0:
		var victim := _usurp_victim(r)
		if not victim.is_empty():
			out.append({"id": "usurpar", "target": victim, "score": power * SCHEMER(p) * 0.8})
	# Amor y familia: casarse si está libre; casar a los hijos si ya tiene familia.
	var married := _is_married(r)
	if not married and r.kind != Relationship.Kind.CONYUGE:
		var fondness := AmbitionCatalog.ramp(r.affection, 20, 80) if RelationsData.courtable(r) else 0.0
		out.append({"id": "casarse", "score": love * (0.5 + 0.5 * fondness)})
	if is_lord and married:
		out.append({"id": "casar_hijos", "score": love * 0.8})
	# Venganza: contra ti si te guarda rencor; contra otro PNJ si su carácter lo pide.
	if r.grudge >= REVENGE_GRUDGE and r.kind != Relationship.Kind.CONYUGE:
		out.append({"id": "vengarse", "score": revenge * (0.6 + 1.4 * AmbitionCatalog.ramp(r.grudge, REVENGE_GRUDGE, 90))})
	out.append({"id": "rivalidad", "score": revenge * 0.35})
	# Riqueza y fe.
	out.append({"id": "enriquecerse", "score": wealth * (0.3 + 0.4 * (1.0 - AmbitionCatalog.ramp(c.gold, 0, 600)))})
	if FAITH(p) > 0.0:
		out.append({"id": "fe", "score": wealth * FAITH(p) * 0.6})
	if is_lord and PAGEANT(p) > 0.0:
		out.append({"id": "torneo", "score": wealth * PAGEANT(p) * 0.5})
	if BLACKMAILER(p) > 0.0 and has_secret() and r.kind != Relationship.Kind.CONYUGE and not r.person_name in RelationsData.retinue:
		out.append({"id": "chantaje", "score": wealth * BLACKMAILER(p) * 0.9})
	return out

func SCHEMER(p: int) -> float:
	return AmbitionCatalog.SCHEMERS.get(p, 0.0)

func FAITH(p: int) -> float:
	return AmbitionCatalog.FAITH.get(p, 0.0)

func PAGEANT(p: int) -> float:
	return AmbitionCatalog.PAGEANTRY.get(p, 0.0)

func BLACKMAILER(p: int) -> float:
	return AmbitionCatalog.BLACKMAILERS.get(p, 0.0)

func _is_married(r: Relationship) -> bool:
	return WorldEvents.married_lords.has(r.person_name) or married_npcs.has(r.person_name) \
		or r.kind == Relationship.Kind.CONYUGE

## Contra quién conspiraría un señor: el señor más poderoso de su reino (si no es él ni tú).
func _usurp_victim(r: Relationship) -> String:
	var best := ""
	var most := 0
	var player_name := GameManager.player_character.full_name() if GameManager.player_character != null else ""
	for other: Relationship in RelationsData.lords():
		if other == r or other.kingdom != r.kingdom or other.person_name == player_name:
			continue
		var n := RelationsData.castles_of(other.person_name).size()
		if n > most:
			most = n
			best = other.person_name
	# También puede ir a por ti, si gobiernas castillos en su reino.
	if best.is_empty() and not player_name.is_empty():
		for c: Castle in RelationsData.castles_of(player_name):
			if c.kingdom == r.kingdom:
				return player_name
	return best

# --- Secretos (para el chantaje) ---

func has_secret() -> bool:
	var now := GameManager.months_elapsed()
	return secrets.any(func(s: Dictionary) -> bool: return now - int(s.month) <= SECRET_MONTHS)

func _note_shame(now: int) -> void:
	var player: Character = GameManager.player_character
	if last_honor >= 0 and last_honor - player.honor >= SHAME_HONOR_DROP:
		secrets.append({"month": now, "text": "tus bajezas"})
	last_honor = player.honor
	secrets = secrets.filter(func(s: Dictionary) -> bool: return now - int(s.month) <= SECRET_MONTHS)

# --- Maduración ---

func _mature(person_name: String, a: Dictionary, now: int) -> void:
	var r := RelationsData.get_relation(person_name)
	if r == null:
		ambitions.erase(person_name)
		return
	if plot_owner == person_name:
		return   # su complot espera tu decisión en la cola
	var event := _player_event(r, a)
	if not event.is_empty():
		if _can_present(now) and randf() < PLOT_PRESENT_CHANCE:
			plot_owner = person_name
			last_plot_month = now
			stats.plots += 1
			GameManager.queue_event(event)
			return
		a.held = int(a.held) + 1
		if int(a.held) <= PLOT_HOLD_MONTHS:
			return   # espera su ocasión
	_npc_outcome(r, a)
	_finish(person_name, now)

func _can_present(now: int) -> bool:
	return plot_owner.is_empty() and now - last_plot_month >= PLOT_MIN_GAP_MONTHS \
		and not CaptureData.is_captive() and not DynastyData.needs_succession()

func _finish(person_name: String, now: int) -> void:
	ambitions.erase(person_name)
	cooldown[person_name] = now + randi_range(COOLDOWN_MONTHS[0], COOLDOWN_MONTHS[1])
	if plot_owner == person_name:
		plot_owner = ""

# --- Eventos que te implican ---

func _player_event(r: Relationship, a: Dictionary) -> Dictionary:
	var id: String = a.id
	if INVOLVE_CHANCE.has(id) and not a.has("involve"):
		a["involve"] = randf() < INVOLVE_CHANCE[id]   # se decide una vez: si no te busca, no insiste
	if INVOLVE_CHANCE.has(id) and not a.involve:
		return {}
	var player: Character = GameManager.player_character
	match id:
		"usurpar": return _usurp_event(r, a, player)
		"casarse": return _proposal_event(r, player)
		"casar_hijos": return _children_event(r, player)
		"ascender": return _rise_event(r, player)
		"vengarse": return _revenge_event(r, player)
		"rivalidad": return _rival_event(r, a, player)
		"enriquecerse": return _invest_event(r, player)
		"fe": return _faith_event(r, player)
		"torneo": return _tourney_event(r, player)
		"chantaje": return _blackmail_event(r, player) if has_secret() else {}
	return {}

func _base(r: Relationship, id: String, title: String, text: String, topic: String, ctx: Dictionary = {}) -> Dictionary:
	var player: Character = GameManager.player_character
	var values := {"player": player.full_name()}
	values.merge(ctx)
	return {"id": "amb_" + id, "title": title, "speaker": r.person_name, "amb_owner": r.person_name,
		"quote": AmbitionCatalog.line(topic, r.character, player, values), "text": text, "options": []}

func _usurp_event(r: Relationship, a: Dictionary, player: Character) -> Dictionary:
	var victim: String = a.target
	if victim.is_empty() or RelationsData.get_relation(victim) == null and victim != player.full_name():
		return {}
	if victim == player.full_name():
		# Un informante te avisa: la conjura es contra ti.
		var e := _base(r, "usurpar_tu", "Una conjura contra ti",
			"Un informante te avisa: %s trama quedarse con tus tierras." % r.person_name, "plot_against_you", {"plotter": r.person_name})
		e.erase("speaker")   # habla el informante, no el conspirador
		e["target"] = r.person_name
		e.options = [
			{"label": "Prenderle", "amb_act": "arrest", "chance": 0.5, "chance_stat": "strategy",
				"success": {"effects": {"honor": 2}, "result": "Le sorprendéis antes de que actúe."},
				"failure": {"effects": {"castle_gold": -80, "garrison": -15}, "result": "Huye a tiempo y su gente saquea tus arcas."}},
			{"label": "Comprar su lealtad (%d oro)" % (BRIBE_PEACE_GOLD * 2), "amb_act": "bribe", "requires": {"gold": BRIBE_PEACE_GOLD * 2}, "amb_cost": BRIBE_PEACE_GOLD * 2,
				"effects": {"affinity": 10}, "result": "El oro calma las ambiciones… por ahora."},
			{"label": "No hacer nada", "amb_act": "ignore", "effects": {"castle_gold": -80, "garrison": -20},
				"result": "La conjura estalla: pierdes oro y hombres antes de sofocarla."},
		]
		return e
	# Te invita a su conjura: solo si eres de su reino, tienes cierto rango y no es contra ti.
	if r.kingdom != GameManager.player_kingdom or player.rank() < Character.rank_of(Character.Role.CABALLERO):
		return {}
	var e := _base(r, "usurpar", "Únete a mi conjura",
		"%s conspira contra %s y busca aliados." % [r.person_name, victim], "plot_usurp", {"victim": victim})
	e.options = [
		{"label": "Unirte a la conjura", "amb_act": "join", "effects": {}, "result": "Juras guardar el secreto y aportar tu espada."},
		{"label": "Delatarle ante %s" % victim, "amb_act": "denounce", "effects": {"honor": 4, "grudge": 40},
			"result": "%s queda al descubierto." % r.person_name},
		{"label": "Pedirle oro por tu silencio", "amb_act": "exploit", "effects": {"gold": BLACKMAIL_GOLD, "honor": -5, "grudge": 25},
			"result": "Paga, pero no te lo perdonará."},
		{"label": "Mantenerte al margen", "amb_act": "ignore", "effects": {}, "result": "No quieres saber nada."},
	]
	return e

func _proposal_event(r: Relationship, player: Character) -> Dictionary:
	if not RelationsData.courtable(r) or RelationsData.is_married() or r.affection < LOVE_PROPOSAL_AFFECTION:
		return {}
	var e := _base(r, "casarse", "Una declaración", "%s te abre su corazón." % r.person_name, "plot_marry_self")
	e.options = [
		{"label": "Corresponder", "amb_act": "accept", "effects": {"affection": 15}, "result": "Nace un amor que la corte no tardará en notar."},
		{"label": "Rechazarle con dulzura", "amb_act": "refuse", "effects": {"affection": -10}, "result": "Lo acepta con tristeza."},
	]
	return e

func _children_event(r: Relationship, player: Character) -> Dictionary:
	var has_heirs := not DynastyData.children().is_empty()
	var can_wed_you := not RelationsData.is_married() and player.rank() >= Character.rank_of(Character.Role.NOBLEZA_BAJA)
	if not has_heirs and not can_wed_you:
		return {}
	var whom := "a uno de tus hijos" if has_heirs else "a ti"
	var e := _base(r, "casar_hijos", "Una alianza de sangre",
		"%s propone casar a alguien de su casa con %s." % [r.person_name, whom], "plot_marry_children")
	e.options = [
		{"label": "Aceptar el enlace", "amb_act": "accept_union" if has_heirs else "wed_you", "effects": {"affinity": 20, "gold": DOWRY_GOLD if has_heirs else 0},
			"result": "Las dos casas quedan unidas."},
		{"label": "Pedir una dote mayor", "amb_act": "exploit", "chance": 0.5, "chance_stat": "charisma",
			"success": {"effects": {"gold": DOWRY_GOLD * 2, "affinity": 10}, "result": "Accede, a regañadientes."},
			"failure": {"effects": {"affinity": -10}, "result": "Se ofende y retira la oferta."}},
		{"label": "Declinar", "amb_act": "refuse", "effects": {"affinity": -5}, "result": "Declinas con cortesía."},
	]
	return e

func _rise_event(r: Relationship, player: Character) -> Dictionary:
	if r.kind == Relationship.Kind.SENOR or r.affection < RISE_MIN_AFFECTION or RelationsData.liege_name.is_empty() \
			or player.rank() < Character.rank_of(Character.Role.CABALLERO):
		return {}
	var e := _base(r, "ascender", "Una recomendación", "%s quiere que hables en su favor ante tu señor." % r.person_name, "plot_rise")
	e.options = [
		{"label": "Recomendarle", "amb_act": "support", "effects": {"affection": 12}, "result": "Tu palabra le abre puertas."},
		{"label": "Hacerlo, a cambio de oro", "amb_act": "support_paid", "effects": {"gold": 40, "honor": -3, "affection": -5},
			"result": "Paga y sube. Ya no te mira igual."},
		{"label": "Negarte", "amb_act": "refuse", "effects": {"affection": -8}, "result": "Se marcha decepcionado."},
	]
	return e

func _revenge_event(r: Relationship, player: Character) -> Dictionary:
	var c := r.character
	var nemesis := r.rivalry_stage() == Relationship.RivalryStage.NEMESIS
	if nemesis and c.personality == Character.Personality.CRUEL and randf() < ASSASSIN_ATTEMPT_CHANCE:
		var e := _base(r, "asesino", "Un puñal en la noche", "Un asesino a sueldo de %s entra en tus aposentos." % r.person_name, "plot_revenge")
		e.options = [
			{"label": "Defenderte", "amb_act": "survive", "chance": 0.55, "chance_stat": "combat",
				"success": {"effects": {"honor": 3, "fame": 3}, "result": "Desarmas al asesino. Toda la corte habla de ello."},
				"failure": {"effects": {"health": -45}, "result": "Sobrevives por poco, malherido."}},
			{"label": "Huir y pedir auxilio", "amb_act": "survive", "effects": {"health": -10, "honor": -2}, "result": "La guardia llega a tiempo."},
		]
		return e
	if c.personality in [Character.Personality.ASTUTO, Character.Personality.COBARDE]:
		var e := _base(r, "sabotaje", "Sabotaje", "Alguien ha quemado un almacén de tu castillo. Todo apunta a %s." % r.person_name, "plot_revenge")
		e.options = [
			{"label": "Investigar", "amb_act": "fight_back", "chance": 0.5, "chance_stat": "strategy",
				"success": {"effects": {"honor": 3, "grudge": 10}, "result": "Encuentras pruebas y le dejas en evidencia."},
				"failure": {"effects": {"castle_gold": -SABOTAGE_GOLD}, "result": "No hallas nada y las pérdidas son tuyas."}},
			{"label": "Ofrecerle la paz (%d oro)" % BRIBE_PEACE_GOLD, "amb_act": "peace", "requires": {"gold": BRIBE_PEACE_GOLD}, "amb_cost": BRIBE_PEACE_GOLD,
				"effects": {"grudge": -25}, "result": "Acepta el oro. El rencor se enfría."},
			{"label": "Asumir la pérdida", "amb_act": "ignore", "effects": {"castle_gold": -SABOTAGE_GOLD}, "result": "Reconstruyes el almacén."},
		]
		return e
	var e := _base(r, "venganza", "Una afrenta pública", "%s te humilla ante toda la corte." % r.person_name, "plot_revenge")
	e["duel_with"] = r.person_name
	e.options = [
		{"label": "Responder con la espada", "amb_act": "fight_back", "requires": {"healthy": true}, "start_duel": true, "effects": {},
			"result": "Le retas a duelo allí mismo."},
		{"label": "Desmentirle", "amb_act": "fight_back", "chance": 0.5, "chance_stat": "charisma",
			"success": {"effects": {"honor": 3, "grudge": 5}, "result": "Tu palabra pesa más que la suya."},
			"failure": {"effects": {"honor": -4, "fame": -2}, "result": "La corte se ríe de ti."}},
		{"label": "Ofrecerle la paz (%d oro)" % BRIBE_PEACE_GOLD, "amb_act": "peace", "requires": {"gold": BRIBE_PEACE_GOLD}, "amb_cost": BRIBE_PEACE_GOLD,
			"effects": {"grudge": -25}, "result": "Acepta, aunque no olvida del todo."},
	]
	return e

func _rival_event(r: Relationship, a: Dictionary, player: Character) -> Dictionary:
	var rival := _pick_rival(r)
	if rival.is_empty() or maxi(r.affection, r.affinity) < RIVAL_ALLY_MIN:
		return {}
	a.target = rival
	var e := _base(r, "rivalidad", "Ayuda contra un rival", "%s quiere hundir a %s y te pide ayuda." % [r.person_name, rival],
		"plot_rival", {"rival": rival})
	e.options = [
		{"label": "Ponerte de su lado", "amb_act": "side", "effects": {"affection": 10, "affinity": 5}, "result": "Juntos dejáis a %s en mal lugar." % rival},
		{"label": "Avisar a %s" % rival, "amb_act": "warn", "effects": {"grudge": 20, "affection": -10}, "result": "%s queda prevenido." % rival},
		{"label": "Vender información a ambos", "amb_act": "exploit", "effects": {"gold": 50, "honor": -6}, "result": "Ganas oro… y dos enemigos si se enteran."},
		{"label": "No meterte", "amb_act": "ignore", "effects": {}, "result": "Que se arreglen entre ellos."},
	]
	return e

func _invest_event(r: Relationship, player: Character) -> Dictionary:
	var e := _base(r, "negocio", "Un negocio", "%s busca socio para un negocio de lana y sal." % r.person_name, "plot_invest")
	e.options = [
		{"label": "Invertir %d de oro" % INVEST_GOLD, "amb_act": "invest", "requires": {"gold": INVEST_GOLD}, "amb_cost": INVEST_GOLD,
			"effects": {"affinity": 5, "affection": 5}, "result": "Sellas el trato. En unos meses sabrás si fue buena idea."},
		{"label": "Pedirle una comisión por tu protección", "amb_act": "exploit", "effects": {"gold": PROTECTION_GOLD, "honor": -3, "grudge": 10},
			"result": "Paga, mirándote de reojo."},
		{"label": "Declinar", "amb_act": "refuse", "effects": {}, "result": "No es momento de arriesgar."},
	]
	return e

func _faith_event(r: Relationship, player: Character) -> Dictionary:
	var e := _base(r, "fe", "Una obra piadosa", "%s levanta una capilla y peregrinará después." % r.person_name, "plot_faith")
	e.options = [
		{"label": "Donar %d de oro" % DONATION_GOLD, "amb_act": "donate", "requires": {"gold": DONATION_GOLD}, "amb_cost": DONATION_GOLD,
			"effects": {"honor": 4, "affinity": 8, "affection": 8}, "result": "Tu nombre quedará grabado en la capilla."},
		{"label": "Peregrinar con %s (%d oro)" % [r.person_name, PILGRIM_GOLD], "amb_act": "pilgrim", "requires": {"gold": PILGRIM_GOLD}, "amb_cost": PILGRIM_GOLD,
			"effects": {"honor": 3, "fame": 2, "xp": 30, "affection": 10}, "result": "Vuelves con el alma ligera y mejores amigos."},
		{"label": "Quedarte parte de las limosnas", "amb_act": "exploit", "effects": {"gold": 30, "honor": -6}, "result": "Nadie lo sabrá… espero."},
		{"label": "Declinar", "amb_act": "refuse", "effects": {}, "result": "Rezas por la obra, de lejos."},
	]
	return e

func _tourney_event(r: Relationship, player: Character) -> Dictionary:
	var e := _base(r, "torneo", "Un torneo", "%s celebra un torneo y te invita." % r.person_name, "plot_tourney")
	var joust := {"label": "Justar", "amb_act": "joust", "chance": 0.5, "chance_stat": "combat",
		"success": {"effects": {"fame": 5, "gold": 60, "xp": 40, "affinity": 5}, "result": "¡Ganas el torneo!"},
		"failure": {"effects": {"health": -25, "fame": 1}, "result": "Muerdes el polvo en la segunda ronda."}}
	if not player.can_fight_duels() or player.is_wounded():
		joust["requires"] = {"healthy": true}
	e.options = [
		joust,
		{"label": "Asistir como invitado", "amb_act": "attend", "effects": {"affinity": 6, "affection": 6}, "result": "Buen vino, buenas justas y nuevos amigos."},
		{"label": "Declinar", "amb_act": "refuse", "effects": {}, "result": "Mandas tus disculpas."},
	]
	return e

func _blackmail_event(r: Relationship, player: Character) -> Dictionary:
	var e := _base(r, "chantaje", "Sé lo que hiciste", "%s conoce tus bajezas y quiere oro." % r.person_name, "plot_blackmail")
	e["duel_with"] = r.person_name
	e.options = [
		{"label": "Pagar (%d oro)" % BLACKMAIL_GOLD, "amb_act": "pay", "requires": {"gold": BLACKMAIL_GOLD}, "amb_cost": BLACKMAIL_GOLD,
			"effects": {}, "result": "Pagas. El secreto queda guardado… de momento."},
		{"label": "Que hable si quiere", "amb_act": "refuse", "effects": {"honor": -5, "fame": -4, "grudge": 10}, "result": "Lo cuenta todo. La corte murmura."},
		{"label": "Volver las tornas", "amb_act": "fight_back", "chance": 0.45, "chance_stat": "strategy",
			"success": {"effects": {"honor": 2, "grudge": 15}, "result": "Descubres sus propios trapos sucios. Calla."},
			"failure": {"effects": {"honor": -6, "fame": -4}, "result": "Te sale mal y lo cuenta todo."}},
		{"label": "Silenciarle con la espada", "amb_act": "fight_back", "requires": {"healthy": true}, "start_duel": true, "effects": {},
			"result": "Le retas a duelo."},
	]
	return e

# --- Tu decisión ---

func _on_option_chosen(event: Dictionary, option: Dictionary) -> void:
	var owner: String = event.get("amb_owner", "")
	if owner.is_empty():
		return
	var r := RelationsData.get_relation(owner)
	var a: Dictionary = ambitions.get(owner, {})
	var act: String = option.get("amb_act", "")
	var extra := ""
	var cost := int(option.get("amb_cost", 0))
	if cost > 0:
		var player: Character = GameManager.player_character
		player.gold = maxi(0, player.gold - cost)
		extra = "Oro −%d" % cost
	if r != null and not a.is_empty():
		var said := _apply_act(r, a, act)
		if not said.is_empty():
			extra = said if extra.is_empty() else "%s\n%s" % [extra, said]
	if not extra.is_empty():
		event["_extra_result"] = extra
	_finish(owner, GameManager.months_elapsed())

## Consecuencias de tu decisión sobre el mundo (lo que no cubren los efectos estándar del evento).
func _apply_act(r: Relationship, a: Dictionary, act: String) -> String:
	var player: Character = GameManager.player_character
	match a.id:
		"usurpar":
			match act:
				"join": return _resolve_usurp(r, str(a.target), USURP_JOIN_BONUS, true)
				"denounce":
					var victim := RelationsData.get_relation(str(a.target))
					if victim != null:
						victim.adjust(15)
					return _punish_plotter(r, "delatado por %s" % player.full_name())
				"ignore": return _resolve_usurp(r, str(a.target), 0.0, false)
		"casarse":
			if act == "accept":
				r.romance = true
		"casar_hijos":
			match act:
				"accept_union":
					if r.affinity >= Relationship.ALLIANCE_MIN_AFFINITY and not r.at_war:
						r.allied = true
					var text := "Tu casa y la de %s quedan unidas por un compromiso." % r.person_name
					WorldEvents.record(text, "", true)
					return text
				"wed_you":
					return RelationsData.arrange_political_marriage(r.person_name)
		"ascender":
			if act in ["support", "support_paid"]:
				return _promote(r)
		"rivalidad":
			var rival := RelationsData.get_relation(str(a.target))
			if rival != null:
				match act:
					"side":
						rival.adjust_grudge(15)
						_record_npc("%s deja en evidencia a %s ante la corte." % [r.person_name, rival.person_name], true)
					"warn":
						rival.adjust_affection(10)
						rival.adjust(5)
					"exploit":
						rival.adjust_grudge(10)
		"enriquecerse":
			if act == "invest":
				investments.append({"due": GameManager.months_elapsed() + randi_range(INVEST_MONTHS[0], INVEST_MONTHS[1]),
					"amount": INVEST_GOLD, "partner": r.person_name})
		"fe":
			if act == "donate":
				_build_chapel(r)
		"chantaje":
			if act == "pay":
				secrets.clear()
	if act == "denounce" or (act == "warn" and a.id != "rivalidad"):
		return AmbitionCatalog.line("plot_denounced", r.character, player, {"player": player.full_name()})
	return ""

func _resolve_usurp(r: Relationship, victim_name: String, bonus: float, with_player: bool) -> String:
	var victim := RelationsData.get_relation(victim_name)
	if victim == null or victim.character == null:
		return ""
	var chance := USURP_BASE_CHANCE + (r.character.strategy - victim.character.strategy) * USURP_STRATEGY_STEP + bonus
	var player: Character = GameManager.player_character
	if randf() < chance:
		var text := _usurp_success(r, victim)
		if with_player:
			player.gold += 80
			player.add_fame(4)
			r.adjust(20)
			victim.adjust(-40)
			text += " Te recompensa con 80 de oro."
		return text
	var text := _punish_plotter(r, "la conjura contra %s fracasa" % victim.person_name)
	if with_player:
		player.honor = clampi(player.honor - 10, 0, 100)
		victim.adjust(-30)
		victim.adjust_grudge(30)
		text += " Tu nombre sale a relucir: honor −10."
	return text

func _usurp_success(r: Relationship, victim: Relationship) -> String:
	var castles := RelationsData.castles_of(victim.person_name)
	if castles.size() >= 2:
		var taken: Castle = castles.pick_random()
		taken.owner_name = r.person_name
		var text := "%s arrebata %s a %s tras una conjura." % [r.person_name, taken.castle_name, victim.person_name]
		WorldEvents._news(text, taken.castle_id, "Una conjura triunfa")
		return text
	for c: Castle in RelationsData.castles_of(r.person_name):
		c.gold += 100
	var text := "La conjura de %s humilla a %s y le llena las arcas." % [r.person_name, victim.person_name]
	WorldEvents.record(text)
	return text

func _punish_plotter(r: Relationship, why: String) -> String:
	if not RelationsData.castles_of(r.person_name).is_empty() and randf() < USURP_EXECUTE_CHANCE:
		WorldEvents.kill_lord(r, "ejecución por traición")
		return "%s: %s acaba en el cadalso." % [_cap(why), r.person_name]
	r.adjust(-15)
	var text := "%s: %s cae en desgracia." % [_cap(why), r.person_name]
	WorldEvents.record(text)
	return text

func _cap(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)

func _promote(r: Relationship) -> String:
	var c := r.character
	var next := RoleProgression.next_role(c.ladder_role())
	if next < 0 or Character.rank_of(next) > Character.rank_of(Character.Role.NOBLEZA_BAJA):
		return ""
	c.role = next
	var text := "%s asciende a %s." % [r.person_name, c.role_title()]
	WorldEvents.record(text)
	return text

func _build_chapel(r: Relationship) -> void:
	for c: Castle in RelationsData.castles_of(r.person_name):
		c.buildings["capilla"] = mini(int(c.buildings.get("capilla", 0)) + 1, MAX_CHAPEL_LEVEL)
		return

func _pick_rival(r: Relationship) -> String:
	var pool: Array[String] = []
	var player_name := GameManager.player_character.full_name()
	for o: Relationship in RelationsData.relations:
		if o == r or o.character == null or o.kind == Relationship.Kind.PUEBLO or o.person_name == player_name:
			continue
		if o.kind == Relationship.Kind.CONYUGE or o.person_name in RelationsData.retinue or o.romance:
			continue   # tu gente no es blanco de intrigas ajenas
		if CaptureData.is_prisoner(o.person_name) or CaptureData.is_serf(o.person_name):
			continue
		if o.kingdom == r.kingdom or o.kind == r.kind:
			pool.append(o.person_name)
	return pool.pick_random() if not pool.is_empty() else ""

# --- Desenlaces entre PNJ (los ves en la crónica) ---

func _npc_outcome(r: Relationship, a: Dictionary) -> void:
	var c := r.character
	match a.id:
		"enriquecerse":
			var gold := randi_range(HOARD_GOLD[0], HOARD_GOLD[1])
			var castles := RelationsData.castles_of(r.person_name)
			if not castles.is_empty():
				castles[0].gold += gold
			else:
				c.gold += gold
			return   # silencioso: no es noticia
	if news_count >= NPC_NEWS_PER_YEAR:
		stats.fizzled += 1
		return
	var text := ""
	match a.id:
		"ascender":
			text = _promote(r)
		"usurpar":
			var victim := RelationsData.get_relation(str(a.target))
			if victim != null and str(a.target) != GameManager.player_character.full_name():
				text = _resolve_usurp(r, victim.person_name, 0.0, false)
		"casarse":
			text = _npc_marriage(r)
		"casar_hijos":
			text = _npc_children_union(r)
		"rivalidad":
			text = _npc_rivalry(r)
		"fe":
			text = _npc_faith(r)
		"torneo":
			text = _npc_tourney(r)
	if text.is_empty():
		stats.fizzled += 1
		return
	news_count += 1
	stats.npc_news += 1

func _record_npc(text: String, quiet: bool = false) -> String:
	if not quiet:
		WorldEvents.record(text)
	return text

func _npc_marriage(r: Relationship) -> String:
	if r.romance:
		return ""   # su corazón es tuyo: no se casa con otro (para eso están los pretendientes)
	if r.kind == Relationship.Kind.SENOR:
		if WorldEvents.married_lords.has(r.person_name):
			return ""
		WorldEvents._lord_marries(r)
		return "boda" if WorldEvents.married_lords.has(r.person_name) else ""
	var gender := CharacterEnums.Gender.MASCULINO if r.is_female() else CharacterEnums.Gender.FEMENINO
	var culture := CharacterLoader.culture_of_kingdom(r.kingdom)
	var spouse := "%s %s" % [CharacterLoader.random_first_name(gender, culture), CharacterLoader.random_last_name(culture, gender, Character.Role.CABALLERO)]
	married_npcs[r.person_name] = spouse
	if r.affection >= Relationship.ROMANCE_INTEREST and r.kind != Relationship.Kind.CONYUGE:
		r.adjust_affection(-10)
	return _record_npc("%s se casa con %s." % [r.person_name, spouse])

func _npc_children_union(r: Relationship) -> String:
	var others: Array[Relationship] = []
	for o: Relationship in RelationsData.lords():
		if o != r and o.kingdom != r.kingdom and not RelationsData.castles_of(o.person_name).is_empty() \
				and not KingdomDiplomacy.at_war(RelationsData.kingdom_wars, r.kingdom, o.kingdom):
			others.append(o)
	if others.is_empty():
		return ""
	var house: Relationship = others.pick_random()
	var text := "%s casa a su heredero con la casa de %s." % [r.person_name, house.person_name]
	var ai_pair := r.kingdom != GameManager.player_kingdom and house.kingdom != GameManager.player_kingdom
	if ai_pair and randf() < WorldEvents.MARRIAGE_ALLIANCE_CHANCE:
		RelationsData.kingdom_alliances[KingdomDiplomacy.pair_key(r.kingdom, house.kingdom)] = true
		text += " Sus reinos sellan una alianza."
	WorldEvents._news(text, "", "Boda en la nobleza" if not ai_pair else "")
	return text

func _npc_rivalry(r: Relationship) -> String:
	var rival_name := _pick_rival(r)
	var rival := RelationsData.get_relation(rival_name)
	if rival == null or rival.character == null:
		return ""
	if r.character.personality == Character.Personality.CRUEL and randf() < ASSASSINATION_CHANCE * 3.0 \
			or randf() < ASSASSINATION_CHANCE:
		if rival.kind == Relationship.Kind.SENOR:
			WorldEvents.kill_lord(rival, "un veneno en la copa")
		else:
			RelationsData.on_character_died(rival.person_name, "asesinato")
		var t := "Se rumorea que %s está detrás de la muerte de %s." % [r.person_name, rival_name]
		WorldEvents.notify("Un crimen en la corte", t)
		return _record_npc(t)
	var won: bool = r.character.combat + randi_range(-4, 4) >= rival.character.combat
	var winner := r.person_name if won else rival_name
	var loser := rival_name if won else r.person_name
	return _record_npc("%s humilla a %s en un duelo." % [winner, loser])

func _npc_faith(r: Relationship) -> String:
	if not RelationsData.castles_of(r.person_name).is_empty():
		_build_chapel(r)
		return _record_npc("%s funda una capilla en sus tierras." % r.person_name)
	return _record_npc("%s parte en peregrinación a Compostela." % r.person_name)

func _npc_tourney(r: Relationship) -> String:
	var champions: Array[Relationship] = []
	for o: Relationship in RelationsData.relations:
		if o.character != null and o.kingdom == r.kingdom and o.kind in [Relationship.Kind.CORTESANO, Relationship.Kind.RIVAL_DUELO]:
			champions.append(o)
	if champions.is_empty():
		return _record_npc("%s celebra un gran torneo." % r.person_name)
	var best: Relationship = champions[0]
	for o in champions:
		if o.character.combat + randi_range(0, 5) > best.character.combat:
			best = o
	best.character.add_fame(3)
	return _record_npc("%s celebra un torneo. Vence %s." % [r.person_name, best.person_name])

# --- Inversiones ---

func _pay_investments(now: int) -> void:
	var player: Character = GameManager.player_character
	for inv: Dictionary in investments.duplicate():
		if int(inv.due) > now:
			continue
		investments.erase(inv)
		if randf() < INVEST_SUCCESS:
			var gain := roundi(int(inv.amount) * INVEST_RETURN)
			player.gold += gain
			WorldEvents.notify("Un buen negocio", "El negocio con %s da fruto: +%d de oro." % [inv.partner, gain])
		else:
			WorldEvents.notify("Un mal negocio", "El negocio con %s se hunde. Pierdes lo invertido." % inv.partner)

# --- Guardado ---

func save_state() -> Dictionary:
	return {"ambitions": ambitions.duplicate(true), "cooldown": cooldown.duplicate(), "married_npcs": married_npcs.duplicate(),
		"investments": investments.duplicate(true), "secrets": secrets.duplicate(true), "last_plot_month": last_plot_month,
		"plot_owner": plot_owner, "news_year": news_year, "news_count": news_count, "last_honor": last_honor}

func load_state(data: Dictionary) -> void:
	reset()
	ambitions = data.get("ambitions", {}).duplicate(true)
	cooldown = data.get("cooldown", {}).duplicate()
	married_npcs = data.get("married_npcs", {}).duplicate()
	investments = data.get("investments", []).duplicate(true)
	secrets = data.get("secrets", []).duplicate(true)
	last_plot_month = int(data.get("last_plot_month", -100))
	plot_owner = str(data.get("plot_owner", ""))
	news_year = int(data.get("news_year", 0))
	news_count = int(data.get("news_count", 0))
	last_honor = int(data.get("last_honor", -1))
	# Si el complot que esperaba ya no está en la cola (partida guardada sin él), se libera.
	if not plot_owner.is_empty() and str(GameManager.pending_event.get("amb_owner", "")) != plot_owner \
			and not GameManager.event_queue.any(func(e) -> bool: return str(e.get("amb_owner", "")) == plot_owner):
		plot_owner = ""
