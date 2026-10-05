extends Node
# Autoload — registrar como "CombatSetup"

const CASTLE_SCENE := "res://scenes/castle_interior/castle_interior.tscn"

var player_character: Character
var enemy_character: Character

# --- Duelo de campaña (iniciado desde el castillo) ---
var is_campaign: bool = false
var return_scene: String = ""
var last_result_text: String = ""   # resumen que el castillo muestra al volver

func start_campaign_duel(player: Character, rival: Character) -> void:
	player_character = player
	enemy_character = rival
	is_campaign = true
	return_scene = CASTLE_SCENE
	last_result_text = ""

func clear() -> void:
	player_character = null
	enemy_character = null
	is_campaign = false
	return_scene = ""
