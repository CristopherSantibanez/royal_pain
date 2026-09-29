extends Node
# Autoload — registrar como "GameManager"

signal turn_advanced(month: int, year: int)
signal game_started(character: Character)
signal state_changed(new_state: int)
signal actions_changed(remaining: int, total: int)

const MONTHS_PER_YEAR := 12

const ACTIONS_BASE_BY_ROLE := {
	Character.Role.CAMPESINO: 1,
	Character.Role.SOLDADO: 1,
	Character.Role.CABALLERO: 2,
	Character.Role.NOBLEZA_BAJA: 2,
	Character.Role.NOBLEZA_ALTA: 3,
	Character.Role.REGENTE: 4,
}

var player_character: Character
var current_castle: Castle
var current_month: int = 1
var current_year: int = 1
var current_state: int = GameStateEnums.State.MENU
var is_game_active: bool = false

var actions_remaining: int = 0
var actions_per_turn: int = 0

func start_new_game(character: Character) -> void:
	player_character = character
	current_month = 1
	current_year = 1
	is_game_active = true
	_recalculate_actions_per_turn()
	game_started.emit(character)

func advance_turn() -> void:
	if not is_game_active:
		push_warning("GameManager: se intentó avanzar el turno sin una partida activa.")
		return

	current_month += 1
	if current_month > MONTHS_PER_YEAR:
		current_month = 1
		current_year += 1

	# --- Punto de extensión ---
	# Aquí es donde, más adelante, se resolverán:
	# - eventos aleatorios mensuales según personalidad/rol
	# - eventos anuales globales (cuando current_month == 1)
	# - actualización de recursos, relaciones y moral
	# Por ahora, solo avanza la fecha y recarga las acciones disponibles.

	_recalculate_actions_per_turn()
	turn_advanced.emit(current_month, current_year)

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

func end_game() -> void:
	is_game_active = false
	player_character = null
