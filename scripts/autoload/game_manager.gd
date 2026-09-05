extends Node
# Autoload — registrar como "GameManager"

signal turn_advanced(month: int, year: int)
signal game_started(character: Character)
signal state_changed(new_state: int)

const MONTHS_PER_YEAR := 12

var player_character: Character
var current_month: int = 1
var current_year: int = 1
var current_state: int = GameStateEnums.State.MENU
var is_game_active: bool = false

func start_new_game(character: Character) -> void:
	player_character = character
	current_month = 1
	current_year = 1
	is_game_active = true
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
	# Por ahora, solo avanza la fecha.

	turn_advanced.emit(current_month, current_year)

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
