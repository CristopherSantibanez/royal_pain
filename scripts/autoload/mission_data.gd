extends Node
# Autoload — registrar como "MissionData"
# Tareas asignadas al jugador según su rol (encargos del señor, duelos de exhibición...),
# con plazo y recompensa. Guarda su estado en la partida (ver SaveSystem.MODULES).
#
# Ciclo de un encargo: ofrecido (evento del mes, con su señor hablando) → activo → cumplido o fallido.
# Las plantillas están en MissionCatalog; aquí solo vive el estado (datos planos, para el guardado).

const MissionCatalog = preload("res://scripts/resources/mission_catalog.gd")
const XpRules = preload("res://scripts/resources/xp_rules.gd")

signal missions_changed

# --- Balance ---
const MAX_ACTIVE := 2
const OFFER_CHANCE := 0.18               # prob. mensual de que tu señor te encargue algo...
const FAME_OFFER_BONUS := 0.004         # ...más alta cuanto más famoso eres
const MAX_OFFER_CHANCE := 0.7
const MARRIAGE_OFFER_CHANCE := 0.05     # prob. mensual de que tu señor te ofrezca una boda política
const MARRIAGE_OFFER_MIN_AFFINITY := 10
const MARRIAGE_OFFER_COOLDOWN := 12     # meses entre ofertas
const MARRIAGE_DECLINE_AFFINITY := -10
const RISK_PER_STAT_POINT := 0.03
const COUNCIL := "El Consejo del Reino"  # quien encarga cuando el jugador es Regente

# --- Vasallaje ---
const DESERT_LIEGE_AFFINITY := -30        # abandonar a tu señor
const DESERT_LIEGE_HONOR := -8

var active: Array[Dictionary] = []
var completed_count := 0
var failed_count := 0
var _next_id := 1
var _last_marriage_offer := -100

func _ready() -> void:
	GameManager.game_started.connect(func(_character: Character): reset())
	GameManager.turn_advanced.connect(_on_month_passed)
	GameManager.event_option_chosen.connect(_on_option_chosen)

func reset() -> void:
	active.clear()
	completed_count = 0
	failed_count = 0
	_next_id = 1
	_last_marriage_offer = -100
	missions_changed.emit()
	# El no afiliado empieza sin señor (diferido: RelationsData también se reinicia ahora).
	_start_unaffiliated.call_deferred()

func _start_unaffiliated() -> void:
	var player: Character = GameManager.player_character
	if player != null and player.role == Character.Role.INAFILIADO:
		leave_liege()   # sin señor desde el primer día

# --- Ofertas ---

func _on_month_passed(_month: int, _year: int) -> void:
	var player: Character = GameManager.player_character
	if not GameManager.is_game_active or player == null:
		return
	for m: Dictionary in active.duplicate():
		if _is_fulfilled(m):
			_complete(m)
		elif GameManager.months_elapsed() > int(m.deadline):
			_fail(m, "Se agotó el plazo.")
	if not GameManager.pending_event.is_empty():
		return
	var marriage := _marriage_offer(player)
	if not marriage.is_empty():
		GameManager.pending_event = marriage
		return
	var chance: float = minf(OFFER_CHANCE + player.fame * FAME_OFFER_BONUS, MAX_OFFER_CHANCE)
	if active.size() < MAX_ACTIVE and randf() < chance:
		var offer := _mission_offer(player)
		if not offer.is_empty():
			GameManager.pending_event = offer
	missions_changed.emit()

func _giver_name(player: Character) -> String:
	return COUNCIL if player.role == Character.Role.REGENTE or RelationsData.liege_name.is_empty() else RelationsData.liege_name

func _mission_offer(player: Character) -> Dictionary:
	var ids: Array = active.map(func(m): return m.id)
	var m := MissionCatalog.pick(player.role, ids)
	if m.is_empty() or not _assign_target(m, player):
		return {}
	m["uid"] = str(_next_id)
	_next_id += 1
	m["giver"] = _giver_name(player)
	m["progress"] = 0
	var giver: Relationship = RelationsData.get_relation(m.giver)
	var quote := ""
	if giver != null and giver.character != null:
		quote = DialogueCatalog.line("liege_task", giver.character, player, {"player": player.full_name(), "task": m.title})
	return {
		"id": "encargo", "title": "Un encargo: %s" % m.title,
		"speaker": m.giver if giver != null else "", "quote": quote,
		"text": "%s\n\nPlazo: %d meses. Recompensa: %s." % [describe_text(m), m.months, _effects_text(m.reward)],
		"options": [
			{"label": "Aceptar el encargo", "effects": {}, "mission_accept": m,
				"result": "Aceptas el encargo. Lo encontrarás en «Encargos»."},
			{"label": "Declinarlo", "effects": {"affinity": -3},
				"result": "Declinas con respeto, pero %s toma nota." % m.giver},
		],
	}

# Elige el objetivo de los encargos que lo necesitan. false si no hay ninguno válido.
func _assign_target(m: Dictionary, player: Character) -> bool:
	match m.type:
		"exhibition":
			var knights: Array[Relationship] = []
			for r: Relationship in RelationsData.courtiers():
				if r.kingdom != GameManager.player_kingdom and r.character != null and r.character.role == Character.Role.CABALLERO:
					knights.append(r)
			if knights.is_empty():
				return false
			m["target"] = knights.pick_random().person_name
		"affinity", "alliance":
			var lords: Array[Relationship] = []
			for r: Relationship in RelationsData.lords():
				if r.person_name != RelationsData.liege_name and not r.at_war and not r.allied:
					lords.append(r)
			if lords.is_empty():
				return false
			m["target"] = lords.pick_random().person_name
	return true

func _marriage_offer(player: Character) -> Dictionary:
	var now := GameManager.months_elapsed()
	if player.rank() < Character.rank_of(Character.Role.CABALLERO) or player.role == Character.Role.REGENTE or RelationsData.is_married():
		return {}
	if now - _last_marriage_offer < MARRIAGE_OFFER_COOLDOWN or randf() >= MARRIAGE_OFFER_CHANCE:
		return {}
	var liege: Relationship = RelationsData.get_relation(RelationsData.liege_name)
	if liege == null or liege.character == null or liege.affinity < MARRIAGE_OFFER_MIN_AFFINITY:
		return {}
	_last_marriage_offer = now
	return {
		"id": "boda_politica", "title": "Una boda concertada",
		"speaker": liege.person_name,
		"quote": DialogueCatalog.line("liege_marriage_offer", liege.character, player, {"player": player.full_name()}),
		"text": "%s te ofrece la mano de alguien de su casa. Un matrimonio así te ataría a su linaje… y a su suerte." % liege.person_name,
		"options": [
			{"label": "Aceptar la boda", "effects": {}, "marriage_accept": true,
				"result": "Aceptas el honor que te ofrece tu señor."},
			{"label": "Rechazarla con cortesía", "effects": {"affinity": MARRIAGE_DECLINE_AFFINITY, "honor": -1},
				"result": "Tu señor no oculta su disgusto."},
		],
	}

func _on_option_chosen(event: Dictionary, option: Dictionary) -> void:
	if option.has("mission_accept"):
		accept(option.mission_accept)
	if option.get("marriage_accept", false):
		event["_extra_result"] = RelationsData.arrange_political_marriage(event.get("speaker", ""))

# --- Ciclo de vida ---

func accept(template: Dictionary) -> void:
	var m := template.duplicate(true)
	m["deadline"] = GameManager.months_elapsed() + int(m.months)
	m["baseline"] = _baseline(m)
	active.append(m)
	missions_changed.emit()

func _baseline(m: Dictionary) -> int:
	var castle: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
	match m.type:
		"garrison":
			return castle.garrison_size if castle != null else 0
		"castle_gold":
			return castle.gold if castle != null else 0
		"affinity":
			var r: Relationship = RelationsData.get_relation(m.get("target", ""))
			return r.affinity if r != null else 0
		"conquer":
			return _owned_castles()
	return 0

func _owned_castles() -> int:
	var player: Character = GameManager.player_character
	var n := 0
	for c: Castle in MapData.castles:
		if player != null and c.owner_name == player.full_name():
			n += 1
	return n

func _is_fulfilled(m: Dictionary) -> bool:
	var castle: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
	match m.type:
		"garrison":
			return castle != null and castle.garrison_size >= int(m.baseline) + int(m.amount)
		"castle_gold":
			return castle != null and castle.gold >= int(m.baseline) + int(m.amount)
		"affinity":
			var r: Relationship = RelationsData.get_relation(m.get("target", ""))
			return r != null and r.affinity >= int(m.baseline) + int(m.amount)
		"alliance":
			var r: Relationship = RelationsData.get_relation(m.get("target", ""))
			return r != null and r.allied
		"conquer":
			return _owned_castles() > int(m.baseline)
	return false

func _complete(m: Dictionary) -> void:
	active.erase(m)
	completed_count += 1
	var summary := _apply(m.reward, m)
	if GameManager.player_character != null:
		GameManager.player_character.gain_xp(XpRules.MISSION_COMPLETE, XpRules.SOURCE_MISSION)
		summary += " +%d exp." % GameManager.player_character.last_xp_gained
	_announce("Encargo cumplido", "«%s» cumplido. %s" % [m.title, summary])

func _fail(m: Dictionary, reason: String) -> void:
	active.erase(m)
	failed_count += 1
	var summary := _apply(m.penalty, m)
	_announce("Encargo fallido", "«%s»: %s %s" % [m.title, reason, summary])

func abandon(uid: String) -> void:
	var m := find(uid)
	if not m.is_empty():
		_fail(m, ABANDON_REASON)

func _apply(effects: Dictionary, m: Dictionary) -> String:
	var giver: Relationship = RelationsData.get_relation(m.get("giver", ""))
	var castle: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
	return EventCatalog._apply_effects(effects, GameManager.player_character, castle, giver)

func _announce(title: String, text: String) -> void:
	ArmyData._add_event(text, GameManager.home_castle_id)
	WorldEvents.notify(title, text)
	missions_changed.emit()

func find(uid: String) -> Dictionary:
	for m: Dictionary in active:
		if m.uid == uid:
			return m
	return {}

# --- Acciones desde el panel de encargos ---

## Texto del botón de acción de un encargo ("" si no se cumple desde el panel).
func action_label(m: Dictionary) -> String:
	match m.type:
		"pay": return "Entregar %d de oro" % m.amount
		"actions": return "Dedicar una acción (%d/%d)" % [m.progress, m.amount]
		"risk": return "Intentarlo (%d%%, 1 acción)" % roundi(risk_chance(m) * 100)
		"exhibition": return "Batirse ahora (1 acción)"
		"fight": return "Combatir (1 acción)"
	return ""

## Motivo por el que no se puede actuar ahora ("" si se puede).
func action_blocker(m: Dictionary) -> String:
	var player: Character = GameManager.player_character
	match m.type:
		"pay":
			return "" if player.gold >= int(m.amount) else "No tienes %d de oro." % m.amount
		"actions", "risk":
			return "" if GameManager.has_actions_remaining() else "No te quedan acciones este turno."
		"exhibition":
			if not GameManager.has_actions_remaining():
				return "No te quedan acciones este turno."
			if not player.can_fight_duels() or player.is_wounded():
				return "No estás en condiciones de batirte."
			if RelationsData.character_of(m.get("target", "")) == null:
				return "Tu rival ya no está disponible."
		"fight":
			if not GameManager.has_actions_remaining():
				return "No te quedan acciones este turno."
			if m.fight.get("type", "duel") == "duel" and (not player.can_fight_duels() or player.is_wounded()):
				return "No estás en condiciones de batirte."
			if m.fight.get("type", "duel") == "battle" and not CombatSetup.battle_blocker(player).is_empty():
				return CombatSetup.battle_blocker(player)
			var castle: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
			if m.fight.get("type", "duel") == "battle" and (castle == null or castle.garrison_size < int(m.fight.get("min_garrison", 15))):
				return "Necesitas al menos %d soldados en tu castillo." % int(m.fight.get("min_garrison", 15))
	return ""

func risk_chance(m: Dictionary) -> float:
	var player: Character = GameManager.player_character
	var stat_value: int = int(player.get(m.get("stat", "combat"))) if player != null else 10
	return clampf(float(m.get("chance", 0.5)) + (stat_value - 10) * RISK_PER_STAT_POINT, 0.05, 0.95)

## Ejecuta la acción de un encargo (pagar, dedicar acción, intentarlo). Devuelve el resultado.
func act(uid: String) -> String:
	var m := find(uid)
	if m.is_empty():
		return ""
	var blocker := action_blocker(m)
	if not blocker.is_empty():
		return blocker
	var player: Character = GameManager.player_character
	match m.type:
		"pay":
			player.gold -= int(m.amount)
			_complete(m)
			return "Entregas %d de oro. Encargo cumplido." % m.amount
		"actions":
			GameManager.consume_action()
			m.progress = int(m.progress) + 1
			var step := _apply(m.get("step", {}), m)
			if int(m.progress) >= int(m.amount):
				_complete(m)
				return "Terminas el trabajo. Encargo cumplido."
			missions_changed.emit()
			return "Avanzas en el encargo (%d/%d). %s" % [m.progress, m.amount, step]
		"risk":
			GameManager.consume_action()
			if randf() < risk_chance(m):
				_complete(m)
				return "¡Lo consigues! Encargo cumplido."
			var hurt := _apply(m.get("fail_effects", {}), m)
			_fail(m, "El intento sale mal.")
			return "El intento sale mal. %s" % hurt
	return ""

## Encargo de combate: gasta la acción y prepara el duelo o la escaramuza. Devuelve la escena ("" si no puede).
## Al terminar, CombatSetup.apply_outcome llama a resolve_fight con el resultado.
func start_fight(uid: String) -> String:
	var m := find(uid)
	if m.is_empty() or m.type != "fight" or not action_blocker(m).is_empty():
		return ""
	GameManager.consume_action()
	var scene := CombatSetup.begin_event_fight(m.fight, m.title)
	CombatSetup.pending_outcome["mission_uid"] = uid
	return scene

func resolve_fight(uid: String, won: bool) -> String:
	var m := find(uid)
	if m.is_empty():
		return ""
	if won:
		_complete(m)
		return "Encargo «%s» cumplido." % m.title
	_apply(m.get("fail_effects", {}), m)
	_fail(m, "Pierdes el combate.")
	return "Encargo «%s» fallido." % m.title

## Prepara el duelo de exhibición: gasta la acción y devuelve el rival (o null).
func start_exhibition(uid: String) -> Character:
	var m := find(uid)
	if m.is_empty() or m.type != "exhibition" or not action_blocker(m).is_empty():
		return null
	var rival: Character = RelationsData.character_of(m.target)
	GameManager.consume_action()
	rival.current_health = rival.max_health
	rival.current_stamina = rival.max_stamina
	rival.current_morale = rival.max_morale
	return rival

## Llamado por la escena de duelo al terminar un duelo de campaña.
func on_duel_finished(enemy: Character, player_won: bool) -> void:
	if enemy == null:
		return
	for m: Dictionary in active.duplicate():
		match m.type:
			"win_duels":
				if player_won:
					m.progress = int(m.progress) + 1
					if int(m.progress) >= int(m.amount):
						_complete(m)
			"exhibition":
				if m.get("target", "") == enemy.full_name():
					if player_won:
						_complete(m)
					else:
						_fail(m, "Pierdes el duelo de exhibición.")
	missions_changed.emit()

# --- Textos ---

func describe_text(m: Dictionary) -> String:
	return str(m.text).replace("{giver}", str(m.get("giver", ""))).replace("{target}", str(m.get("target", ""))).replace("{amount}", str(m.get("amount", "")))

func months_left(m: Dictionary) -> int:
	return maxi(0, int(m.deadline) - GameManager.months_elapsed())

func progress_text(m: Dictionary) -> String:
	var castle: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
	match m.type:
		"actions", "win_duels":
			return "Progreso: %d/%d" % [m.progress, m.amount]
		"garrison":
			return "Guarnición: %d de %d" % [castle.garrison_size if castle != null else 0, int(m.baseline) + int(m.amount)]
		"castle_gold":
			return "Tesoro: %d de %d" % [castle.gold if castle != null else 0, int(m.baseline) + int(m.amount)]
		"affinity":
			var r: Relationship = RelationsData.get_relation(m.get("target", ""))
			return "Afinidad con %s: %d de %d" % [m.target, r.affinity if r != null else 0, int(m.baseline) + int(m.amount)]
		"alliance":
			return "Alianza con %s: pendiente" % m.target
		"conquer":
			return "Castillos conquistados: %d de %d" % [_owned_castles(), int(m.baseline) + 1]
	return ""

func _effects_text(effects: Dictionary) -> String:
	var labels := {"gold": "oro", "honor": "honor", "fame": "fama", "affinity": "favor de quien encarga", "garrison": "soldados"}
	var parts: Array[String] = []
	for key in effects:
		parts.append("%+d %s" % [effects[key], labels.get(key, key)])
	return ", ".join(parts)

func reward_text(m: Dictionary) -> String:
	return _effects_text(m.reward)

const ABANDON_REASON := "Renuncias al encargo."

## Contexto para RoleProgression.check_ascension: sucesión al trono.
func progression_context() -> Dictionary:
	return RelationsData.succession_context()

## Soldado o Caballero que abandona a su señor y queda sin afiliación. Devuelve el texto.
func desert_liege(player: Character) -> String:
	var old_liege := RelationsData.liege_name
	var liege: Relationship = RelationsData.get_relation(old_liege)
	if liege != null:
		liege.adjust(DESERT_LIEGE_AFFINITY)
	player.honor = clampi(player.honor + DESERT_LIEGE_HONOR, 0, 100)
	player.role = Character.Role.INAFILIADO
	leave_liege()   # los encargos de tu antiguo señor ya no te atan
	GameManager.refresh_actions_for_role_change()
	return "Rompes tu juramento con %s y te vas por los caminos. Ahora eres %s (honor %d)." % [
		old_liege if not old_liege.is_empty() else "tu señor", player.role_title(), DESERT_LIEGE_HONOR]

## Sin señor se olvida el vasallaje y sus encargos.
func leave_liege() -> void:
	RelationsData.liege_name = ""
	active.clear()
	RelationsData.relations_changed.emit()
	missions_changed.emit()

# --- Guardado (datos planos) ---

func save_state() -> Dictionary:
	return {"active": active.duplicate(true), "completed": completed_count, "failed": failed_count,
		"next_id": _next_id, "last_marriage_offer": _last_marriage_offer}

func load_state(data: Dictionary) -> void:
	active.clear()
	for m in data.get("active", []):
		if not m.get("contract", false):   # los contratos mercenarios de partidas antiguas ya no existen
			active.append(m)
	completed_count = int(data.get("completed", 0))
	failed_count = int(data.get("failed", 0))
	_next_id = int(data.get("next_id", 1))
	_last_marriage_offer = int(data.get("last_marriage_offer", -100))
	missions_changed.emit()
