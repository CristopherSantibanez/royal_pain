extends Node
# Viajeros entre reinos: refugiados, cortesanos con recados, gente con ambiciones y rivales que
# recorren las rutas (TravelData.path_to) un tramo por mes. Mientras viajan, su reino (Relationship.kingdom)
# es el del castillo donde están, así aparecen en «Tu zona» si coincidís (RelationsData.in_area).
# Si os cruzáis, te sale un encuentro con su retrato. Guarda su estado (SaveSystem.MODULES).

signal travelers_changed

const MAX_TRAVELERS := 5            # viajeros a la vez
const SPAWN_CHANCE := 0.5           # probabilidad mensual de que alguien se ponga en camino
const MIN_HOPS := 2
const MAX_HOPS := 6
const MEET_CHANCE := 0.7            # probabilidad de que os crucéis si coincidís
const TRADE_GOLD := 10
const TRADE_AFFINITY := 2
const REASON_LABELS := {"refugee": "Refugiado", "errand": "De recado", "ambition": "Busca fortuna",
	"rival": "Te busca", "wander": "Errante"}

## Cada viajero: {name, reason, at, from, dest, met}
var travelers: Array[Dictionary] = []
var pending_conversation := ""      # el mapa abre la conversación al cerrar el encuentro
var _last_hops := 0

func _ready() -> void:
	GameManager.game_started.connect(func(_c: Character): reset())
	GameManager.turn_advanced.connect(_on_month_passed)
	GameManager.event_option_chosen.connect(_on_option_chosen)
	TravelData.location_changed.connect(_on_player_moved)

func reset() -> void:
	travelers.clear()
	pending_conversation = ""
	_last_hops = TravelData.hops_travelled

# --- Consultas ---

func is_traveling(person_name: String) -> bool:
	return not get_traveler(person_name).is_empty()

func get_traveler(person_name: String) -> Dictionary:
	for t in travelers:
		if t.name == person_name:
			return t
	return {}

func travelers_at(castle_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for t in travelers:
		if t.at == castle_id:
			result.append(t)
	return result

func reason_label(t: Dictionary) -> String:
	return REASON_LABELS.get(t.get("reason", ""), "Viajero")

func tooltip(t: Dictionary) -> String:
	var r := RelationsData.get_relation(str(t.name))
	var dest := MapData.get_castle_by_id(str(t.dest))
	return "%s\n%s · %s\nRumbo a %s" % [t.name, r.character.role_name() if r != null and r.character != null else "?",
		reason_label(t), dest.castle_name if dest != null else "?"]

# --- Ponerse en camino ---

func _valid(r: Relationship) -> bool:
	return r != null and r.character != null and r.kingdom >= 0 and RelationsData.sociable(r) \
		and r.kind != Relationship.Kind.CONYUGE and not r.person_name in RelationsData.retinue \
		and r.person_name != RelationsData.spouse_name and r.person_name != RelationsData.liege_name \
		and not CaptureData.is_prisoner(r.person_name) \
		and not (r.kind == Relationship.Kind.SENOR and not RelationsData.castles_of(r.person_name).is_empty())

func _castles_of_kingdom(kingdom: int) -> Array[Castle]:
	var result: Array[Castle] = []
	for c: Castle in MapData.castles:
		if c.kingdom == kingdom:
			result.append(c)
	return result

## Empieza un viaje; devuelve true si hay camino. dest_id vacío = un castillo de otro reino al azar.
func start_trip(person_name: String, reason: String, from_id: String, dest_id: String = "") -> bool:
	var r := RelationsData.get_relation(person_name)
	if travelers.size() >= MAX_TRAVELERS or not _valid(r) or is_traveling(person_name) or MapData.get_castle_by_id(from_id) == null:
		return false
	if dest_id.is_empty():
		var start := MapData.get_castle_by_id(from_id)
		var options: Array[String] = []
		for c: Castle in MapData.castles:
			if c.kingdom != start.kingdom and c.kingdom >= 0 and c.kingdom != KingdomEnums.Kingdom.NEUTRAL:
				var hops := TravelData.path_to(c.castle_id, from_id).size()
				if hops >= MIN_HOPS and hops <= MAX_HOPS:
					options.append(c.castle_id)
		if options.is_empty():
			return false
		dest_id = options.pick_random()
	if TravelData.path_to(dest_id, from_id).is_empty():
		return false
	travelers.append({"name": person_name, "reason": reason, "at": from_id, "from": from_id, "dest": dest_id, "met": false})
	_settle(r, from_id)
	travelers_changed.emit()
	return true

## Quienes huyen de un reino caído salen del castillo perdido hacia su nuevo reino (RelationsData.on_castle_taken).
func add_refugees(names: Array[String], castle_id: String) -> void:
	for n in names:
		var r := RelationsData.get_relation(n)
		if r == null:
			continue
		var homes := _castles_of_kingdom(r.kingdom)
		if not homes.is_empty():
			start_trip(n, "refugee", castle_id, homes.pick_random().castle_id)

func _spawn() -> void:
	var pool: Array[Dictionary] = []
	for r: Relationship in RelationsData.relations:
		if not _valid(r) or is_traveling(r.person_name):
			continue
		var reason := "wander"
		if AmbitionData.ambitions.has(r.person_name):
			reason = "ambition"
		elif r.kind == Relationship.Kind.RIVAL_DUELO:
			reason = "rival"
		elif r.kind == Relationship.Kind.CORTESANO:
			reason = "errand"
		pool.append({"name": r.person_name, "reason": reason, "kingdom": r.kingdom})
	if pool.is_empty():
		return
	var pick: Dictionary = pool.pick_random()
	var homes := _castles_of_kingdom(int(pick.kingdom))
	if homes.is_empty():
		return
	var from_id: String = homes.pick_random().castle_id
	var dest := ""
	if pick.reason == "rival" and TravelData.current_castle_id() != from_id:
		dest = TravelData.current_castle_id()   # el rival va a buscarte
	start_trip(str(pick.name), str(pick.reason), from_id, dest)

## Su reino es el del castillo donde está: así entra en «Tu zona» si estás allí.
func _settle(r: Relationship, castle_id: String) -> void:
	var c := MapData.get_castle_by_id(castle_id)
	if r != null and c != null and c.kingdom >= 0:
		r.kingdom = c.kingdom

# --- Cada mes ---

func _on_month_passed(_month: int, _year: int) -> void:
	advance_all()
	if travelers.size() < MAX_TRAVELERS and randf() < SPAWN_CHANCE:
		_spawn()
	_check_meeting(true)

## Cada viajero avanza un tramo; quien llega se queda allí.
func advance_all() -> void:
	var keep: Array[Dictionary] = []
	for t in travelers:
		var r := RelationsData.get_relation(str(t.name))
		if not _valid(r):
			continue
		var path := TravelData.path_to(str(t.dest), str(t.at))
		if path.is_empty():
			continue   # llegó (o ya no hay camino): se queda donde está
		t.from = t.at
		t.at = path[0]
		_settle(r, t.at)
		if t.at != t.dest:
			keep.append(t)
	travelers = keep
	travelers_changed.emit()

func _on_player_moved(_castle_id: String) -> void:
	if TravelData.hops_travelled == _last_hops:
		return   # cargar o empezar partida no es viajar
	_last_hops = TravelData.hops_travelled
	_check_meeting(false)

## Si un viajero está en tu castillo (o acaba de salir de él por la ruta), te lo cruzas.
func _check_meeting(include_road: bool) -> void:
	if not GameManager.is_game_active or GameManager.player_character == null or CaptureData.is_captive():
		return
	var here := TravelData.current_castle_id()
	for t in travelers:
		if t.met or not (t.at == here or (include_road and t.from == here)):
			continue
		if randf() >= MEET_CHANCE:
			continue
		var event := meeting_event(t)
		if not event.is_empty():
			t.met = true
			GameManager.queue_event(event)
			return   # uno al mes basta

func meeting_event(t: Dictionary) -> Dictionary:
	var r := RelationsData.get_relation(str(t.name))
	var player: Character = GameManager.player_character
	if r == null or r.character == null or player == null:
		return {}
	var dest := MapData.get_castle_by_id(str(t.dest))
	var duel := {"label": "Retar a duelo", "trav_act": "duel", "start_duel": true, "effects": {}, "result": "Acepta el reto."}
	if not player.can_fight_duels() or player.is_wounded():
		duel["requires"] = {"healthy": true}
	return {"id": "viajero", "title": "Un viajero", "speaker": r.person_name, "duel_with": r.person_name,
		"trav_owner": r.person_name,
		"text": "%s (%s, %s) va camino de %s y se cruza contigo." % [r.person_name, r.character.role_name(),
			reason_label(t).to_lower(), dest.castle_name if dest != null else "otras tierras"],
		"options": [
			{"label": "Conversar", "trav_act": "talk", "effects": {}, "result": "Os apartáis a charlar."},
			{"label": "Invitar al séquito", "trav_act": "invite", "effects": {}, "result": ""},
			duel,
			{"label": "Noticias y trueque", "trav_act": "trade", "effects": {"gold": TRADE_GOLD, "affinity": TRADE_AFFINITY},
				"result": "Truecas unas baratijas."},
			{"label": "Dejarlo pasar", "trav_act": "pass", "effects": {}, "result": "Cada cual sigue su camino."},
		]}

func _on_option_chosen(event: Dictionary, option: Dictionary) -> void:
	var owner: String = event.get("trav_owner", "")
	var r := RelationsData.get_relation(owner)
	if owner.is_empty() or r == null:
		return
	var t := get_traveler(owner)
	match option.get("trav_act", ""):
		"talk":
			pending_conversation = owner
		"invite":
			var text := RelationsData.invite_to_retinue(r)
			event["_extra_result"] = text
			if owner in RelationsData.retinue:
				travelers.erase(t)
				travelers_changed.emit()
		"trade":
			var from := MapData.get_castle_by_id(str(t.get("from", "")))
			var dest := MapData.get_castle_by_id(str(t.get("dest", "")))
			if from != null and dest != null:
				event["_extra_result"] = "Viene de %s y va a %s." % [from.castle_name, dest.castle_name]

## El mapa la recoge al cerrar el encuentro.
func take_conversation() -> String:
	var n := pending_conversation
	pending_conversation = ""
	return n

# --- Guardado ---

func save_state() -> Dictionary:
	return {"travelers": travelers.duplicate(true)}

func load_state(data: Dictionary) -> void:
	travelers.clear()
	pending_conversation = ""
	_last_hops = TravelData.hops_travelled
	for t in data.get("travelers", []):
		if not t is Dictionary:
			continue
		var who := str(t.get("name", ""))
		var at := str(t.get("at", ""))
		var dest := str(t.get("dest", ""))
		if RelationsData.get_relation(who) == null or MapData.get_castle_by_id(at) == null or MapData.get_castle_by_id(dest) == null:
			continue
		travelers.append({"name": who, "reason": str(t.get("reason", "wander")), "at": at,
			"from": str(t.get("from", at)), "dest": dest, "met": bool(t.get("met", false))})
	travelers_changed.emit()
