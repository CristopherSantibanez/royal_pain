extends Node
# Autoload — registrar como "CombatSetup"

const CASTLE_SCENE := "res://scenes/castle_interior/castle_interior.tscn"

# --- Torneos (ajustables sin tocar la lógica) ---
const TOURNAMENT_ROUNDS := 3
const TOURNAMENT_ENTRY_FEE := 50
const TOURNAMENT_PRIZE_GOLD := 300
const TOURNAMENT_PRIZE_HONOR := 15
const TOURNAMENT_ROUND_HONOR := 3      # por cada ronda ganada
const TOURNAMENT_ROUND_HEAL := 30      # vida que se recupera entre rondas
const TOURNAMENT_STAT_STEP := 1        # cada ronda el rival es algo más fuerte
const TOURNAMENT_MONTHS := [4, 5, 6, 7, 8, 9]

var player_character: Character
var enemy_character: Character

# --- Duelo de campaña (iniciado desde el castillo) ---
var is_campaign: bool = false
var return_scene: String = ""
var last_result_text: String = ""   # resumen que el castillo muestra al volver

# --- Torneo en curso ---
var tournament_opponents: Array[Character] = []
var tournament_round: int = 0       # 1..TOURNAMENT_ROUNDS mientras hay torneo; 0 si no
var tournament_honor_start: int = 0
var tournament_gold_start: int = 0

func start_campaign_duel(player: Character, rival: Character) -> void:
	player_character = player
	enemy_character = rival
	is_campaign = true
	return_scene = CASTLE_SCENE
	last_result_text = ""
	tournament_opponents.clear()
	tournament_round = 0

func is_tournament() -> bool:
	return tournament_round > 0

func start_tournament(player: Character, opponents: Array[Character]) -> void:
	start_campaign_duel(player, opponents[0])
	tournament_opponents = opponents
	tournament_round = 1
	tournament_honor_start = player.honor
	tournament_gold_start = player.gold

func is_final_round() -> bool:
	return tournament_round >= tournament_opponents.size()

# Pasa a la siguiente ronda: el jugador recupera algo de vida y entra el siguiente rival.
func advance_tournament_round() -> void:
	tournament_round += 1
	enemy_character = tournament_opponents[tournament_round - 1]
	player_character.current_health = mini(player_character.max_health, player_character.current_health + TOURNAMENT_ROUND_HEAL)
	player_character.current_stamina = player_character.max_stamina
	player_character.current_morale = player_character.max_morale

func clear() -> void:
	player_character = null
	enemy_character = null
	is_campaign = false
	return_scene = ""
	tournament_opponents.clear()
	tournament_round = 0
