extends Node
## Lealtad (0-100) de quienes dependen del jugador: séquito, cónyuges y amantes, siervos, vasallos
## (los señores de tu reino si eres Duque o Regente) y la guarnición de cada castillo tuyo.
## Cada mes se acerca a lo que «merece» (intimidad, afinidad, tu honor) y cambia por causas concretas
## (paga, victorias, regalos, deshonra, crueldad...), más o menos deprisa según el carácter.
## Bajo WARN_AT llega un aviso (queja y rumor, con remedios); solo tras un aviso, y bajo BETRAY_AT,
## puede llegar la traición. Otros sistemas usan loyalty_of() e is_disloyal().

signal loyalty_changed

const START := 60
const DISLOYAL_AT := 20          # is_disloyal(): candidato a traicionar (batallas, fase 4)
const WARN_AT := 30
const BETRAY_AT := 18
const RECOVER_AT := 45           # por encima, el aviso se olvida
const WARN_MIN_MONTHS := 2       # meses entre el aviso y una posible traición
const BETRAY_CHANCE := 0.3       # al mes, ya avisado y bajo BETRAY_AT
const DRIFT := 0.15              # fracción de la distancia al valor de fondo que recorre cada mes
const AFFECTION_WEIGHT := 0.4    # intimidad -> lealtad de fondo
const AFFINITY_WEIGHT := 0.3     # afinidad del vasallo -> lealtad de fondo
const HONOR_WEIGHT := 0.3        # tu honor -> lealtad de la guarnición
const SERF_PENALTY := 20         # un siervo nunca es leal del todo
const HUNGRY_CASTLE := 15        # guarnición sin comida
const HONOR_STEP := 3            # cambio de honor en un mes que tu gente nota
const CASTLE_PREFIX := "castillo:"
const CAUSES := {
	"paid": 1, "unpaid": -8, "victory": 4, "defeat": -5, "gift": 5, "honor": 2, "dishonor": -5,
	"mistreat": -6, "loot": 6, "ambition": -3, "talk": 6, "pay": 12, "grant": 20,
}
const SPEED := {Character.Personality.LEAL: 0.5, Character.Personality.AMBICIOSO: 1.6}
const OUTRAGED := [Character.Personality.HONORABLE, Character.Personality.PIADOSO]
const OUTRAGE_FACTOR := 1.5
const DISHONOR_HONORABLE := 2.0
const SAME_KINGDOM_FACTOR := 2.0  # enslavar o ejecutar a gente de su propio reino
const POWER_AMBITIONS := ["ascender", "usurpar"]
const TALK_CHARISMA_DIV := 4
# Remedios del aviso
const REMEDY_PAY_GOLD := 40
const REMEDY_GRANT_GOLD := 120
const PUNISH_FEAR := 10          # cobardes y prudentes: el castigo los mete en cintura
const PUNISH_RESENT := -8
const PUNISH_AFFECTION := -10
const PUNISH_GARRISON := 0.1
const FEARFUL := [Character.Personality.COBARDE, Character.Personality.PRUDENTE]
# Traiciones
const DESERT_GOLD_SHARE := 0.15
const DESERT_GOLD_MAX := 150
const POISON_CHANCE := 0.15
const POISON_DAMAGE := 40
const SELL_INFO_CHANCE := 0.4
const SELL_INFO_GRUDGE := 15
const SELL_INFO_GARRISON := 0.1
const GARRISON_DESERT := 0.3
const CASTLE_GOLD_STOLEN := 0.5
const PLOT_PARDON_HONOR := 3
const PLOT_PARDON_LOYALTY := 15
const PLOT_JAIL_AFFINITY := 25

var loyalty: Dictionary = {}     # clave (nombre o "castillo:<id>") -> 0..100
var warned: Dictionary = {}      # clave -> mes (months_elapsed) del aviso
var _last_honor := -1
var _last_victory := -1

func _ready() -> void:
	GameManager.game_started.connect(func(_c: Character): reset())
	GameManager.turn_advanced.connect(_on_month_passed)
	GameManager.event_option_chosen.connect(_on_option_chosen)

func reset() -> void:
	loyalty.clear()
	warned.clear()
	_last_honor = -1
	_last_victory = RelationsData.last_victory_month

# --- Consultas ---

static func castle_key(c: Castle) -> String:
	return CASTLE_PREFIX + c.castle_id

func key_of(x: Variant) -> String:
	if x is Castle:
		return castle_key(x)
	if x is Relationship:
		return (x as Relationship).person_name
	if x is Character:
		return (x as Character).full_name()
	return str(x)

## Lealtad de alguien (nombre, Character, Relationship) o de la guarnición de un Castle.
func loyalty_of(x: Variant) -> int:
	return int(loyalty.get(key_of(x), START))

func is_tracked(x: Variant) -> bool:
	return loyalty.has(key_of(x))

func is_disloyal(x: Variant) -> bool:
	return is_tracked(x) and loyalty_of(x) < DISLOYAL_AT

func is_warned(x: Variant) -> bool:
	return warned.has(key_of(x))

## Texto corto para fichas: «Lealtad 62».
func bar_text(x: Variant) -> String:
	return "Lealtad %d" % loyalty_of(x)

func status_word(x: Variant) -> String:
	var v := loyalty_of(x)
	if v < BETRAY_AT:
		return "A punto de traicionarte"
	if v < WARN_AT:
		return "Descontento"
	if v < RECOVER_AT:
		return "Dudoso"
	return "Fiel" if v < 80 else "Devoto"

## Vasallos: los señores de tu reino si tu rango es de Duque o más (salvo tu soberano).
func vassals() -> Array[Relationship]:
	var out: Array[Relationship] = []
	var player: Character = GameManager.player_character
	if player == null or player.rank() < Character.rank_of(Character.Role.DUQUE):
		return out
	for r: Relationship in RelationsData.lords():
		if r.kingdom == GameManager.player_kingdom and r.person_name != RelationsData.liege_name \
				and r.character != null and r.person_name != player.full_name():
			out.append(r)
	return out

func dependents() -> Array[String]:
	var out: Array[String] = []
	var player: Character = GameManager.player_character
	if player == null:
		return out
	var names: Array[String] = []
	names.append_array(RelationsData.retinue)
	names.append_array(RelationsData.spouse_names())
	names.append_array(RelationsData.concubines)
	for r: Relationship in vassals():
		names.append(r.person_name)
	for c: Castle in MapData.castles:
		if c.owner_name == player.full_name():
			names.append(castle_key(c))
	for n: String in names:
		if not n.is_empty() and not n in out:
			out.append(n)
	return out

func _personality(key: String) -> int:
	var r := RelationsData.get_relation(key)
	return r.character.personality if r != null and r.character != null else -1

func _display(key: String) -> String:
	if key.begins_with(CASTLE_PREFIX):
		var c: Castle = MapData.get_castle_by_id(key.trim_prefix(CASTLE_PREFIX))
		return "La guarnición de %s" % (c.castle_name if c != null else "tu castillo")
	return key

# --- Cambios ---

## Aplica una causa (ver CAUSES) a alguien, según su carácter. Devuelve la nueva lealtad.
func note(x: Variant, cause: String, scale: float = 1.0) -> int:
	var key := key_of(x)
	var p := _personality(key)
	var f: float = scale * float(SPEED.get(p, 1.0))
	match cause:
		"mistreat":
			if p == Character.Personality.CRUEL:
				f = 0.0
			elif p in OUTRAGED:
				f *= OUTRAGE_FACTOR
		"dishonor":
			if p == Character.Personality.HONORABLE:
				f *= DISHONOR_HONORABLE
	return change(key, roundi(int(CAUSES.get(cause, 0)) * f))

func change(x: Variant, amount: int) -> int:
	var key := key_of(x)
	var v := clampi(loyalty_of(key) + amount, 0, 100)
	loyalty[key] = v
	loyalty_changed.emit()
	return v

func note_all(cause: String, scale: float = 1.0) -> void:
	for key: String in dependents():
		note(key, cause, scale)

func note_if_dependent(x: Variant, cause: String) -> void:
	if key_of(x) in dependents():
		note(x, cause)

## Esclavizas o ejecutas a alguien: tu gente lo nota, más quien es de su mismo reino.
func on_mistreatment(victim_kingdom: int) -> void:
	for key: String in dependents():
		var r := RelationsData.get_relation(key)
		var same := victim_kingdom >= 0 and r != null and r.kingdom == victim_kingdom
		note(key, "mistreat", SAME_KINGDOM_FACTOR if same else 1.0)

## Repartes botín con tu séquito. Devuelve el texto o el motivo.
func share_loot(amount: int) -> String:
	var player: Character = GameManager.player_character
	if player == null or player.gold < amount or RelationsData.retinue.is_empty():
		return "No puedes repartir botín."
	player.gold -= amount
	for person_name: String in RelationsData.retinue:
		note(person_name, "loot")
	return "Repartes %d de oro entre tu séquito." % amount

# --- Paso del tiempo ---

func _on_month_passed(_month: int, _year: int) -> void:
	if not GameManager.is_game_active or GameManager.player_character == null:
		return
	month_tick()

func month_tick() -> void:
	var player: Character = GameManager.player_character
	var deps := dependents()
	for key: String in loyalty.keys():
		if not key in deps:
			loyalty.erase(key)
			warned.erase(key)
	for key: String in deps:
		if not loyalty.has(key):
			loyalty[key] = START
		_drift(key)
	if RelationsData.last_victory_month != _last_victory:
		_last_victory = RelationsData.last_victory_month
		if _last_victory >= 0:
			note_all("victory")
	if _last_honor >= 0:
		if player.honor <= _last_honor - HONOR_STEP:
			note_all("dishonor")
		elif player.honor >= _last_honor + HONOR_STEP:
			note_all("honor")
	_last_honor = player.honor
	for key: String in deps:
		if AmbitionData.ambition_of(key) in POWER_AMBITIONS:
			note(key, "ambition")
	_warnings_and_betrayals(deps)
	loyalty_changed.emit()

func _target(key: String) -> float:
	var player: Character = GameManager.player_character
	if key.begins_with(CASTLE_PREFIX):
		var c: Castle = MapData.get_castle_by_id(key.trim_prefix(CASTLE_PREFIX))
		var t := START + (player.honor - 50) * HONOR_WEIGHT
		return t - (HUNGRY_CASTLE if c != null and c.food <= 0 else 0)
	var r := RelationsData.get_relation(key)
	if r == null:
		return START
	if r.kind == Relationship.Kind.SENOR:
		return START + r.affinity * AFFINITY_WEIGHT
	return START + (r.affection - 50) * AFFECTION_WEIGHT - (SERF_PENALTY if CaptureData.is_serf(key) else 0)

func _drift(key: String) -> void:
	var v := loyalty_of(key)
	var speed: float = SPEED.get(_personality(key), 1.0)
	loyalty[key] = clampi(v + roundi((_target(key) - v) * DRIFT * speed), 0, 100)

## Un aviso al mes como mucho; una traición al mes como mucho, siempre tras un aviso previo.
func _warnings_and_betrayals(deps: Array) -> void:
	var now := GameManager.months_elapsed()
	var warned_now := false
	var betrayed := false
	for key: String in deps:
		var v := loyalty_of(key)
		if warned.has(key):
			if v >= RECOVER_AT:
				warned.erase(key)
			elif not betrayed and v < BETRAY_AT and now - int(warned[key]) >= WARN_MIN_MONTHS and randf() < BETRAY_CHANCE:
				betrayed = true
				warned.erase(key)
				betray(key)
		elif v < WARN_AT and not warned_now:
			warned_now = true
			warn(key)

## Queja (evento con remedios) y rumor en la crónica.
func warn(key: String) -> void:
	warned[key] = GameManager.months_elapsed()
	WorldEvents.record("Rumores: %s murmura contra ti." % _display(key), "", true)
	GameManager.queue_event(warning_event(key))

func warning_event(key: String) -> Dictionary:
	var who := _display(key)
	var castle := key.begins_with(CASTLE_PREFIX)
	var options: Array = [
		{"label": "Hablar", "result": "", "loyalty_action": "talk", "loyalty_target": key},
		{"label": "Pagar (%d)" % REMEDY_PAY_GOLD, "requires": {"gold": REMEDY_PAY_GOLD}, "effects": {"gold": -REMEDY_PAY_GOLD},
			"result": "", "loyalty_action": "pay", "loyalty_target": key},
		{"label": "Conceder favores (%d)" % REMEDY_GRANT_GOLD, "requires": {"gold": REMEDY_GRANT_GOLD},
			"effects": {"gold": -REMEDY_GRANT_GOLD}, "result": "", "loyalty_action": "grant", "loyalty_target": key},
		{"label": "Castigar", "result": "", "loyalty_action": "punish", "loyalty_target": key},
		{"label": "Ignorarlo", "result": "Las quejas siguen."},
	]
	var event := {"id": "lealtad_aviso", "title": "Lealtad en duda",
		"text": "%s se queja de ti (lealtad %d). Si nada cambia, podría traicionarte." % [who, loyalty_of(key)],
		"options": options}
	if not castle:
		event["speaker"] = key
	return event

func _on_option_chosen(event: Dictionary, option: Dictionary) -> void:
	var action: String = option.get("loyalty_action", "")
	if action.is_empty():
		return
	event["_extra_result"] = remedy(action, str(option.get("loyalty_target", "")))

func remedy(action: String, key: String) -> String:
	var player: Character = GameManager.player_character
	var who := _display(key)
	var r := RelationsData.get_relation(key)
	match action:
		"talk":
			change(key, roundi(CAUSES.talk * float(SPEED.get(_personality(key), 1.0))) + player.charisma / TALK_CHARISMA_DIV)
		"pay", "grant":
			note(key, action)
		"punish":
			warned.erase(key)   # el miedo aplaza la traición: haría falta otro aviso
			if key.begins_with(CASTLE_PREFIX):
				var c: Castle = MapData.get_castle_by_id(key.trim_prefix(CASTLE_PREFIX))
				if c != null:
					c.garrison_size = maxi(1, c.garrison_size - int(c.garrison_size * PUNISH_GARRISON))
				change(key, PUNISH_FEAR)
			else:
				if r != null:
					r.adjust_affection(PUNISH_AFFECTION)
				change(key, PUNISH_FEAR if _personality(key) in FEARFUL else PUNISH_RESENT)
		"plot_jail":
			return _cut_ties(key, "Apartas a %s de tu casa." % key)
		"plot_pardon":
			player.gain_honor(PLOT_PARDON_HONOR)
			change(key, PLOT_PARDON_LOYALTY)
		"plot_bribe":
			loyalty[key] = RECOVER_AT
	return "%s: lealtad %d." % [who, loyalty_of(key)]

# --- Traiciones ---

## Traición según quién sea. Devuelve el texto (también va a la crónica y a un aviso).
func betray(key: String) -> String:
	var text := ""
	if key.begins_with(CASTLE_PREFIX):
		text = _castle_betrayal(key)
	elif CaptureData.is_serf(key):
		text = _serf_escape(key)
	elif RelationsData.is_spouse(key) or RelationsData.is_concubine(key):
		text = _poison(key) if randf() < POISON_CHANCE else _plot(key)
	elif vassals().any(func(v: Relationship) -> bool: return v.person_name == key):
		text = _sell_info(key) if randf() < SELL_INFO_CHANCE else _plot(key)
	else:
		text = _sell_info(key) if randf() < SELL_INFO_CHANCE else _desert(key)
	if not text.is_empty():
		WorldEvents.record(text, "", true)
		WorldEvents.notify("Traición", text)
	loyalty_changed.emit()
	return text

func _leave_retinue(key: String) -> void:
	RelationsData.retinue.erase(key)
	RelationsData.occupations.erase(key)
	if RelationsData.designated_champion == key:
		RelationsData.designated_champion = ""
	loyalty.erase(key)
	RelationsData.relations_changed.emit()

func _desert(key: String) -> String:
	var player: Character = GameManager.player_character
	var stolen := mini(DESERT_GOLD_MAX, int(player.gold * DESERT_GOLD_SHARE))
	player.gold -= stolen
	_leave_retinue(key)
	return "%s deserta de tu séquito llevándose %d de oro." % [key, stolen]

func _serf_escape(key: String) -> String:
	CaptureData.serfs.erase(key)
	_leave_retinue(key)
	CaptureData.captures_changed.emit()
	return "%s se fuga aprovechando la noche." % key

func _poison(key: String) -> String:
	var player: Character = GameManager.player_character
	player.current_health = maxi(1, player.current_health - POISON_DAMAGE)
	_cut_ties(key, "")
	return "%s intenta envenenarte y huye (vida −%d)." % [key, POISON_DAMAGE]

## Se une a una conjura contra ti: lo descubres y decides (evento).
func _plot(key: String) -> String:
	GameManager.queue_event({"id": "lealtad_conjura", "title": "Conjura descubierta", "speaker": key,
		"text": "%s conspira contra ti con tus enemigos." % key, "options": [
			{"label": "Apartarle de tu casa", "result": "", "loyalty_action": "plot_jail", "loyalty_target": key},
			{"label": "Perdonar", "result": "", "loyalty_action": "plot_pardon", "loyalty_target": key},
			{"label": "Comprar su silencio (%d)" % REMEDY_GRANT_GOLD, "requires": {"gold": REMEDY_GRANT_GOLD},
				"effects": {"gold": -REMEDY_GRANT_GOLD}, "result": "", "loyalty_action": "plot_bribe", "loyalty_target": key},
		]})
	return "%s se une a una conjura contra ti." % key

func _sell_info(key: String) -> String:
	var enemy: Relationship = null
	var vassal_names: Array = vassals().map(func(v: Relationship) -> String: return v.person_name)
	for r: Relationship in RelationsData.lords():
		if r.person_name != key and not r.person_name in vassal_names and (enemy == null or r.affinity < enemy.affinity):
			enemy = r
	var home: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
	if home != null:
		home.garrison_size = maxi(1, home.garrison_size - int(home.garrison_size * SELL_INFO_GARRISON))
	if enemy != null:
		enemy.adjust_grudge(SELL_INFO_GRUDGE)
	return "%s vende tus secretos a %s." % [key, enemy.person_name if enemy != null else "tus enemigos"]

func _castle_betrayal(key: String) -> String:
	var c: Castle = MapData.get_castle_by_id(key.trim_prefix(CASTLE_PREFIX))
	if c == null:
		return ""
	if c.castle_id != GameManager.home_castle_id and c.original_kingdom >= 0 and c.original_kingdom != c.kingdom:
		loyalty.erase(key)
		ArmyData._rebel(c)
		return "La guarnición de %s se rinde a sus antiguos señores." % c.castle_name
	var lost := int(c.garrison_size * GARRISON_DESERT)
	var stolen := int(c.gold * CASTLE_GOLD_STOLEN)
	c.garrison_size = maxi(1, c.garrison_size - lost)
	c.gold -= stolen
	loyalty[key] = WARN_AT
	return "Motín en %s: desertan %d soldados con %d de oro." % [c.castle_name, lost, stolen]

## Rompe con alguien de tu casa: cónyuge (fin del matrimonio), amante, séquito o vasallo.
func _cut_ties(key: String, text: String) -> String:
	var r := RelationsData.get_relation(key)
	if RelationsData.is_spouse(key) and r != null:
		DynastyData._end_marriage(r)
	RelationsData.concubines.erase(key)
	if r != null and r.kind == Relationship.Kind.SENOR:
		r.adjust(-PLOT_JAIL_AFFINITY)
	_leave_retinue(key)
	return text

# --- Guardado ---

func save_state() -> Dictionary:
	return {"loyalty": loyalty.duplicate(), "warned": warned.duplicate(), "last_honor": _last_honor, "last_victory": _last_victory}

func load_state(data: Dictionary) -> void:
	loyalty = {}
	for k in data.get("loyalty", {}):
		loyalty[str(k)] = int(data.loyalty[k])
	warned = {}
	for k in data.get("warned", {}):
		warned[str(k)] = int(data.warned[k])
	_last_honor = int(data.get("last_honor", -1))
	_last_victory = int(data.get("last_victory", RelationsData.last_victory_month))
