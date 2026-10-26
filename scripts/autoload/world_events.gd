extends Node
# Autoload — registrar como "WorldEvents"
# Vida del mundo fuera del jugador: eventos globales aleatorios y noticias importantes de
# otros reinos (matrimonios, muertes, guerras). Guarda su estado en la partida (ver SaveSystem.MODULES).
#
# Las noticias van a la crónica (ArmyData.turn_events); las importantes además se avisan
# con una notificación en el mapa (cola: notifications / pop_notification).

const WorldEventCatalog = preload("res://scripts/resources/world_event_catalog.gd")

signal notification_added

# --- Balance ---
const WORLD_EVENT_CHANCE := 0.2          # prob. mensual de un suceso del mundo (sin decisión)
const PLAYER_EVENT_CHANCE := 0.08        # prob. mensual de un suceso global que pide decisión
const LORD_DEATH_CHANCE := 0.005         # por señor y mes (~6% al año)
const LORD_MARRIAGE_CHANCE := 0.01       # por señor soltero y mes
const MARRIAGE_ALLIANCE_CHANCE := 0.5    # una boda entre casas de reinos en paz puede sellar una alianza
const INITIAL_WARS := 2                  # guerras entre reinos de la IA al empezar
const INITIAL_ALLIANCES := 2

const DEATH_CAUSES := ["unas fiebres", "una caída del caballo", "una vieja herida de guerra", "la peste",
	"un mal de pecho", "un veneno, según murmuran algunos", "una cacería que salió mal"]

var notifications: Array[Dictionary] = []    # [{title, text}] pendientes de mostrar
var chronicle: Array[Dictionary] = []        # todas las noticias de la partida: {m, y, text, castle_id, personal}
const CHRONICLE_MAX := 600
var married_lords: Dictionary = {}           # señor -> nombre de su cónyuge
var deferred_event: Dictionary = {}          # suceso global con decisión que esperó a un mes libre

func _ready() -> void:
	GameManager.game_started.connect(func(_character: Character): reset())
	GameManager.turn_advanced.connect(_on_month_passed)

func reset() -> void:
	notifications.clear()
	chronicle.clear()
	married_lords.clear()
	deferred_event = {}
	_initial_diplomacy()

## Guerras y alianzas iniciales entre reinos de la IA (cada partida, distintas).
func _initial_diplomacy() -> void:
	var neighbors := KingdomDiplomacy.kingdom_neighbors(MapData.castles)
	var pairs: Array = []
	for k in neighbors.keys():
		if k == GameManager.player_kingdom or k == KingdomEnums.Kingdom.NEUTRAL:
			continue
		for o in neighbors[k]:
			if o > k and o != GameManager.player_kingdom and o != KingdomEnums.Kingdom.NEUTRAL:
				pairs.append([k, o])
	pairs.shuffle()
	var month := GameManager.months_elapsed()
	for i in range(mini(INITIAL_WARS, pairs.size())):
		KingdomDiplomacy.declare_war(RelationsData.kingdom_wars, RelationsData.kingdom_alliances, pairs[i][0], pairs[i][1], month)
	for i in range(INITIAL_WARS, mini(INITIAL_WARS + INITIAL_ALLIANCES, pairs.size())):
		RelationsData.kingdom_alliances[KingdomDiplomacy.pair_key(pairs[i][0], pairs[i][1])] = true

# --- Crónica ---

## Apunta una noticia en la crónica de la partida. personal: decisiones y sucesos del propio jugador.
func record(text: String, castle_id: String = "", personal: bool = false) -> void:
	if text.strip_edges().is_empty():
		return
	chronicle.append({"m": GameManager.current_month, "y": GameManager.current_year,
		"text": text.strip_edges(), "castle_id": castle_id, "personal": personal})
	if chronicle.size() > CHRONICLE_MAX:
		chronicle = chronicle.slice(chronicle.size() - CHRONICLE_MAX)

# --- Notificaciones ---

func notify(title: String, text: String) -> void:
	notifications.append({"title": title, "text": text})
	notification_added.emit()

func has_notifications() -> bool:
	return not notifications.is_empty()

func pop_notification() -> Dictionary:
	return notifications.pop_front() if not notifications.is_empty() else {}

# Noticia en la crónica; si es importante, también aviso en el mapa.
func _news(text: String, castle_id: String, important_title: String = "") -> void:
	ArmyData._add_event(text, castle_id)
	if not important_title.is_empty():
		notify(important_title, text)

# --- Paso del mes ---

func _on_month_passed(_month: int, _year: int) -> void:
	if not GameManager.is_game_active:
		return
	if not GameManager.last_annual_event.is_empty():
		record("Año nuevo: " + GameManager.last_annual_event)
	_world_event()
	_lords_life()
	_player_global_event()
	ArmyData.events_changed.emit()

func _world_event() -> void:
	if randf() >= WORLD_EVENT_CHANCE:
		return
	var e := WorldEventCatalog.pick_world_event(GameManager.current_month)
	if e.is_empty():
		return
	var kingdoms := _ai_and_player_kingdoms()
	if kingdoms.is_empty():
		return
	var kingdom: int = kingdoms.pick_random()
	var text := WorldEventCatalog.apply_world_event(e, MapData.castles, kingdom)
	var touches_player: bool = e.scope == "all" or kingdom == GameManager.player_kingdom
	_news(text, _castle_of(kingdom), "Noticias del reino" if touches_player else "")

func _player_global_event() -> void:
	var player: Character = GameManager.player_character
	if player == null:
		return
	var e := deferred_event
	if e.is_empty() and randf() < PLAYER_EVENT_CHANCE:
		e = WorldEventCatalog.pick_player_event(player.role)
	if e.is_empty():
		return
	if GameManager.pending_event.is_empty():
		GameManager.pending_event = e
		deferred_event = {}
	else:
		deferred_event = e   # una sola decisión por mes: espera al siguiente

# Señores que mueren (con heredero) o se casan.
func _lords_life() -> void:
	for r: Relationship in RelationsData.lords():
		if r.character == null or RelationsData.castles_of(r.person_name).is_empty():
			continue
		if randf() < LORD_DEATH_CHANCE:
			_lord_dies(r)
		elif not married_lords.has(r.person_name) and randf() < LORD_MARRIAGE_CHANCE:
			_lord_marries(r)

func _lord_dies(r: Relationship) -> void:
	var old_name := r.person_name
	var castles: Array[Castle] = RelationsData.castles_of(old_name)
	var kingdom: int = castles[0].kingdom
	var female := randf() < 0.5
	var gender := CharacterEnums.Gender.FEMENINO if female else CharacterEnums.Gender.MASCULINO
	var crowned := old_name.begins_with("Rey ") or old_name.begins_with("Reina ")
	var title := ("Reina" if female else "Rey") if crowned else ("Lady" if female else "Lord")
	var heir_name := "%s %s %s" % [title, CharacterLoader.random_first_name(gender), RelationsData.family_name_of(old_name)]
	var portrait := ""
	portrait = RelationsData.take_free_portrait(gender)
	var heir := CharacterLoader.make_random_character(r.character.role, gender, portrait, heir_name)
	var was_liege := old_name == RelationsData.liege_name
	var was_family := old_name == RelationsData.spouse_family
	married_lords.erase(old_name)
	RelationsData.replace_lord(old_name, heir)
	var text := "%s muere por %s. Le sucede %s al frente de %s." % [old_name, DEATH_CAUSES.pick_random(), heir_name, KingdomEnums.kingdom_name(kingdom)]
	if was_liege:
		text += " Tu nuevo señor aún no te conoce: la lealtad habrá que ganársela de nuevo."
	elif was_family:
		text += " La familia de tu cónyuge está de luto."
	_news(text, castles[0].castle_id, "Muere un señor")

func _lord_marries(r: Relationship) -> void:
	var others: Array[Relationship] = []
	for o: Relationship in RelationsData.lords():
		if o != r and o.kingdom != r.kingdom and not RelationsData.castles_of(o.person_name).is_empty():
			others.append(o)
	if others.is_empty():
		return
	var house: Relationship = others.pick_random()
	var spouse_gender := CharacterEnums.Gender.MASCULINO if RelationsData.lord_gender(r.person_name) == CharacterEnums.Gender.FEMENINO else CharacterEnums.Gender.FEMENINO
	var spouse := "%s %s" % [CharacterLoader.random_first_name(spouse_gender), RelationsData.family_name_of(house.person_name)]
	married_lords[r.person_name] = spouse
	var a: int = r.kingdom
	var b: int = house.kingdom
	var text := "%s se casa con %s, de la casa de %s." % [r.person_name, spouse, house.person_name]
	var ai_pair := a != GameManager.player_kingdom and b != GameManager.player_kingdom
	if ai_pair and not KingdomDiplomacy.at_war(RelationsData.kingdom_wars, a, b) and randf() < MARRIAGE_ALLIANCE_CHANCE:
		RelationsData.kingdom_alliances[KingdomDiplomacy.pair_key(a, b)] = true
		text += " La boda sella una alianza entre %s y %s." % [KingdomEnums.kingdom_name(a), KingdomEnums.kingdom_name(b)]
	if r.person_name == RelationsData.liege_name:
		var lady: bool = RelationsData.lord_gender(r.person_name) == CharacterEnums.Gender.FEMENINO
		text = ("Tu señora, " if lady else "Tu señor, ") + text
	_news(text, _castle_of(a), "Boda en la nobleza")

func _ai_and_player_kingdoms() -> Array[int]:
	var result: Array[int] = []
	for c: Castle in MapData.castles:
		if c.kingdom != KingdomEnums.Kingdom.NEUTRAL and not c.kingdom in result:
			result.append(c.kingdom)
	return result

func _castle_of(kingdom: int) -> String:
	for c: Castle in MapData.castles:
		if c.kingdom == kingdom:
			return c.castle_id
	return ""

# --- Guardado (datos planos) ---

func save_state() -> Dictionary:
	return {"notifications": notifications.duplicate(true), "married_lords": married_lords.duplicate(),
		"deferred_event": deferred_event.duplicate(true), "chronicle": chronicle.duplicate(true)}

func load_state(data: Dictionary) -> void:
	notifications.clear()
	for n in data.get("notifications", []):
		notifications.append(n)
	married_lords = data.get("married_lords", {}).duplicate()
	deferred_event = data.get("deferred_event", {}).duplicate(true)
	chronicle.clear()
	for e in data.get("chronicle", []):
		chronicle.append(e)
