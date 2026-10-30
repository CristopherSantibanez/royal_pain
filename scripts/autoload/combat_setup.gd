extends Node
# Autoload — registrar como "CombatSetup"

const CASTLE_SCENE := "res://scenes/castle_interior/castle_interior.tscn"
## Escena de todos los combates que no son batallas campales (duelos, encuentros, torneos, prácticas…).
const RPG_SCENE := "res://scenes/rpg_battle/rpg_battle.tscn"
const ESCORT_MAX := 4   # el jefe rival + como mucho 4 de escolta (5 enemigos)

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
# Duelo a muerte: si cae el jugador (no un campeón), muere (DynastyData.on_player_died); si cae
# el rival, muere él. Quien lance el duelo lo activa justo después de start_campaign_duel:
#   CombatSetup.duel_to_death = option.get("to_death", false)
var duel_to_death: bool = false
# Combate de grupo (eventos, encuentros, exploración, historias): tu grupo (PartyData) contra el rival
# como jefe más una escolta genérica según el contexto (EnemyCatalog). Los duelos de honor son 1 contra 1.
var group_fight := false
var fight_context := ""
var enemy_party: Array[Character] = []

# --- Combates que nacen de un evento (ver opciones "fight" en EventCatalog) ---
# pending_outcome: {title, win: {effects, result}, lose: {effects, result}, no_rival}
# skirmish: escaramuza pendiente {title, enemy_name, player_soldiers, enemy_soldiers, foe}
var pending_outcome: Dictionary = {}
var skirmish: Dictionary = {}
const SKIRMISH_GARRISON_SHARE := 0.3     # parte de tu guarnición que sale contigo
const SKIRMISH_MIN_SOLDIERS := 12

# --- Batallas ajenas: alguien que te conoce te llama a filas (ver InvitationCatalog) ---
# invited: {kind ("army" asedio de un ejército de la IA | "field" batalla campal), title, inviter, lord, side,
#   army_id, castle_id, ally_castle_id, enemy_castle_id, player_soldiers}
var invited: Dictionary = {}
const PERSONAL_LEVY_BY_RANK := [12, 15, 20, 30, 40, 50, 60]   # tu pelotón por defecto según tu rango (campesino: milicia)

# --- Reparto de hombres antes de la batalla: tu pelotón y el de cada compañero ---
# Mínimo por pelotón (uno más pequeño se rompe enseguida) y máximo según el Liderazgo de quien lo manda.
const PLATOON_MIN := 15
const PLATOON_BASE_MAX := 10              # máximo = PLATOON_BASE_MAX + PLATOON_PER_LEADERSHIP × Liderazgo
const PLATOON_PER_LEADERSHIP := 2         # (Liderazgo 5 → 20, 10 → 30, 15 → 40, 20 → 50)
const PLATOON_STEP := 5                   # lo que suma o resta cada pulsación
# Soldada por batalla: en una batalla ajena los hombres se contratan para ella y se pagan de tu bolsa
# (si vencéis, el anfitrión paga INVITE_WIN_GOLD_PER_SOLDIER por cada uno). Tu propia gente
# (ejército, guarnición) ya cobra: repartirla es gratis.
const SOLDADA_PER_MAN := 2
const PERSONAL_RETAINERS := PLATOON_MIN    # tus allegados: el mínimo de tu propio pelotón nunca se paga
const FIELD_BATTLE_SHARE := 0.4          # parte de cada guarnición que sale a la batalla campal
const FIELD_BATTLE_MIN := 20

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
	duel_to_death = false
	group_fight = false
	fight_context = ""
	enemy_party = []
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

## Por qué el jugador no puede ir a una batalla por su cuenta ("" si puede). Un campesino solo lucha
## en una batalla si alguien que lo conoce lo llama a filas (las invitaciones no pasan por aquí).
func battle_blocker(player: Character) -> String:
	if player != null and player.role == Character.Role.CAMPESINO:
		return "Un campesino no va a la guerra por su cuenta: solo si alguien que te conoce te llama a filas."
	return ""

## Tu pelotón por defecto en una batalla ajena, según tu rango.
func player_levy(player: Character) -> int:
	if player == null:
		return PERSONAL_LEVY_BY_RANK[0]
	return PERSONAL_LEVY_BY_RANK[clampi(player.rank(), 0, PERSONAL_LEVY_BY_RANK.size() - 1)]

## Hombres que puede mandar alguien en un pelotón (según su Liderazgo).
func platoon_max(c: Character) -> int:
	return PLATOON_BASE_MAX + PLATOON_PER_LEADERSHIP * (c.leadership if c != null else 0)

## Soldada de un reparto {nombre: hombres}: solo si los hombres se contratan (batalla ajena). Los allegados de tu propio pelotón (PERSONAL_RETAINERS) no cobran.
func soldada_cost(allocation: Dictionary, player_name: String, hired: bool) -> int:
	if not hired:
		return 0
	var men := 0
	for who in allocation:
		var n := int(allocation[who])
		men += maxi(0, n - PERSONAL_RETAINERS) if who == player_name else n
	return men * SOLDADA_PER_MAN

## Reparto inicial: tu pelotón según tu rango (o tu parte del total), y el mínimo para cada compañero.
## pool > 0 limita el total (tu propia gente); pool <= 0 = hombres contratados, sin límite de total.
func default_allocation(player: Character, companions: Array[Character], pool: int, mine_default: int) -> Dictionary:
	var result := {}
	var leaders: Array[Character] = [player]
	leaders.append_array(companions)
	var floor_men: int = PLATOON_MIN if pool <= 0 else clampi(pool / maxi(1, leaders.size()), 1, PLATOON_MIN)
	var left: int = pool
	for i in range(leaders.size() - 1, -1, -1):   # primero el mínimo de los compañeros, lo demás para ti
		var c: Character = leaders[i]
		var n: int = floor_men if i > 0 else clampi(mine_default, floor_men, maxi(floor_men, platoon_max(c)))
		if pool > 0:
			if i == 0:
				n = clampi(left, mini(floor_men, left), maxi(floor_men, platoon_max(c)))
			n = mini(n, maxi(0, left))
			left -= n
		result[c.full_name()] = n
	return result

## Prepara una batalla ajena a partir de la opción aceptada (datos planos: nombres e ids).
func begin_invited_battle(fight: Dictionary, event_title: String) -> String:
	invited = fight.duplicate()
	invited["title"] = event_title
	invited["player_soldiers"] = player_levy(GameManager.player_character)
	return "res://scenes/battle/battle.tscn"

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
	if fight.get("type", "duel") == "invited":
		return begin_invited_battle(fight, event_title)
	if fight.get("type", "duel") == "battle" and not battle_blocker(player).is_empty():
		return ""   # quien llama ya debió impedirlo (EventCatalog.can_choose, MissionData.action_blocker)
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
	duel_to_death = bool(fight.get("to_death", false))
	return_scene = "res://scenes/map/map.tscn"
	group_fight = true
	fight_context = str(fight.get("context", "camino"))
	enemy_party = make_enemy_party(foe, fight_context, player)
	return RPG_SCENE

## Marca de dónde viene un combate (camino, exploracion, historia…) para elegir la escolta enemiga.
static func tag_fight(fight: Dictionary, context: String) -> Dictionary:
	if fight.is_empty() or fight.has("context"):
		return fight
	var out := fight.duplicate()
	out["context"] = context
	return out

## Grupo rival: el rival con nombre de jefe y una escolta genérica del contexto (tantos como tu grupo activo).
func make_enemy_party(leader: Character, context: String, player: Character) -> Array[Character]:
	var out: Array[Character] = [leader]
	var size := clampi(PartyData.active().size() if player != null else 1, 1, ESCORT_MAX)
	var escort := EnemyCatalog.make_party(context, player.level if player != null else 1)
	for e in escort.slice(0, size):
		out.append(e)
	return out

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
	var summary := EventCatalog._apply_effects(o.get("effects", {}), player, castle, null, true)
	WorldEvents.record("%s: %s" % [title, text], "", true)
	if not summary.is_empty():
		text += "\n\n" + summary   # recompensas en lista, una por línea
	return text

func clear() -> void:
	invited = {}
	player_character = null
	enemy_character = null
	is_campaign = false
	return_scene = ""
	duel_to_death = false
	group_fight = false
	fight_context = ""
	enemy_party = []
	tournament_opponents.clear()
	tournament_round = 0
