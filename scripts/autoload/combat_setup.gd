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

# --- Combates que nacen de un evento (ver opciones "fight" en EventCatalog) ---
# pending_outcome: {title, win: {effects, result}, lose: {effects, result}, no_rival}
# skirmish: escaramuza pendiente {title, enemy_name, player_soldiers, enemy_soldiers, foe}
var pending_outcome: Dictionary = {}
var skirmish: Dictionary = {}
const SKIRMISH_GARRISON_SHARE := 0.3     # parte de tu guarnición que sale contigo
const SKIRMISH_MIN_SOLDIERS := 12

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

## Rival generado para un combate de evento: algo más fuerte o débil que el jugador según "power".
func make_event_foe(spec: Dictionary, player: Character) -> Character:
	var gender: int = spec.get("gender", [CharacterEnums.Gender.MASCULINO, CharacterEnums.Gender.FEMENINO].pick_random())
	var foe := CharacterLoader.make_rival(player, RelationsData.take_free_portrait(gender), gender)
	foe.role = int(spec.get("role", player.role))
	var power := int(spec.get("power", 0))
	foe.combat = clampi(foe.combat + power, 1, 20)
	foe.defense = clampi(foe.defense + power, 1, 20)
	if spec.has("name"):
		foe.first_name = str(spec.name)
		foe.last_name = ""
	if spec.has("personality") and Character.Personality.has(str(spec.personality)):
		foe.personality = Character.Personality[str(spec.personality)]
	foe.current_health = foe.max_health
	foe.current_stamina = foe.max_stamina
	foe.current_morale = foe.max_morale
	return foe

## Prepara el combate de una opción de evento. Devuelve la escena a la que ir ("" si no hay combate).
func begin_event_fight(fight: Dictionary, event_title: String) -> String:
	var player: Character = GameManager.player_character
	pending_outcome = {"title": event_title, "win": fight.get("win", {}), "lose": fight.get("lose", {}),
		"no_rival": fight.get("no_rival", false)}
	var foe := make_event_foe(fight.get("foe", {}), player)
	if fight.get("type", "duel") == "battle":
		var castle: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
		var mine: int = maxi(SKIRMISH_MIN_SOLDIERS, int(castle.garrison_size * fight.get("garrison_share", SKIRMISH_GARRISON_SHARE)) if castle != null else SKIRMISH_MIN_SOLDIERS)
		skirmish = {"title": event_title, "enemy_name": fight.get("enemy_name", foe.full_name()),
			"player_soldiers": mine, "enemy_soldiers": maxi(6, roundi(mine * float(fight.get("enemy_ratio", 1.0)))), "foe": foe}
		return "res://scenes/battle/battle.tscn"
	start_campaign_duel(player, foe)
	return_scene = "res://scenes/map/map.tscn"
	return "res://scenes/combat/combat.tscn"

## Aplica el desenlace del combate de un evento y devuelve su texto ("" si no había ninguno).
func apply_outcome(won: bool) -> String:
	if pending_outcome.is_empty():
		return ""
	var o: Dictionary = pending_outcome.get("win" if won else "lose", {})
	var title: String = pending_outcome.get("title", "")
	var mission_uid: String = pending_outcome.get("mission_uid", "")
	pending_outcome = {}
	if not mission_uid.is_empty():
		return MissionData.resolve_fight(mission_uid, won)
	var player: Character = GameManager.player_character
	var castle: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
	var text: String = o.get("result", "")
	var summary := EventCatalog._apply_effects(o.get("effects", {}), player, castle)
	if not summary.is_empty():
		text += " (%s)" % summary
	WorldEvents.record("%s: %s" % [title, text], "", true)
	return text

func clear() -> void:
	player_character = null
	enemy_character = null
	is_campaign = false
	return_scene = ""
	tournament_opponents.clear()
	tournament_round = 0
