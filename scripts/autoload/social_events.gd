extends Node
# Autoload — sucesos sociales del mes (ver SocialEventCatalog): lazos según la intimidad, rivalidades,
# cartas y visitas de señores que reaccionan a tus hazañas, y la vida de tu facción.
# Como mucho uno al mes, solo si el mes no trae ya otra decisión, con pausa global y por persona.
# Los eventos llegan por GameManager.queue_event; lo que no cabe en EventCatalog (intimidad con toda
# la facción, duelos concertados, rencor de terceros) lo aplica _on_option_chosen. Guarda su estado (SaveSystem.MODULES).

const SocialEventCatalog = preload("res://scripts/resources/social_event_catalog.gd")

const FIRST_MONTH := 3                          # nada en los primeros meses de partida
const MIN_GAP_MONTHS := 2                       # meses entre dos sucesos sociales (máx. 1 al mes)
const PERSON_COOLDOWN := 10                     # meses antes de que la misma persona protagonice otro
const BOND_CHANCE := 0.05                       # prob. mensual de un suceso de lazo (si hay alguien cercano)
const RIVALRY_STAGE_CHANCE := [0.02, 0.06, 0.12, 0.04]   # por etapa: conocido, rival, némesis, respeto
const DEED_REACTION_CHANCE := 0.5               # un señor responde a una hazaña reciente
const DEED_MEMORY := 4                          # meses que una hazaña sigue dando que hablar
const DISHONOR_DROP := 8                        # caída de honor en un mes que se considera deshonra
const TOAST_CHANCE := 0.6                       # brindis tras una victoria con camaradas
const TOAST_WINDOW := 2                         # meses tras la batalla en que aún se brinda
const LORD_AMBIENT_CHANCE := 0.025              # órdenes, peticiones, visitas o banquetes sin motivo
const FACTION_AMBIENT_CHANCE := 0.025           # camaradería, disputas, camaradas en apuros
const DUEL_DELAY := 2                           # meses hasta un duelo de honor concertado
const PACING_WINDOW := 12                      # meses que se miran para no saturar de decisiones
const PACING_MAX_SHARE := 0.5                   # si la mitad de esos meses ya trajo decisión, no se añade otra
const EVENT_KEY := "_social"

signal social_event_queued(id: String)

var last_event_month := -1000
var cooldowns: Dictionary = {}       # nombre -> mes del último suceso que protagonizó
var deeds: Array = []                # [{type: victoria|deshonra|boda, m}]
var seen_victory := -1
var last_honor := -1
var was_married := false
var last_battle: Dictionary = {}     # {names[], won, m}
var scheduled_duels: Array = []      # [{name, due}]
var counts: Dictionary = {}          # id de categoría -> sucesos lanzados (estadística)
var recent_busy: Array = []          # últimos PACING_WINDOW meses: ¿trajo ya otra decisión?

func _ready() -> void:
	GameManager.game_started.connect(func(_c: Character): reset())
	GameManager.turn_advanced.connect(_on_month_passed)
	GameManager.event_option_chosen.connect(_on_option_chosen)

func reset() -> void:
	last_event_month = -1000
	cooldowns = {}
	deeds = []
	seen_victory = RelationsData.last_victory_month
	var p: Character = GameManager.player_character
	last_honor = p.honor if p != null else -1
	was_married = RelationsData.is_married()
	last_battle = {}
	scheduled_duels = []
	counts = {}
	recent_busy = []

func _now() -> int:
	return GameManager.months_elapsed()

# --- Mes ---

func _on_month_passed(_month: int, _year: int) -> void:
	var p: Character = GameManager.player_character
	if not GameManager.is_game_active or p == null:
		return
	_track_deeds(p)
	recent_busy.append(not GameManager.pending_event.is_empty() or not GameManager.event_queue.is_empty())
	if recent_busy.size() > PACING_WINDOW:
		recent_busy.pop_front()
	if _queue_due_duel():
		return
	if not can_fire():
		return
	var event := pick_event()
	if not event.is_empty():
		deliver(event)

func _track_deeds(p: Character) -> void:
	var now := _now()
	if RelationsData.last_victory_month > seen_victory:
		seen_victory = RelationsData.last_victory_month
		deeds.append({"type": "victoria", "m": now})
	if last_honor >= 0 and p.honor <= last_honor - DISHONOR_DROP:
		deeds.append({"type": "deshonra", "m": now})
	last_honor = p.honor
	if RelationsData.is_married() and not was_married:
		deeds.append({"type": "boda", "m": now})
	was_married = RelationsData.is_married()
	deeds = deeds.filter(func(d: Dictionary) -> bool: return now - int(d.m) <= DEED_MEMORY)

func can_fire() -> bool:
	return _now() >= FIRST_MONTH and _now() - last_event_month >= MIN_GAP_MONTHS \
		and GameManager.pending_event.is_empty() and GameManager.event_queue.is_empty() 		and recent_busy.count(true) < PACING_MAX_SHARE * PACING_WINDOW

## Elige el suceso del mes por orden de urgencia ({} si no toca ninguno).
func pick_event() -> Dictionary:
	var e := {}
	if not deeds.is_empty() and randf() < DEED_REACTION_CHANCE:
		e = lord_event(str(deeds.back().type))
		if not e.is_empty():
			deeds.pop_back()
			return e
	if not last_battle.is_empty() and _now() - int(last_battle.m) <= TOAST_WINDOW and randf() < TOAST_CHANCE:
		e = faction_event(true)
		last_battle = {}
		if not e.is_empty():
			return e
	e = _try_rivalry()
	if e.is_empty() and randf() < BOND_CHANCE:
		var people := bond_people()
		if not people.is_empty():
			e = bond_event(people.pick_random())
	if e.is_empty() and randf() < FACTION_AMBIENT_CHANCE:
		e = faction_event(false)
	if e.is_empty() and randf() < LORD_AMBIENT_CHANCE:
		e = lord_event("")
	return e

func deliver(event: Dictionary) -> void:
	last_event_month = _now()
	var who := str(event.get("speaker", ""))
	if not who.is_empty():
		cooldowns[who] = _now()
	var cat := str(event.get(EVENT_KEY, {}).get("cat", "?"))
	counts[cat] = int(counts.get(cat, 0)) + 1
	GameManager.queue_event(event)
	social_event_queued.emit(str(event.get("id", "")))

func _cooling(person_name: String) -> bool:
	return _now() - int(cooldowns.get(person_name, -1000)) < PERSON_COOLDOWN

func _weighted(templates: Array, personality: int) -> Dictionary:
	var total := 0.0
	for t: Dictionary in templates:
		total += float(t.get("bias", {}).get(personality, 1.0))
	var roll := randf() * total
	for t: Dictionary in templates:
		roll -= float(t.get("bias", {}).get(personality, 1.0))
		if roll <= 0.0:
			return t
	return templates.back() if not templates.is_empty() else {}

func _make(t: Dictionary, r: Relationship, cat: String, extra: Dictionary = {}) -> Dictionary:
	var p: Character = GameManager.player_character
	var names := {"name": r.person_name, "player": p.full_name()}
	names.merge(extra)
	var e := SocialEventCatalog.build(t, r.character, p, names)
	e["speaker"] = r.person_name
	e["target"] = r.person_name
	e[EVENT_KEY] = {"cat": cat, "names": names}
	return e

# --- 1) Lazos ---

## Clases de lazo de una persona (ver SocialEventCatalog: kinds).
func bond_kinds(r: Relationship) -> Array[String]:
	var k: Array[String] = []
	if r.kind == Relationship.Kind.CONYUGE:
		k.append("spouse")
	elif r.romance:
		k.append("lover")
	if CaptureData.is_prisoner(r.person_name):
		k.append("prisoner")
	if CaptureData.is_serf(r.person_name):
		k.append("serf")
	if r.person_name in RelationsData.retinue:
		k.append("retinue")
	if RelationsData.intimacy_tier(r.affection) >= 2:
		k.append("friend")
	if r.kind == Relationship.Kind.CORTESANO:
		k.append("courtier")
	return k

func bond_people() -> Array[Relationship]:
	var out: Array[Relationship] = []
	for r: Relationship in RelationsData.relations:
		if r.character == null or _cooling(r.person_name) or RelationsData.intimacy_tier(r.affection) < 1:
			continue
		if r.kind == Relationship.Kind.SENOR or r.kind == Relationship.Kind.RIVAL_DUELO:
			continue
		var kinds := bond_kinds(r)
		if kinds.has("spouse") or kinds.has("retinue") or kinds.has("serf") or kinds.has("prisoner") or RelationsData.person_present(r):
			out.append(r)
	return out

## Plantillas de lazo posibles con esa persona: más intimidad, más sucesos.
func bond_templates(r: Relationship) -> Array:
	var tier := RelationsData.intimacy_tier(r.affection)
	var kinds := bond_kinds(r)
	return SocialEventCatalog.BOND.filter(func(t: Dictionary) -> bool:
		if int(t.min_tier) > tier:
			return false
		var want: Array = t.get("kinds", [])
		return want.is_empty() or want.any(func(x: String) -> bool: return x in kinds))

func bond_event(r: Relationship, id: String = "") -> Dictionary:
	var pool := bond_templates(r)
	if not id.is_empty():
		pool = pool.filter(func(t: Dictionary) -> bool: return t.id == id)
	if pool.is_empty():
		return {}
	return _make(_weighted(pool, r.character.personality), r, "lazo")

# --- 2) Rivalidades ---

func rivalry_chance(r: Relationship) -> float:
	return RIVALRY_STAGE_CHANCE[r.rivalry_stage()]

func _try_rivalry() -> Dictionary:
	var rivals := RelationsData.duel_rivals()
	rivals.shuffle()
	for r: Relationship in rivals:
		if r.character != null and not _cooling(r.person_name) and randf() < rivalry_chance(r):
			return rivalry_event(r)
	return {}

func rivalry_event(r: Relationship, id: String = "") -> Dictionary:
	var stage := r.rivalry_stage()
	var beloved := _beloved()
	var third := _third_party(r)
	var pool: Array = SocialEventCatalog.RIVALRY.filter(func(t: Dictionary) -> bool:
		if not stage in t.stages or (not id.is_empty() and t.id != id):
			return false
		match str(t.get("needs", "")):
			"beloved": return beloved != null
			"third": return third != null
		return true)
	if pool.is_empty():
		return {}
	var t := _weighted(pool, r.character.personality)
	var extra := {}
	if str(t.get("needs", "")) == "beloved":
		extra["third"] = beloved.person_name
	elif third != null:
		extra["third"] = third.person_name
	var e := _make(t, r, "rivalidad", extra)
	e["duel_with"] = r.person_name
	if t.id == "soc_sabotaje":
		e["target"] = beloved.person_name   # el cortejo afecta a quien amas; el duelo, al rival
	return e

func _beloved() -> Relationship:
	if RelationsData.is_married():
		return null
	for r: Relationship in RelationsData.relations:
		if r.romance and r.affection >= Relationship.ROMANCE_INTEREST and r.character != null:
			return r
	return null

func _third_party(r: Relationship) -> Relationship:
	for o: Relationship in RelationsData.duel_rivals():
		if o != r and o.character != null:
			return o
	return null

# --- 3) Señores ---

func _lord_ok(r: Relationship) -> bool:
	return r != null and r.character != null and not r.at_war and not _cooling(r.person_name)

func neighbor_lords() -> Array[Relationship]:
	var out: Array[Relationship] = []
	for r: Relationship in RelationsData.lords():
		if r.person_name == RelationsData.liege_name or not _lord_ok(r):
			continue
		var cs := RelationsData.castles_of(r.person_name)
		if not cs.is_empty() and (cs[0].kingdom == GameManager.player_kingdom or cs[0].kingdom in RelationsData.allied_kingdoms()):
			out.append(r)
	return out

## Carta, orden, visita o banquete de un señor; deed = hazaña a la que reacciona ("" = ninguna).
func lord_event(deed: String, id: String = "") -> Dictionary:
	var liege := RelationsData.get_relation(RelationsData.liege_name)
	var neighbors := neighbor_lords()
	var pool: Array = SocialEventCatalog.LORD.filter(func(t: Dictionary) -> bool:
		if str(t.deed) != deed or (not id.is_empty() and t.id != id):
			return false
		return _lord_ok(liege) if t.liege else not neighbors.is_empty())
	if pool.is_empty():
		return {}
	var t: Dictionary = pool.pick_random()
	var lord: Relationship = liege if t.liege else neighbors.pick_random()
	return _make(t, lord, "senor")

# --- 4) Facción ---

## Lo llama ArmyData.battle_bonds: quienes lucharon a tu lado brindarán contigo.
func note_battle(names: Array, won: bool) -> void:
	if won and not names.is_empty():
		last_battle = {"names": names.duplicate(), "won": won, "m": _now()}

func comrades() -> Array[Relationship]:
	var out: Array[Relationship] = []
	if GameManager.player_kingdom < 0:
		return out
	for r: Relationship in RelationsData.courtiers(GameManager.player_kingdom):
		if r.character != null:
			out.append(r)
	for r: Relationship in RelationsData.retinue_members():
		if r.character != null and not r in out:
			out.append(r)
	return out

func faction_event(after_battle: bool, id: String = "") -> Dictionary:
	var group := comrades()
	if not last_battle.is_empty():
		for n in last_battle.names:
			var r := RelationsData.get_relation(str(n))
			if r != null and r.character != null and not r in group:
				group.push_front(r)
	group = group.filter(func(r: Relationship) -> bool: return not _cooling(r.person_name))
	if group.is_empty():
		return {}
	var liege := RelationsData.get_relation(RelationsData.liege_name)
	var pool: Array = SocialEventCatalog.FACTION.filter(func(t: Dictionary) -> bool:
		if bool(t.after_battle) != after_battle or (not id.is_empty() and t.id != id):
			return false
		if t.get("liege", false) and not _lord_ok(liege):
			return false
		return group.size() >= 2 or t.id != "soc_rivalidad_interna")
	if pool.is_empty():
		return {}
	var t: Dictionary = pool.pick_random()
	var hero: Relationship = liege if t.get("liege", false) else group[0] if after_battle else group.pick_random()
	var comrade: Relationship = group[1] if group.size() > 1 and group[0] == hero else group[0]
	var e := _make(t, hero, "faccion", {"comrade": comrade.person_name})
	e[EVENT_KEY]["group"] = group.map(func(r: Relationship) -> String: return r.person_name)
	return e

# --- Efectos propios y duelos concertados ---

func _on_option_chosen(event: Dictionary, option: Dictionary) -> void:
	if not event.has(EVENT_KEY) or not option.has("social"):
		return
	var spec: Dictionary = option.social
	var meta: Dictionary = event[EVENT_KEY]
	var names: Dictionary = meta.get("names", {})
	var told: Array[String] = []
	if spec.has("group"):
		for n in meta.get("group", []):
			var r := RelationsData.get_relation(str(n))
			if r != null and r.person_name != str(event.get("target", "")):
				r.adjust_affection(int(spec.group))
		told.append("Intimidad con tu facción %+d" % int(spec.group))
	for key in spec.get("adjust", {}):
		var r := RelationsData.get_relation(str(names.get(key, "")))
		if r != null:
			r.adjust_affection(int(spec.adjust[key]))
			told.append("Afecto de %s %+d" % [r.person_name, int(spec.adjust[key])])
	if spec.has("third_grudge"):
		var r := RelationsData.get_relation(str(names.get("third", "")))
		if r != null:
			r.adjust_grudge(int(spec.third_grudge))
			told.append("Rencor de %s %+d" % [r.person_name, int(spec.third_grudge)])
	if spec.get("schedule_duel", false):
		scheduled_duels.append({"name": str(event.get("speaker", "")), "due": _now() + DUEL_DELAY})
		told.append("Duelo dentro de %d meses" % DUEL_DELAY)
	if not told.is_empty():
		var prev := str(GameManager.pending_event.get("_extra_result", ""))
		GameManager.pending_event["_extra_result"] = (prev + "\n" if not prev.is_empty() else "") + "(" + ", ".join(told) + ")"
	RelationsData.relations_changed.emit()

func _queue_due_duel() -> bool:
	for d: Dictionary in scheduled_duels:
		if _now() >= int(d.due):
			scheduled_duels.erase(d)
			var r := RelationsData.get_relation(str(d.name))
			if r == null or r.character == null:
				return false
			var e := _make(SocialEventCatalog.DUEL_DAY, r, "rivalidad")
			e["duel_with"] = r.person_name
			deliver(e)
			return true
	return false

# --- Guardado ---

func save_state() -> Dictionary:
	return {"last": last_event_month, "cooldowns": cooldowns.duplicate(), "deeds": deeds.duplicate(true),
		"seen_victory": seen_victory, "last_honor": last_honor, "married": was_married,
		"battle": last_battle.duplicate(true), "duels": scheduled_duels.duplicate(true), "counts": counts.duplicate()}

func load_state(data: Dictionary) -> void:
	last_event_month = int(data.get("last", -1000))
	cooldowns = data.get("cooldowns", {}).duplicate()
	deeds = data.get("deeds", []).duplicate(true)
	seen_victory = int(data.get("seen_victory", RelationsData.last_victory_month))
	last_honor = int(data.get("last_honor", -1))
	was_married = bool(data.get("married", RelationsData.is_married()))
	last_battle = data.get("battle", {}).duplicate(true)
	scheduled_duels = data.get("duels", []).duplicate(true)
	counts = data.get("counts", {}).duplicate()
