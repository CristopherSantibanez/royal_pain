extends Node
# Autoload — registrar como "TravelData"
# Dónde está el jugador y cómo se mueve: su ficha viaja de castillo en castillo por las rutas del mapa.
# Viajar a un castillo vecino gasta 1 acción (2 en invierno, salvo Paso Invernal) y en el camino
# puede salir un encuentro (ver RoadEncounterCatalog). En otros castillos: gente del lugar, armería,
# torneos locales, audiencia con el señor y jurar lealtad. Desde lejos se gobierna tu castillo con límites.
# Guarda su estado (SaveSystem.MODULES).

const RoadEncounterCatalog = preload("res://scripts/resources/road_encounter_catalog.gd")

signal location_changed(castle_id: String)

const HOP_COST := 1
const WINTER_HOP_COST := 2

# Encuentros en el camino: probabilidad por tramo recorrido.
const ENCOUNTER_BASE := 0.18
const ENCOUNTER_WINTER_BONUS := 0.10
const ENCOUNTER_WAR_BONUS := 0.17        # el tramo toca un reino en guerra u hostil contigo
const ENCOUNTER_WILDS_BONUS := 0.05      # tierras sin señor
const ENCOUNTER_MAX := 0.55

# Gobernar desde lejos: las gestiones que se pueden hacer por carta cuestan una acción más.
const REMOTE_EXTRA_ACTIONS := 1

# Audiencia con un señor (1 acción, una vez al mes por señor).
const AUDIENCE_MIN_AFFINITY := -30       # por debajo no te recibe
const AUDIENCE_LOW_RANK_FAME := 15       # bajo Caballero (mercenarios) hace falta algo de fama; campesinos y soldados no piden audiencia
const AUDIENCE_RESPECT_BASE := 6         # + Carisma / 3 de afinidad al presentar tus respetos

# Jurar lealtad a otro señor.
const FEALTY_MIN_AFFINITY := 10          # el señor tiene que confiar en ti...
const FEALTY_MIN_FAME := 40              # ...o tu fama hablar por ti
const FEALTY_HONOR_COST := 15            # romper tu juramento anterior
const FEALTY_TREASON_FACTOR := 2         # el doble si te pasas al enemigo en plena guerra
const FEALTY_OLD_LIEGE_AFFINITY := -50
const FEALTY_NEW_LORD_AFFINITY := 15
const FEALTY_COOLDOWN_MONTHS := 12

# Torneos locales: uno por castillo y año, en la temporada de torneos.
var local_tournament_years := {}         # castle_id -> año del último torneo disputado allí

var location_id := ""
var pending_encounter: Dictionary = {}   # {id, from, to} mientras no se resuelva
var hops_travelled := 0
var last_fealty_month := -1000
var _audience_months := {}               # nombre del señor -> mes (months_elapsed) de la última audiencia

func _ready() -> void:
	GameManager.game_started.connect(func(_character: Character): reset())
	if DynastyData.has_signal("family_changed"):
		DynastyData.family_changed.connect(_check_location)

func reset() -> void:
	location_id = GameManager.home_castle_id
	pending_encounter = {}
	hops_travelled = 0
	last_fealty_month = -1000
	local_tournament_years.clear()
	_audience_months.clear()
	location_changed.emit(location_id)

## Si la ubicación ya no existe (partida antigua, sucesión...), el jugador vuelve a casa.
func _check_location() -> void:
	if MapData.get_castle_by_id(location_id) == null:
		location_id = GameManager.home_castle_id
		location_changed.emit(location_id)

# --- Consultas ---

func current_castle_id() -> String:
	if location_id.is_empty() or MapData.get_castle_by_id(location_id) == null:
		return GameManager.home_castle_id
	return location_id

func current_castle() -> Castle:
	return MapData.get_castle_by_id(current_castle_id())

func is_at(castle_id: String) -> bool:
	return current_castle_id() == castle_id

func is_at_home() -> bool:
	return is_at(GameManager.home_castle_id)

## Reino de la zona donde estás: su gente es la de «Tu zona».
func zone_kingdom() -> int:
	var c := current_castle()
	return c.kingdom if c != null else GameManager.player_kingdom

func hop_cost(month: int = GameManager.current_month) -> int:
	if SkillEffects.has_unique(GameManager.player_character, SkillEffects.UNIQUE_BABIECA):
		return HOP_COST
	return WINTER_HOP_COST if SkillEffects.march_turns(month, GameManager.player_character) > 1 else HOP_COST

## Camino más corto (castillos a recorrer, sin incluir el de partida). Vacío si no hay o ya estás allí.
func path_to(target_id: String, from_id: String = "") -> Array[String]:
	var start := from_id if not from_id.is_empty() else current_castle_id()
	var result: Array[String] = []
	if start == target_id or MapData.get_castle_by_id(target_id) == null:
		return result
	var came_from := {start: ""}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		if id == target_id:
			break
		var c := MapData.get_castle_by_id(id)
		if c == null:
			continue
		for n: String in c.connected_castle_ids:
			if not came_from.has(n):
				came_from[n] = id
				queue.append(n)
	if not came_from.has(target_id):
		return result
	var step := target_id
	while step != start:
		result.push_front(step)
		step = came_from[step]
	return result

## Por qué no puedes viajar ahora hacia ese castillo ("" si puedes).
func travel_blocker(target_id: String) -> String:
	if not GameManager.is_game_active:
		return "No hay una partida activa."
	if not pending_encounter.is_empty():
		return "Primero resuelve lo que te ha salido al paso en el camino."
	if CaptureData.is_captive():
		return "Estás preso: no puedes viajar."
	if is_at(target_id):
		return "Ya estás aquí."
	if path_to(target_id).is_empty():
		return "No hay camino hasta allí."
	if GameManager.actions_remaining < hop_cost():
		return "Viajar al siguiente castillo cuesta %d %s (te quedan %d)." % [hop_cost(), "acción" if hop_cost() == 1 else "acciones", GameManager.actions_remaining]
	return ""

## Avanza un tramo hacia el castillo indicado (al vecino del camino más corto).
## Devuelve {ok, text, arrived_id, encounter (evento o {})}.
func travel_toward(target_id: String) -> Dictionary:
	var blocker := travel_blocker(target_id)
	if not blocker.is_empty():
		return {"ok": false, "text": blocker, "arrived_id": current_castle_id(), "encounter": {}}
	var from_id := current_castle_id()
	var next_id: String = path_to(target_id)[0]
	for i in hop_cost():
		GameManager.consume_action()
	location_id = next_id
	hops_travelled += 1
	var dest := MapData.get_castle_by_id(next_id)
	var text := "Llegas a %s." % MapData.place_label(dest)
	var encounter := {}
	if randf() < encounter_chance(from_id, next_id):
		var id := RoadEncounterCatalog.pick(_encounter_context(from_id, next_id))
		if not id.is_empty():
			pending_encounter = {"id": id, "from": from_id, "to": next_id}
			encounter = encounter_event()
	location_changed.emit(location_id)
	return {"ok": true, "text": text, "arrived_id": next_id, "encounter": encounter}

func encounter_chance(from_id: String, to_id: String) -> float:
	var chance := ENCOUNTER_BASE
	if SkillEffects.is_winter(GameManager.current_month):
		chance += ENCOUNTER_WINTER_BONUS
	if _war_zone(from_id, to_id):
		chance += ENCOUNTER_WAR_BONUS
	var dest := MapData.get_castle_by_id(to_id)
	if dest != null and dest.kingdom == KingdomEnums.Kingdom.NEUTRAL:
		chance += ENCOUNTER_WILDS_BONUS
	if SkillEffects.has_unique(GameManager.player_character, SkillEffects.UNIQUE_SAFE_ROADS):
		chance *= SkillEffects.SAFE_ROADS_FACTOR
	return minf(chance, ENCOUNTER_MAX)

func _war_zone(from_id: String, to_id: String) -> bool:
	var hostile := RelationsData.hostile_kingdoms()
	for id in [from_id, to_id]:
		var c := MapData.get_castle_by_id(id)
		if c != null and c.kingdom != GameManager.player_kingdom and c.kingdom in hostile:
			return true
	return false

func _encounter_context(from_id: String, to_id: String) -> Dictionary:
	var dest := MapData.get_castle_by_id(to_id)
	var enemy := -1
	for id in [to_id, from_id]:
		var c := MapData.get_castle_by_id(id)
		if c != null and c.kingdom != GameManager.player_kingdom and c.kingdom in RelationsData.hostile_kingdoms():
			enemy = c.kingdom
			break
	return {"winter": SkillEffects.is_winter(GameManager.current_month), "war": enemy >= 0,
		"enemy_kingdom": enemy, "player": GameManager.player_character,
		"place": dest.castle_name if dest != null else ""}

func has_pending_encounter() -> bool:
	return not pending_encounter.is_empty()

## El encuentro pendiente visto como un evento (title, text, options).
func encounter_event() -> Dictionary:
	if pending_encounter.is_empty():
		return {}
	var enemy := -1
	var from := MapData.get_castle_by_id(str(pending_encounter.get("from", "")))
	var to := MapData.get_castle_by_id(str(pending_encounter.get("to", "")))
	for c in [to, from]:
		if c != null and c.kingdom != GameManager.player_kingdom and c.kingdom in RelationsData.hostile_kingdoms():
			enemy = c.kingdom
			break
	return RoadEncounterCatalog.as_event(str(pending_encounter.id), {
		"place": to.castle_name if to != null else "el camino",
		"kingdom": KingdomEnums.kingdom_name(enemy) if enemy >= 0 else "un reino vecino",
		"player": GameManager.player_character})

## Resuelve el encuentro eligiendo una opción (no gasta acción: ya la gastó el viaje).
## Devuelve {ok, text, fight, title}.
func resolve_encounter(option_index: int) -> Dictionary:
	var event := encounter_event()
	var player: Character = GameManager.player_character
	if event.is_empty() or player == null:
		return {"ok": false, "text": "", "fight": {}, "title": ""}
	var options: Array = event.options
	if option_index < 0 or option_index >= options.size():
		return {"ok": false, "text": "", "fight": {}, "title": ""}
	var home := MapData.get_castle_by_id(GameManager.home_castle_id)
	var option: Dictionary = options[option_index]
	if not EventCatalog.can_choose(option, player, home):
		return {"ok": false, "text": EventCatalog.requirement_text(option), "fight": {}, "title": ""}
	var text := EventCatalog.apply_option(event, option_index, player, home)
	WorldEvents.record("%s: %s. %s" % [event.title, option.get("label", ""), text.get_slice("\n", 0)], str(pending_encounter.get("to", "")), true)
	pending_encounter = {}
	return {"ok": true, "text": text, "fight": option.get("fight", {}), "title": event.title}

# --- Gobernar desde lejos ---

## Estás gestionando tu castillo sin estar en él.
func is_remote(castle: Castle) -> bool:
	return castle != null and castle.castle_id == GameManager.home_castle_id and not is_at_home() \
		and GameManager.player_character != null and GameManager.player_character.role != Character.Role.INAFILIADO

## Puedes entrar a un castillo si estás en él, o al tuyo desde lejos (con límites).
func can_enter(castle: Castle) -> String:
	if castle == null or not GameManager.is_game_active:
		return "No disponible."
	if is_at(castle.castle_id):
		return ""
	# Sin tierra no hay castillo que gobernar desde lejos.
	if castle.castle_id == GameManager.home_castle_id and GameManager.player_character.role != Character.Role.INAFILIADO:
		return ""
	return "Tienes que viajar hasta %s para entrar." % castle.castle_name

# --- Torneos locales ---

func local_tournament_blocker(castle: Castle) -> String:
	var player: Character = GameManager.player_character
	if castle == null or player == null:
		return "No disponible."
	if not GameManager.current_month in CombatSetup.TOURNAMENT_MONTHS:
		return "Los torneos se celebran de abril a septiembre."
	if int(local_tournament_years.get(castle.castle_id, 0)) == GameManager.current_year:
		return "Ya justaste en el torneo de %s este año." % castle.castle_name
	if not player.can_fight_duels():
		return "Tu rango no te permite justar."
	if player.is_wounded():
		return "Estás demasiado herido para justar."
	if player.gold < CombatSetup.TOURNAMENT_ENTRY_FEE:
		return "Necesitas %d de oro para la inscripción." % CombatSetup.TOURNAMENT_ENTRY_FEE
	return ""

func mark_local_tournament(castle: Castle) -> void:
	local_tournament_years[castle.castle_id] = GameManager.current_year

# --- Audiencia con el señor del castillo ---

func lord_relation(castle: Castle) -> Relationship:
	if castle == null or castle.owner_name == RelationsData.NO_LORD:
		return null
	var r := RelationsData.get_relation(castle.owner_name)
	return r if r != null and r.kind == Relationship.Kind.SENOR else null

## Por qué no te reciben ("" si puedes pedir audiencia). No mira las acciones.
func audience_blocker(castle: Castle) -> String:
	var player: Character = GameManager.player_character
	var lord := lord_relation(castle)
	if player == null or lord == null:
		return "Este castillo no tiene un señor que te reciba."
	if lord.person_name == player.full_name():
		return "Este castillo es tuyo."
	var rank_reason: String = RelationsData.lord_rank_blocker()
	if not rank_reason.is_empty():
		return rank_reason
	if not is_at(castle.castle_id):
		return "Tienes que estar en %s." % castle.castle_name
	if int(_audience_months.get(lord.person_name, -1)) == GameManager.months_elapsed():
		return "%s ya te recibió este mes." % lord.person_name
	if lord.at_war:
		return "Estáis en guerra: %s no te recibiría más que encadenado." % lord.person_name
	if lord.affinity < AUDIENCE_MIN_AFFINITY:
		return "%s no quiere ni oír tu nombre (afinidad %d)." % [lord.person_name, lord.affinity]
	if player.rank() < Character.rank_of(Character.Role.CABALLERO) and player.fame < AUDIENCE_LOW_RANK_FAME:
		return "Un señor no recibe a cualquiera: necesitas %d de fama (tienes %d) o ser Caballero." % [AUDIENCE_LOW_RANK_FAME, player.fame]
	return ""

## Pide la audiencia (gasta 1 acción). Devuelve {ok, text}.
func request_audience(castle: Castle) -> Dictionary:
	var blocker := audience_blocker(castle)
	if not blocker.is_empty():
		return {"ok": false, "text": blocker}
	if not GameManager.consume_action():
		return {"ok": false, "text": "No te quedan acciones este mes."}
	var lord := lord_relation(castle)
	_audience_months[lord.person_name] = GameManager.months_elapsed()
	return {"ok": true, "text": "%s te recibe en su salón de %s." % [lord.person_name, castle.castle_name]}

## Opciones dentro de la audiencia (ya pagada). Devuelve el texto del resultado.
func audience_respects(castle: Castle) -> String:
	var player: Character = GameManager.player_character
	var lord := lord_relation(castle)
	var gain: int = AUDIENCE_RESPECT_BASE + player.charisma / 3
	lord.adjust(gain)
	RelationsData.relations_changed.emit()
	return "Presentas tus respetos a %s. Afinidad %+d (ahora %d)." % [lord.person_name, gain, lord.affinity]

func audience_news(castle: Castle) -> String:
	var lord := lord_relation(castle)
	var parts: Array[String] = []
	for c: Castle in MapData.castles:
		if c.kingdom == castle.kingdom:
			parts.append("%s: %d soldados, %d de oro" % [c.castle_name, c.garrison_size, c.gold])
	var text := "%s te habla de su reino. %s." % [lord.person_name, "; ".join(parts)]
	WorldEvents.record("Audiencia en %s: %s" % [castle.castle_name, "; ".join(parts)], castle.castle_id, true)
	return text

## Pide un encargo al señor (lo da el sistema de encargos con el señor como quien lo encarga).
func audience_mission(castle: Castle) -> String:
	var player: Character = GameManager.player_character
	var lord := lord_relation(castle)
	if not MissionData.has_method("_mission_offer"):
		return "%s no tiene nada que encargarte." % lord.person_name
	var offer: Dictionary = MissionData.call("_mission_offer", player)
	if offer.is_empty():
		return "%s no tiene ahora ningún encargo para alguien de tu rango." % lord.person_name
	var m: Dictionary = offer.options[0].mission_accept
	m["giver"] = lord.person_name
	MissionData.accept(m)
	return "%s te encarga: %s. Lo tienes en «Encargos»." % [lord.person_name, m.get("title", "un encargo")]

# --- Jurar lealtad a otro señor ---

func fealty_blocker(castle: Castle) -> String:
	var player: Character = GameManager.player_character
	var lord := lord_relation(castle)
	if player == null or lord == null:
		return "Este castillo no tiene un señor al que jurar lealtad."
	if player.role == Character.Role.REGENTE:
		return "Una corona no se arrodilla ante nadie."
	if lord.person_name == player.full_name():
		return "No puedes jurarte lealtad a ti mismo."
	if not is_at(castle.castle_id):
		return "El juramento se hace en persona: viaja a %s." % castle.castle_name
	if castle.kingdom == GameManager.player_kingdom and not player.is_mercenary() and player.role != Character.Role.INAFILIADO:
		return "Ya sirves a %s." % KingdomEnums.kingdom_name(castle.kingdom)
	if GameManager.months_elapsed() - last_fealty_month < FEALTY_COOLDOWN_MONTHS:
		return "Cambiaste de señor hace poco: nadie confiaría en otro juramento tuyo tan pronto."
	if ArmyData.armies.any(func(a: Army) -> bool: return ArmyData.is_player_army(a) and a.pending_battle):
		return "No puedes cambiar de bando en mitad de un asedio."
	if lord.at_war:
		return "Estás en guerra con %s." % lord.person_name
	if not player.role in [Character.Role.CAMPESINO, Character.Role.INAFILIADO] and lord.affinity < FEALTY_MIN_AFFINITY and player.fame < FEALTY_MIN_FAME:
		return "%s no se fía de ti: necesitas %d de afinidad (tienes %d) o %d de fama." % [
			lord.person_name, FEALTY_MIN_AFFINITY, lord.affinity, FEALTY_MIN_FAME]
	return ""

## Honor que te costaría el juramento ahora (0 si no rompes ninguno).
func fealty_honor_cost(castle: Castle) -> int:
	var player: Character = GameManager.player_character
	if player == null or player.role in [Character.Role.CAMPESINO, Character.Role.INAFILIADO] or player.is_mercenary() or RelationsData.liege_name.is_empty():
		return 0
	var cost := FEALTY_HONOR_COST
	var old_liege := RelationsData.get_relation(RelationsData.liege_name)
	if _kingdoms_at_war(GameManager.player_kingdom, castle.kingdom) or (old_liege != null and old_liege.at_war):
		cost *= FEALTY_TREASON_FACTOR
	return cost

func _kingdoms_at_war(a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and KingdomDiplomacy.at_war(RelationsData.kingdom_wars, a, b)

func fealty_preview(castle: Castle) -> String:
	var lord := lord_relation(castle)
	var cost := fealty_honor_cost(castle)
	var old := RelationsData.liege_name
	var text := "Pasarás a servir a %s en %s: este castillo será tu nuevo hogar." % [
		lord.person_name, MapData.place_label(castle)]
	if cost > 0:
		text += " Romper tu juramento con %s te costará %d de honor y su enemistad (afinidad %d)." % [old, cost, FEALTY_OLD_LIEGE_AFFINITY]
	var mine := RelationsData.castles_of(GameManager.player_character.full_name())
	if not mine.is_empty():
		text += " Tus %d castillos pasarán al reino de %s." % [mine.size(), KingdomEnums.kingdom_name(castle.kingdom)]
	return text

## Jura lealtad al señor del castillo donde estás. Devuelve {ok, text}.
func swear_fealty(castle: Castle) -> Dictionary:
	var blocker := fealty_blocker(castle)
	if not blocker.is_empty():
		return {"ok": false, "text": blocker}
	var player: Character = GameManager.player_character
	var lord := lord_relation(castle)
	var cost := fealty_honor_cost(castle)
	var old_liege_name := RelationsData.liege_name
	var old_kingdom := GameManager.player_kingdom
	var text := "Hincas la rodilla ante %s y le juras lealtad." % lord.person_name
	if cost > 0:
		player.honor = clampi(player.honor - cost, 0, 100)
		text += " Rompes tu juramento anterior: −%d de honor." % cost
	var old_liege := RelationsData.get_relation(old_liege_name)
	if old_liege != null and old_liege != lord and cost > 0:
		old_liege.adjust(FEALTY_OLD_LIEGE_AFFINITY)
		old_liege.allied = false
		text += " %s no te lo perdonará." % old_liege_name
	lord.adjust(FEALTY_NEW_LORD_AFFINITY)
	# Tus tierras propias cambian de reino contigo; tus ejércitos también.
	for c: Castle in RelationsData.castles_of(player.full_name()):
		c.kingdom = castle.kingdom
	for a: Army in ArmyData.armies:
		if ArmyData.is_player_army(a):
			a.kingdom = castle.kingdom
	# Los encargos de tu antiguo señor quedan sin cumplir.
	for m: Dictionary in MissionData.active.duplicate():
		if str(m.get("giver", "")) == old_liege_name and not old_liege_name.is_empty():
			MissionData.abandon(str(m.uid))
	GameManager.player_kingdom = castle.kingdom
	GameManager.home_castle_id = castle.castle_id
	RelationsData.liege_name = lord.person_name
	last_fealty_month = GameManager.months_elapsed()
	var rp: Script = RoleProgression
	if rp.has_method("on_fealty_sworn"):
		var extra = rp.call("on_fealty_sworn", player, castle)
		if extra is String and not extra.is_empty():
			text += " " + extra
	GameManager.refresh_actions_for_role_change()
	WorldEvents.record("%s jura lealtad a %s y pasa de %s a %s." % [player.full_name(), lord.person_name,
		KingdomEnums.kingdom_name(old_kingdom) if old_kingdom >= 0 else "ningún reino", KingdomEnums.kingdom_name(castle.kingdom)], castle.castle_id, true)
	RelationsData.relations_changed.emit()
	location_changed.emit(location_id)
	return {"ok": true, "text": text}

# --- Guardado ---

func save_state() -> Dictionary:
	return {"location_id": location_id, "pending_encounter": pending_encounter.duplicate(), "hops_travelled": hops_travelled,
		"last_fealty_month": last_fealty_month, "local_tournament_years": local_tournament_years.duplicate(),
		"audience_months": _audience_months.duplicate()}

func load_state(data: Dictionary) -> void:
	location_id = str(data.get("location_id", GameManager.home_castle_id))
	pending_encounter = {}
	var pe = data.get("pending_encounter", {})
	if pe is Dictionary and RoadEncounterCatalog.ENCOUNTERS.has(str(pe.get("id", ""))):
		pending_encounter = {"id": str(pe.id), "from": str(pe.get("from", "")), "to": str(pe.get("to", ""))}
	hops_travelled = int(data.get("hops_travelled", 0))
	last_fealty_month = int(data.get("last_fealty_month", -1000))
	local_tournament_years = {}
	for k in data.get("local_tournament_years", {}):
		local_tournament_years[str(k)] = int(data.local_tournament_years[k])
	_audience_months = {}
	for k in data.get("audience_months", {}):
		_audience_months[str(k)] = int(data.audience_months[k])
	_check_location()
	location_changed.emit(current_castle_id())
