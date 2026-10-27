extends Node
# Autoload — registrar como "GameManager"

signal turn_advanced(month: int, year: int)
signal game_started(character: Character)
signal state_changed(new_state: int)
signal actions_changed(remaining: int, total: int)
signal event_resolved(result_text: String)
## Se elige una opción de un evento (antes de aplicar sus efectos). Lo escuchan los sistemas que
## reaccionan a opciones especiales (aceptar un encargo, una boda política...): ver MissionData.
signal event_option_chosen(event: Dictionary, option: Dictionary)

const MONTHS_PER_YEAR := 12

const ACTIONS_BASE_BY_ROLE := {
	Character.Role.CAMPESINO: 1,
	Character.Role.SOLDADO: 1,
	Character.Role.CABALLERO: 2,
	Character.Role.NOBLEZA_BAJA: 2,
	Character.Role.NOBLEZA_ALTA: 3,
	Character.Role.REGENTE: 4,
	Character.Role.DUQUE: 4,
	Character.Role.MERCENARIO: 1,
	Character.Role.CAPITAN: 2,
	Character.Role.CONDOTIERO: 3,
}

var player_character: Character
var home_castle_id: String = ""   # castillo donde el jugador inicia y puede entrar
var player_kingdom: int = -1        # reino al que sirve el jugador (el de su castillo de origen)
var game_over_reason: String = ""   # no vacío cuando la partida terminó en derrota

# Eventos (ver EventCatalog): el mensual espera la decisión del jugador; el anual ya se aplicó.
var pending_event: Dictionary = {}
# Eventos con decisión que esperan su turno: se muestran de uno en uno, en orden de llegada.
# Úsalo en vez de escribir pending_event directamente para no pisar otro evento.
var event_queue: Array = []
var last_annual_event: String = ""

# Victoria (ver VictoryRules): la meta depende del rol con el que se empezó la partida.
var starting_role: int = -1
var victory_achieved: bool = false   # ya se anunció la victoria (se puede seguir jugando)

var active_edict: String = ""        # edicto del Regente vigente (ver EdictCatalog)
var last_tournament_year: int = 0    # año del último torneo disputado (uno por año)
var current_castle: Castle
var current_month: int = 1
var current_year: int = 1
var current_state: int = GameStateEnums.State.MENU
var is_game_active: bool = false

var actions_remaining: int = 0
var actions_per_turn: int = 0

func start_new_game(character: Character, start_castle_id: String) -> void:
	# Cada partida nueva se juega en un mundo nuevo. Si la pantalla de Nueva Partida ya generó uno
	# (y el jugador eligió castillo en él), se usa ese; si no, se genera otro.
	# (ArmyData se reinicia solo al escuchar game_started; referenciarlo aquí crearía un ciclo de dependencias.)
	if MapData.world_used:
		MapData.new_world()
	MapData.world_used = true

	player_character = character
	home_castle_id = start_castle_id
	current_castle = MapData.get_castle_by_id(start_castle_id)
	player_kingdom = current_castle.kingdom if current_castle != null else -1
	game_over_reason = ""
	pending_event = {}
	event_queue.clear()
	last_annual_event = ""
	starting_role = character.role
	victory_achieved = false
	active_edict = ""
	last_tournament_year = 0
	current_month = 1
	current_year = 1
	is_game_active = true
	_recalculate_actions_per_turn()
	game_started.emit(character)

# Restaura una partida guardada (ver SaveSystem). No emite game_started para no reiniciar el mundo.
func restore_game(character: Character, start_castle_id: String, kingdom: int, month: int, year: int,
		remaining: int, per_turn: int) -> void:
	player_character = character
	home_castle_id = start_castle_id
	player_kingdom = kingdom
	current_castle = MapData.get_castle_by_id(start_castle_id)
	current_month = month
	current_year = year
	actions_per_turn = per_turn
	actions_remaining = remaining
	game_over_reason = ""
	is_game_active = true
	change_state(GameStateEnums.State.MAP)
	actions_changed.emit(actions_remaining, actions_per_turn)

func advance_turn() -> void:
	if not is_game_active:
		push_warning("GameManager: se intentó avanzar el turno sin una partida activa.")
		return

	current_month += 1
	if current_month > MONTHS_PER_YEAR:
		current_month = 1
		current_year += 1

	# Eventos: el anual (cada enero) afecta a todos los castillos; el mensual espera decisión.
	# (Pendiente para más adelante: relaciones y moral.)
	last_annual_event = EventCatalog.roll_annual(MapData.castles) if current_month == 1 else ""
	pending_event = EventCatalog.roll_monthly(player_character)

	if player_character != null:
		player_character.monthly_recovery()
	_recalculate_actions_per_turn()
	turn_advanced.emit(current_month, current_year)
	_pull_queued_event()

# --- Victoria y derrota ---

func evaluate_goal() -> Dictionary:
	# MissionData se busca por ruta (como ArmyData más arriba) para no crear un ciclo de dependencias.
	var missions := get_node_or_null("/root/MissionData")
	var extra := {"contracts_done": missions.contracts_done, "company_size": missions.company_size()} if missions != null else {}
	return VictoryRules.evaluate(starting_role, player_character, MapData.castles, player_kingdom, home_castle_id, extra)

# La partida solo termina al dominar el mundo, al unificar los dos últimos reinos por matrimonio
# (AchievementData) o al morir o ser ejecutado sin heredero (DynastyData).

## Deshonra total: no termina la partida, pero se pierde rango y fama (RoleProgression.apply_disgrace).
## Devuelve el texto de lo ocurrido, o "" si no hay deshonra.
func check_disgrace() -> String:
	if not is_game_active or not RoleProgression.is_disgraced(player_character):
		return ""
	var relations := get_node_or_null("/root/RelationsData")
	var has_liege: bool = relations != null and not relations.liege_name.is_empty()
	var result := RoleProgression.apply_disgrace(player_character, has_liege)
	if result.expelled:
		var missions := get_node_or_null("/root/MissionData")
		if missions != null:
			missions.leave_liege()   # se pasa por ruta para no crear un ciclo de dependencias
	refresh_actions_for_role_change()
	var events := get_node_or_null("/root/WorldEvents")
	if events != null:
		events.record(result.text, "", true)
		events.notify("Deshonrado", result.text)
	return result.text

## Compatibilidad: la deshonra ya no termina la partida (siempre devuelve false).
func check_defeat() -> bool:
	check_disgrace()
	return false

## Pone un evento en cola: si no hay ninguno esperando decisión, pasa a ser el pendiente.
## front = true lo adelanta (para lo urgente: cautiverio, sucesión, ultimátums).
func queue_event(event: Dictionary, front: bool = false) -> void:
	if event.is_empty():
		return
	if pending_event.is_empty():
		pending_event = event
	elif front:
		event_queue.push_front(event)
	else:
		event_queue.append(event)

func _pull_queued_event() -> void:
	if pending_event.is_empty() and not event_queue.is_empty():
		pending_event = event_queue.pop_front()

func has_pending_event() -> bool:
	return not pending_event.is_empty()

# relation: la relación con el protagonista del evento (rivales, amores, cónyuge), si lo hay.
func resolve_pending_event(option_index: int, relation: Relationship = null) -> String:
	if pending_event.is_empty() or player_character == null:
		return ""
	var castle := MapData.get_castle_by_id(home_castle_id)
	var option: Dictionary = pending_event.options[option_index]
	if not EventCatalog.can_choose(option, player_character, castle):
		return ""
	var old_role := player_character.role
	var event := pending_event
	event_option_chosen.emit(event, option)
	var text := EventCatalog.apply_option(event, option_index, player_character, castle, relation)
	if pending_event == event:
		pending_event = {}
	_pull_queued_event()
	var extra: String = event.get("_extra_result", "")
	if not extra.is_empty():
		text += "\n" + extra
	if player_character.role != old_role:
		refresh_actions_for_role_change()
	event_resolved.emit(text)
	return text

func _recalculate_actions_per_turn() -> void:
	if player_character == null:
		actions_per_turn = 0
		actions_remaining = 0
		return
	var base: int = ACTIONS_BASE_BY_ROLE.get(player_character.role, 1)
	var bonus: int = int(player_character.leadership / 10)
	actions_per_turn = base + bonus
	actions_remaining = actions_per_turn
	actions_changed.emit(actions_remaining, actions_per_turn)

func has_actions_remaining() -> bool:
	return actions_remaining > 0

func consume_action() -> bool:
	if actions_remaining <= 0:
		return false
	actions_remaining -= 1
	actions_changed.emit(actions_remaining, actions_per_turn)
	return true

func refresh_actions_for_role_change() -> void:
	# Llamar cuando el rol del jugador cambia (ascenso/descenso) a mitad de turno,
	# para que el máximo de acciones se actualice sin esperar al próximo mes.
	# Mantiene el gasto ya hecho este turno (no regala acciones nuevas de golpe).
	if player_character == null:
		return
	var base: int = ACTIONS_BASE_BY_ROLE.get(player_character.role, 1)
	var bonus: int = int(player_character.leadership / 10)
	var new_total := base + bonus
	var spent := actions_per_turn - actions_remaining
	actions_per_turn = new_total
	actions_remaining = max(0, new_total - spent)
	actions_changed.emit(actions_remaining, actions_per_turn)

func get_date_string() -> String:
	const MONTH_NAMES := [
		"Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
		"Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"
	]
	return "%s, Año %d" % [MONTH_NAMES[current_month - 1], current_year]

func change_state(new_state: int) -> void:
	current_state = new_state
	state_changed.emit(new_state)

func months_elapsed() -> int:
	return (current_year - 1) * MONTHS_PER_YEAR + (current_month - 1)

func end_game(reason: String = "") -> void:
	is_game_active = false
	game_over_reason = reason
	pending_event = {}
	event_queue.clear()
	player_character = null
	home_castle_id = ""
	current_castle = null
