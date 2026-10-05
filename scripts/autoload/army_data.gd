extends Node
# Autoload — registrar como "ArmyData"

signal armies_changed
signal battle_pending(army: Army)
signal events_changed

# --- Balance de resultados de batalla ---
const VICTORY_HONOR := 10
const DEFEAT_HONOR := 5
const LOOT_FRACTION := 0.3   # parte del oro del castillo conquistado que se lleva el jugador

var armies: Array[Army] = []
var _next_id: int = 1

# Ejército cuya batalla se está jugando en la escena de batalla táctica.
var active_battle_army: Army

# Noticias del último turno: [{text, castle_id}]. El mapa muestra las que el jugador puede ver.
var turn_events: Array[Dictionary] = []

func _ready() -> void:
	GameManager.turn_advanced.connect(_on_turn_advanced)
	GameManager.game_started.connect(func(_character: Character): reset())

func reset() -> void:
	armies.clear()
	_next_id = 1
	active_battle_army = null
	turn_events.clear()
	armies_changed.emit()
	events_changed.emit()

func create_army(owner_name: String, kingdom: int, size: int, castle_id: String) -> Army:
	var a := Army.new()
	a.army_id = "army_%d" % _next_id
	_next_id += 1
	a.owner_name = owner_name
	a.kingdom = kingdom
	a.size = size
	a.current_castle_id = castle_id
	armies.append(a)
	armies_changed.emit()
	return a

func get_armies_at(castle_id: String) -> Array[Army]:
	var result: Array[Army] = []
	for a: Army in armies:
		if a.current_castle_id == castle_id:
			result.append(a)
	return result

func get_player_armies() -> Array[Army]:
	var result: Array[Army] = []
	for a: Army in armies:
		if is_player_army(a):
			result.append(a)
	return result

func is_player_army(army: Army) -> bool:
	var player: Character = GameManager.player_character
	return player != null and army.owner_name == player.full_name()

# Un castillo lo defiende el jugador si es su castillo de origen o uno que conquistó.
func is_player_defended(castle: Castle) -> bool:
	var player: Character = GameManager.player_character
	if castle == null or player == null:
		return false
	return castle.castle_id == GameManager.home_castle_id or castle.owner_name == player.full_name()

func set_destination(army: Army, destination_castle_id: String) -> bool:
	if not army.is_idle():
		return false
	var origin: Castle = MapData.get_castle_by_id(army.current_castle_id)
	if origin == null or not origin.connected_castle_ids.has(destination_castle_id):
		return false

	army.origin_castle_id = army.current_castle_id
	army.destination_castle_id = destination_castle_id
	army.turns_remaining = 1   # por ahora, 1 salto = 1 turno, siempre a castillos directamente conectados
	armies_changed.emit()
	return true

func disband_army(army: Army) -> void:
	armies.erase(army)
	armies_changed.emit()

func _add_event(text: String, castle_id: String) -> void:
	turn_events.append({"text": text, "castle_id": castle_id})

# --- Turno mensual ---

func _on_turn_advanced(_month: int, _year: int) -> void:
	turn_events.clear()

	# 1. Las defensas que el jugador no jugó se resuelven solas.
	for a: Army in armies.duplicate():
		if a.pending_battle and not is_player_army(a):
			_auto_resolve_battle(a)

	# 2. Movimiento (se recorre una copia: las llegadas pueden disolver ejércitos).
	for a: Army in armies.duplicate():
		if a.pending_battle or a.destination_castle_id == "":
			continue
		a.turns_remaining -= 1
		if a.turns_remaining <= 0:
			_resolve_arrival(a)

	# 3. Reclutamiento natural en todos los castillos.
	KingdomAI.recruit(MapData.castles)

	# 4. Los reinos de la IA deciden nuevos ataques.
	if GameManager.is_game_active:
		_run_kingdom_ai()

	armies_changed.emit()
	events_changed.emit()

func _run_kingdom_ai() -> void:
	var player_name: String = GameManager.player_character.full_name() if GameManager.player_character != null else ""
	var plans := KingdomAI.plan_attacks(MapData.castles, armies, GameManager.player_kingdom, GameManager.months_elapsed(), player_name)
	for plan: Dictionary in plans:
		var origin: Castle = MapData.get_castle_by_id(plan.from_id)
		var target: Castle = MapData.get_castle_by_id(plan.to_id)
		if origin == null or target == null or plan.size <= 0:
			continue
		origin.garrison_size -= plan.size
		var army := create_army(origin.owner_name, origin.kingdom, plan.size, origin.castle_id)
		set_destination(army, target.castle_id)
		var warning := " ¡Va hacia tu castillo!" if is_player_defended(target) else ""
		_add_event("%s moviliza %d soldados desde %s hacia %s.%s" % [
			origin.owner_name, plan.size, origin.castle_name, target.castle_name, warning], target.castle_id)

func _resolve_arrival(army: Army) -> void:
	var destination: Castle = MapData.get_castle_by_id(army.destination_castle_id)
	if destination == null:
		# Castillo inválido, cancela la marcha para no dejar el ejército en el limbo.
		army.destination_castle_id = ""
		return

	army.current_castle_id = destination.castle_id
	army.destination_castle_id = ""

	if destination.kingdom == army.kingdom:
		# Territorio aliado: el ejército se disuelve y refuerza la guarnición local.
		destination.garrison_size += army.size
		disband_army(army)
		return

	# Territorio enemigo: queda a la espera de batalla.
	army.pending_battle = true
	if is_player_army(army):
		battle_pending.emit(army)
	elif is_player_defended(destination):
		_add_event("¡%s asedia %s con %d soldados! Defiéndelo antes de avanzar el turno." % [
			army.owner_name, destination.castle_name, army.size], destination.castle_id)
		battle_pending.emit(army)
	else:
		_auto_resolve_battle(army)

func _auto_resolve_battle(army: Army) -> void:
	var castle: Castle = MapData.get_castle_by_id(army.current_castle_id)
	if castle == null:
		disband_army(army)
		return
	var defending := is_player_defended(castle)
	var r := KingdomAI.auto_resolve(army.size, castle.garrison_size)
	var summary := resolve_battle(army, r.attacker_won, r.attacker_survivors, r.defender_survivors, defending)
	var prefix := "Sin tu mando, la defensa se libra sola: " if defending else ""
	_add_event(prefix + summary.replace("\n", " "), castle.castle_id)

# --- Resolución de batallas (escena táctica o auto-resolución) ---
# Devuelve un texto de resumen con las consecuencias en el mapa y para el jugador.

func resolve_battle(army: Army, attacker_won: bool, attacker_survivors: int, defender_survivors: int, player_defending: bool = false) -> String:
	var castle: Castle = MapData.get_castle_by_id(army.current_castle_id)
	if army == active_battle_army:
		active_battle_army = null
	if castle == null:
		disband_army(army)
		return "El castillo disputado ya no existe."

	var lines: Array[String] = []
	var player: Character = GameManager.player_character
	var player_attacking := is_player_army(army)

	if attacker_won:
		var old_kingdom: int = castle.kingdom
		castle.kingdom = army.kingdom
		castle.owner_name = army.owner_name
		castle.garrison_size = attacker_survivors
		disband_army(army)
		lines.append("%s cae en manos de %s (antes: %s). Guarnición: %d soldados." % [
			castle.castle_name, KingdomEnums.kingdom_name(castle.kingdom), KingdomEnums.kingdom_name(old_kingdom), attacker_survivors])
		if player_attacking:
			var loot := int(castle.gold * LOOT_FRACTION)
			castle.gold -= loot
			player.gold += loot
			player.honor = clamp(player.honor + VICTORY_HONOR, 0, 100)
			lines.append("Ganas %d de honor y saqueas %d de oro." % [VICTORY_HONOR, loot])
		elif player_defending:
			_apply_player_defeat(lines)
			if castle.castle_id == GameManager.home_castle_id:
				_handle_home_castle_lost(castle, lines)
	else:
		castle.garrison_size = defender_survivors
		lines.append("%s resiste el ataque con %d defensores." % [castle.castle_name, defender_survivors])
		_retreat_army(army, attacker_survivors, lines)
		if player_attacking:
			_apply_player_defeat(lines)
		elif player_defending and player != null:
			player.honor = clamp(player.honor + VICTORY_HONOR, 0, 100)
			lines.append("Defendiste tu castillo: ganas %d de honor." % VICTORY_HONOR)

	return "\n".join(lines)

func _retreat_army(army: Army, survivors: int, lines: Array[String]) -> void:
	var origin: Castle = MapData.get_castle_by_id(army.origin_castle_id)
	if survivors <= 0 or origin == null:
		disband_army(army)
		lines.append("No quedan tropas que puedan replegarse: el ejército se disuelve.")
		return
	if is_player_army(army):
		army.size = survivors
		army.pending_battle = false
		army.current_castle_id = army.origin_castle_id
		army.destination_castle_id = ""
		armies_changed.emit()
		lines.append("Tu ejército se repliega a %s con %d soldados." % [origin.castle_name, survivors])
	else:
		# La IA no vuelve a dar órdenes a un ejército derrotado: sus restos regresan a la guarnición.
		if origin.kingdom == army.kingdom:
			origin.garrison_size += survivors
		disband_army(army)
		lines.append("Los %d sobrevivientes de %s se repliegan a %s." % [survivors, army.owner_name, origin.castle_name])

func _apply_player_defeat(lines: Array[String]) -> void:
	var player: Character = GameManager.player_character
	if player == null:
		return
	player.honor = clamp(player.honor - DEFEAT_HONOR, 0, 100)
	lines.append("Pierdes %d de honor." % DEFEAT_HONOR)
	if RoleProgression.check_dishonor_demotion(player):
		var old_role: int = player.role
		RoleProgression.apply_dishonor_demotion(player)
		GameManager.refresh_actions_for_role_change()
		lines.append("Caes en deshonra y desciendes de %s a %s." % [
			Character.role_name_for(old_role), player.role_name()])

func _handle_home_castle_lost(lost: Castle, lines: Array[String]) -> void:
	var player: Character = GameManager.player_character
	if player == null:
		return
	# Busca refugio en otro castillo conquistado por el jugador.
	for c: Castle in MapData.castles:
		if c != lost and c.owner_name == player.full_name():
			GameManager.home_castle_id = c.castle_id
			GameManager.current_castle = c
			lines.append("Pierdes tu hogar, pero te refugias en %s." % c.castle_name)
			return
	var reason := "%s ha caído y no te queda ningún castillo donde refugiarte." % lost.castle_name
	lines.append(reason + " Fin de la partida.")
	GameManager.end_game(reason)
