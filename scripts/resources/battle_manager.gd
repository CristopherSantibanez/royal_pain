class_name BattleManager
extends RefCounted

signal log_message(text: String)
signal state_updated
signal battle_ended(winner_side: int, report: Dictionary)
# Eventos puntuales para animaciones y sonido (no cambian la simulación).
signal unit_attacked(attacker: BattleUnit, target: BattleUnit, casualties: int, counter: int, ranged: bool)
signal unit_routed(unit: BattleUnit, annihilated: bool)
signal ability_used(user: Character, ability_id: String, side: int)
# La IA reta a duelo singular al jefe de uno de tus pelotones: la batalla espera tu respuesta (answer_challenge).
signal challenge_offered(challenger: BattleUnit, target: BattleUnit)
# Un duelo entre jefes terminó (o se rehusó): texto para el cartel.
signal challenge_resolved(text: String)

# --- Constantes de balance (ajustables sin tocar la lógica) ---
const GRID_W := 12
const GRID_H := 8
const MAX_TURNS := 12               # si se agota, el asedio fracasa y gana el defensor
const SOLDIERS_PER_UNIT := 20
const MAX_UNITS_PER_SIDE := 6
const MAX_UNITS_WITH_ALLIES := 8      # en una batalla ajena: tus pelotones + los del anfitrión (una columna del tablero)
const ROUT_CONTAGION := 5             # moral que pierde el bando cuando huye un pelotón completo (proporcional a su tamaño)
const WALL_COLUMNS := 2
const AI_ENGAGE_DISTANCE := 4       # el defensor amurallado solo sale si el enemigo está así de cerca
const BASE_MORALE := 70
const RETALIATION_FACTOR := 0.4
const SIEGE_BREAK_RATIO := 0.38       # al agotarse el asedio, la guarnición con menos de esta parte en pie se rinde...
const CAPTAIN_MASTERY_SHARE := 0.5    # parte del mando del general que llega a los pelotones de sus capitanes
const NIGHT_MORALE_WEIGHT := 0.1      # al caer la noche, cada punto de moral media vale una décima de soldado

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# Habilidades de batalla con efecto mecánico (por nombre, ver GameData._load_battle_skills)
const SKILL_GRITO_GUERRA := "Grito de Guerra"
const SKILL_TACTICA_DEFENSIVA := "Táctica Defensiva"
const SKILL_CARGA_LETAL := "Carga Letal"
const GRITO_GUERRA_MORALE := 5
const CARGA_LETAL_FACTOR := 1.4
const CARGA_MIN_DISTANCE := 2         # con Carga Letal, la caballería que carga 2+ casillas no recibe respuesta
const TACTICA_DEFENSIVA_FACTOR := 1.3
const TACTICA_DEFENSIVA_WALL_MORALE := 5
const COMMANDER_DIVISOR := 200.0      # bonus del comandante: 1 + (Liderazgo + Estrategia) / este valor

# --- Compañeros al mando de pelotones (séquito del jugador o cortesanos del señor enemigo) ---
const COMPANION_DIVISOR := 100.0      # bonus del pelotón: (Combate + Liderazgo del compañero) / este valor
const COMPANION_MORALE_DIVISOR := 2   # moral inicial extra: Liderazgo del compañero / este valor
const FACTION_MORALE_PENALTY := 10    # los prestados por el señor no luchan con la misma entrega
const FACTION_DESERT_MORALE := 45     # si el pelotón cae por debajo de esta moral, el de facción se retira
const WOUND_CHANCE_ANNIHILATED := 0.6
const WOUND_CHANCE_ROUTED := 0.25
const COMPANION_WOUND_MONTHS := 2

# --- Órdenes de pelotón ---
const HOLD_DEFENSE := 1.3             # Mantener posición: recibe menos bajas, pero no se mueve
const CHARGE_POWER := 1.3             # Cargar: su primer golpe cuerpo a cuerpo hace +30%...
const CHARGE_FATIGUE := 1.5           # ...a costa de cansarse más al moverse y al golpear
const WITHDRAW_STEPS := 2             # Replegarse: retrocede hasta 2 casillas, recupera moral y gasta el turno
const WITHDRAW_MORALE := 10
const WITHDRAW_FATIGUE := 5
const IMPASSABLE := 99                # coste de movimiento del río (solo se cruza por vados y puentes)
const RIVER_EXTRA_TURNS := 2          # cruzar un río lleva tiempo: el asedio dura algo más

# --- Clima y hora: al azar en cada batalla, según el reino y la estación ---
const RAIN_ARCHER_FACTOR := 0.7
const RANGE_PENALTY := 1              # niebla o noche: los arqueros disparan una casilla menos
const MIN_ARCHER_RANGE := 2
const SNOW_CAV_MOVE_PENALTY := 1
const FOG_VISION := 3                 # con niebla solo se ve a los enemigos a esta distancia de tus pelotones
const NIGHT_VISION := 4

# --- Habilidades de mando: una vez por batalla para el comandante y cada compañero ---
# Cada una sale de alguna de sus habilidades de batalla ("skills").
const ABILITIES := {
	"grito": {"name": "Grito de guerra", "desc": "Todos tus pelotones ganan +15 de moral.",
		"skills": ["Grito de Guerra", "Estandarte Sagrado"]},
	"flechas": {"name": "Lluvia de flechas", "desc": "Cada pelotón de arqueros lanza una andanada extra, con una casilla más de alcance, sin gastar su turno.",
		"skills": ["Lluvia de Flechas", "Arqueros de Élite"]},
	"carga": {"name": "Carga de caballería", "desc": "Tu caballería avanza 2 casillas más este turno y su primer golpe es una carga (+30%).",
		"skills": ["Carga Letal", "Jinete Experto"]},
	"muro": {"name": "Muro de escudos", "desc": "Hasta tu próximo turno, tus pelotones reciben un 30% menos de bajas.",
		"skills": ["Muro de Escudos", "Táctica Defensiva", "Represalia"]},
	"reagrupar": {"name": "Reagrupar filas", "desc": "Tus pelotones recuperan 10 de moral y 25 de fatiga.",
		"skills": ["Reagrupar", "Disciplina de Hierro", "Logística"]},
	"emboscada": {"name": "Emboscada", "desc": "Tus pelotones en bosque o aldea golpean un 50% más en su próximo ataque.",
		"skills": ["Emboscada"]},
	"coordinado": {"name": "Ataque coordinado", "desc": "Este turno todos tus pelotones causan un 25% más de bajas.",
		"skills": ["Ataque Coordinado", "Maestro de Asedio"]},
}
const GRITO_MORALE := 15
const VOLLEY_FACTOR := 0.7
const VOLLEY_EXTRA_RANGE := 1
const CARGA_BONUS_MOVE := 2
const MURO_DEFENSE := 1.43            # ≈ 30% menos de bajas
const REAGRUPAR_MORALE := 10
const REAGRUPAR_FATIGUE := 25
const EMBOSCADA_SURGE := 1.5
const COORDINADO_POWER := 1.25

var weather: int = BattleEnums.Weather.DESPEJADO
var time_of_day: int = BattleEnums.TimeOfDay.DIA
var biome: int = -1                   # reino donde se combate (KingdomEnums.Kingdom); -1 = genérico
var map_feature: String = ""          # lo que distingue el campo: "un río con vado y puente", "una aldea"...
var random_conditions := true         # false: quien prepara la batalla fija el clima y la hora
# Mejoras del castillo asediado (ver Castle.wall_bonus y Castle.cavalry_bonus); se fijan antes de start_battle.
var wall_bonus: float = 0.0            # la defensa en la muralla se multiplica por (1 + wall_bonus)
var cavalry_bonus: Array = [0.0, 0]    # caballería que sale del castillo: [fuerza extra, moral extra]
var _used_abilities := {}             # Character -> habilidades de mando ya usadas (1 por batalla; 2 con el Olifante)
var _oriflamma_used := {}             # bando -> ya resistió su primer pelotón a punto de huir (Oriflama)
var _shield := {}                     # side -> factor de defensa mientras dura su Muro de escudos
var _power := {}                      # side -> multiplicador de bajas de este turno (Ataque coordinado)
var _path_cache := {}                 # casilla objetivo -> {casilla: coste del camino} (IA)

var terrain: Array = []              # terrain[x][y] -> BattleEnums.Terrain
var units: Array[BattleUnit] = []
var attacker_cmd: Character
var defender_cmd: Character
var player_side: int = BattleEnums.Side.ATACANTE
var has_walls: bool = true
var location_name: String = ""
var turn: int = 1
var max_turns: int = MAX_TURNS        # turnos del asedio (más si hay un río que cruzar)
var is_over: bool = false

var _initial_soldiers := {}
var _own_initial := 0

# --- Batallas ajenas: te invitan a unirte a un ejército (ver CombatSetup.invited) ---
const PLAYER_MAX_UNITS := 2           # en una batalla ajena llevas como mucho 2 pelotones (tú y tu séquito)...
const PLAYER_MAX_OWN_UNITS := 4       # ...o uno por cada compañero que te acompaña, hasta este tope
var player_leader: Character          # tu personaje; en una batalla ajena no es el comandante del bando
var ally_soldiers := 0                # parte de tu bando que mueve la IA aliada (fíjalo antes de start_battle)
# Hombres que el jugador asignó a cada uno de sus pelotones antes de la batalla: nombre del jefe -> soldados
# (tú y cada compañero; ver CombatSetup.platoon_max). Vacío = reparto automático. Fíjalo antes de start_battle.
var own_allocation: Dictionary = {}
const CAPTAIN_MIN_SOLDIERS := 5       # en tu propio ejército, lo que queda siempre para cada pelotón de capitán
var reuse_terrain := false            # true: start_battle conserva el campo ya generado (cambiar compañeros antes de empezar)
var retreating_side := -1             # bando que se retiró a tiempo (sus jefes en pie casi nunca caen presos)
var _own_companions := 0              # compañeros propios (no prestados) del jugador en esta batalla

# --- Competencia de la IA aliada (los pelotones de tu anfitrión que mueve la IA) ---
# Un jefe aliado corriente juega algo peor que el enemigo: a veces elige mal el objetivo, duda, avanza sin
# mirar el terreno o tarda en usar sus habilidades. Con Liderazgo + Estrategia altos juega como el enemigo.
const ALLY_SKILL_FULL := 28           # Liderazgo + Estrategia del jefe aliado para no cometer errores
const ALLY_SKILL_LOW := 14            # por debajo de esto, torpeza máxima
const ALLY_MAX_BLUNDER := 0.3         # probabilidad máxima de error en cada decisión de un pelotón aliado
const ALLY_HESITATE_SHARE := 0.5      # de los errores al moverse: la mitad dudan (no avanzan), el resto avanza sin mirar
const ALLY_HESITATE_SHARE_SIEGE := 0.1   # en un asedio dudar sale carísimo (se acaban los turnos): casi siempre avanzan sin mirar
var ally_competence_override := -1.0  # pruebas: 0..1 fija la competencia aliada (1 = igual que el enemigo)
var ally_blunders := 0                # errores de la IA aliada en esta batalla (para medir)

# --- Duelos singulares entre jefes (solo en campo abierto) ---
const CHALLENGE_MIN_HONOR := 40       # honor mínimo del jefe que lanza el reto
const CHALLENGE_ACCEPT_BASE := 0.7
const CHALLENGE_ACCEPT_BY_PERSONALITY := {
	Character.Personality.COBARDE: 0.25, Character.Personality.PRUDENTE: 0.5, Character.Personality.ASTUTO: 0.55,
	Character.Personality.ARROGANTE: 0.95, Character.Personality.VALIENTE: 0.95, Character.Personality.HONORABLE: 0.9,
	Character.Personality.CRUEL: 0.8,
}
const CHALLENGE_WEAKER_GAP := 4       # si el retado es así de peor luchador (combate + defensa)...
const CHALLENGE_WEAKER_PENALTY := 0.2 # ...se lo piensa más
const CHALLENGE_REFUSE_MORALE := 8    # rehusar un reto avergüenza a todo el bando
const CHALLENGE_WIN_MORALE := 10      # ver vencer a tu jefe enardece a los tuyos
const AI_CHALLENGE_CHANCE := 0.25     # cada turno, si la IA tiene a tiro un jefe al que cree poder vencer
const AI_CHALLENGE_MIN_EDGE := -2     # la IA no reta a quien le supera por más de esto
const AUTO_DUEL_MAX_TURNS := 40
const GENERAL_ACCEPT_FACTOR := 0.5     # un general acepta retos la mitad de las veces
const AI_GENERAL_CHALLENGE_EDGE := 4.0 # y la IA solo reta con su general si le saca esta ventaja

# --- Familias de tropa, comandancia y general ---
const ADVANTAGE_FACTOR := 1.3          # familia que aplasta a la del objetivo (círculo de ventajas)
const DISADVANTAGE_FACTOR := 0.8       # familia que ataca a su depredador
const RANGED_MELEE_FACTOR := 0.6       # arqueros y ballesteros cuerpo a cuerpo
const HEAVY_CHARGE_POWER := 1.35       # la caballería pesada carga con +35% (en vez del +30% de CHARGE_POWER)
const ARROW_RESIST := 1.3              # la infantería pesada aguanta las flechas (no las de ballesta)
const BASE_FAMILY_WEIGHTS := {BattleEnums.Family.INFANTERIA: 0.35, BattleEnums.Family.ARQUERIA: 0.25,
	BattleEnums.Family.CABALLERIA: 0.2, BattleEnums.Family.PIQUEROS: 0.2}
const MASTERY_WEIGHT_PER_LEVEL := 0.04 # el general recluta más de la tropa que domina
const VETERAN_MASTERY := 7             # desde este nivel del general, sus capitanes llevan la tropa avanzada
const MASTERY_POWER_PER_LEVEL := 0.02  # +2% de fuerza por nivel de mando del jefe del pelotón (sobre el 1)
const MASTERY_MORALE_PER_LEVEL := 2    # +2 de moral inicial por nivel
const MASTERY_SHARE_PER_LEVEL := 0.08  # los buenos mandos se llevan más soldados al repartir la tropa
const ASSIGN_BEST_BASE := 0.4          # el general te da tu mejor tropa con 40% + 6% por nivel de mando en ella
const ASSIGN_BEST_PER_LEVEL := 0.06
const GENERAL_POWER := 1.15            # la escolta del general: su pelotón golpea más...
const GENERAL_DEFENSE := 1.6           # ...y lo protegen mejor
# Escolta montada: ya tiene la movilidad y la carga de la caballería, así que su ventaja de escolta es menor
# (con la escolta completa, un general de caballería con mando 4 ganaba el 61% frente al ~43% del resto).
const GENERAL_MOUNTED_POWER := 1.05
const GENERAL_MOUNTED_DEFENSE := 1.4
const GENERAL_MORALE_LOSS := 0.4       # la escolta del general no se desmoraliza tan fácilmente
const GENERAL_MORALE := 10
const GENERAL_ESCORT_FAMILY := BattleEnums.Family.INFANTERIA   # escolta de un general cuya tropa es de tiro
const GENERAL_SHARE := 0.25            # soldados extra al repartir (el general es fuerte por su escolta, no por número)
const GENERAL_SCORE_FAME := 0.5        # puntuación del señor al elegir general: fama, mando y rango
const GENERAL_SCORE_LEADERSHIP := 2.0
const GENERAL_SCORE_STRATEGY := 1.5
const GENERAL_SCORE_RANK := 5.0
const MASTERY_XP_WIN := 30             # experiencia de mando de la familia que dirigiste
const MASTERY_XP_LOSS := 10
# Negociar tu tropa con el general (una vez por batalla).
const NEGOTIATE_BASE := 0.2
const NEGOTIATE_PER_MASTERY := 0.05
const NEGOTIATE_PER_CHARISMA := 0.015
const NEGOTIATE_PER_FAME := 0.003
const NEGOTIATE_PER_RELATION := 0.003
const NEGOTIATE_PER_STRATEGY := 0.01
const NEGOTIATE_MIN := 0.05
const NEGOTIATE_MAX := 0.95
const NEGOTIATE_FAIL_RELATION := 3
# Retirada: solo la ordena el general.
const AI_RETREAT_RATIO := 0.35         # el general de la IA se retira si le queda menos de esta parte...
const AI_RETREAT_EDGE := 1.5           # ...y el enemigo le dobla casi en número
const AI_RETREAT_MIN_TURN := 3
const COVER_TURNS := 2                 # turnos que aguantas cubriendo la retirada de tu bando
const COVER_HONOR := 12
const COVER_FAME := 8
const DESERT_HONOR := 10               # abandonar el campo sin orden del general
# Estrategia = leer al rival.
const VISION_STRATEGY_BASE := 5        # +1 casilla de visión con niebla o de noche por cada 5 puntos sobre 5...
const VISION_STRATEGY_STEP := 5
const VISION_STRATEGY_MAX := 2         # ...hasta +2
const INTENT_MIN_STRATEGY := 8         # desde aquí adivinas lo que harán los pelotones enemigos cercanos
const INTENT_RANGE_BASE := 2
const INTENT_STEP := 4                 # +1 casilla de lectura por cada 4 puntos sobre el mínimo
const ABILITY_STRATEGY_PIVOT := 10     # las habilidades de mando rinden un 3% más por punto de Estrategia sobre 10
const ABILITY_STRATEGY_PER_POINT := 0.02
const ABILITY_SCALE_MIN := 1.0 
const ABILITY_SCALE_MAX := 1.2
const TERRAIN_STRATEGY_PIVOT := 10     # +3% de defensa del terreno por punto de Estrategia sobre 10
const TERRAIN_STRATEGY_PER_POINT := 0.03
const TERRAIN_STRATEGY_CAP := 0.12
var pending_challenge: Dictionary = {} # {challenger, target}: la IA retó a uno de tus jefes y espera respuesta

# --- Traición en plena batalla ---
var betrayed_side := -1               # bando que traicionaste (-1 si nadie traicionó)
var betrayed_characters: Array[Character] = []   # quienes vieron tu traición desde el bando traicionado

enum { ABILITY_ANY, ABILITY_PLAYER, ABILITY_ALLY }
var wounded_companions: Array[String] = []   # nombres de compañeros heridos en esta batalla

var generals := {}                    # side -> Character: general del bando (lo elige su señor)
var negotiated := false               # ya pediste otra tropa al general en esta batalla
var player_family := -1              # tropa pactada para tu pelotón; sobrevive a rehacer el despliegue (-1: ninguna)
var pending_retreat := false          # el general de tu bando ordenó la retirada: ¿te vas o cubres?
var covering := false                 # te quedaste cubriendo la retirada
var cover_turns_left := 0
var deserted := false                 # abandonaste el campo sin orden del general
var mastery_gains: Array = []         # [nombre, familia, niveles ganados] al terminar

signal retreat_ordered(general: Character)
signal encounter_pending(enc: Dictionary)   # choque con tu grupo: se juega en la pantalla RPG (o «Resolver»)
signal unit_defected(u: BattleUnit)

# --- Fase 4: oficiales y choques RPG ---
var use_encounters := true             # cada choque cuerpo a cuerpo es un combate RPG (auto o jugado)
var interactive_encounters := false    # la pantalla de batalla juega los choques con tu grupo (si no, se resuelven solos)
var auto_resolve_others := true        # los choques ajenos (sin tu grupo) se resuelven solos
var pending_encounters: Array = []     # choques esperando a jugarse en la pantalla RPG
var encounter_hp := {}                 # Character -> parte de PV que le queda en esta batalla
var faction_officers := {}             # "player"/"enemy" -> Array[Character]: PNJ de la facción que van de oficiales
var player_is_officer := false         # vas de oficial en el pelotón de otro jefe (tu señor te asigna)

# --- Fase 4B: flancos, formaciones e IA más lista ---
const FLANK_DAMAGE := 1.25             # golpe por el flanco...
const REAR_DAMAGE := 1.5               # ...o por la espalda
const FLANK_MORALE := 4                # moral extra que pierde quien recibe por el flanco...
const REAR_MORALE := 8                 # ...o por la espalda
const CUNA_POWER := 1.2                # Cuña: golpea y carga más fuerte...
const CUNA_FLANK_DEFENSE := 0.8        # ...pero sus flancos aguantan peor
const CUADRO_POWER := 0.9              # Cuadro: golpea algo menos...
const CUADRO_DEFENSE := 1.1            # ...se defiende algo mejor...
const CUADRO_VS_CAVALRY := 1.35        # ...mucho mejor contra la caballería...
const CUADRO_MOVE := 1                 # ...se mueve una casilla menos y apenas tiene flancos
const AI_SMART_CHANCE := [0.55, 0.85, 1.0]   # Fácil, Normal, Difícil: cuántas veces la IA elige lo mejor
const AI_SLOPPY_CHANCE := [0.25, 0.0, 0.0]   # en Fácil, a veces golpea o avanza sin pensar
const AI_FLANK_WEIGHT := 2.0           # la IA busca casillas de flanco y espalda
const AI_ISOLATED_WEIGHT := 4.0        # y prefiere a los pelotones aislados...
const AI_GENERAL_TARGET := 3.0         # ...y al general enemigo
const AI_REGROUP_MORALE := 42          # con menos moral y el enemigo cerca, se repliega para reagruparse
const AI_REGROUP_DIST := 2
const AI_RESERVE_MIN_UNITS := 4        # con tantos pelotones, guarda uno en reserva
const AI_RESERVE_BEHIND := 2
const AI_RESERVE_TRIGGER := 3          # la reserva entra si el enemigo se acerca a esto de ella o del general...
const AI_RESERVE_TURN := 4             # ...desde este turno...
const AI_RESERVE_LOSING := 0.1         # ...o si su bando va perdiendo por esta parte de fuerza
const AI_ESCORT_MIN_UNITS := 3         # con tantos pelotones, uno escolta al general
const AI_ESCORT_RADIUS := 3            # la escolta ataca a quien se acerque a esto del general
var ai_difficulty := 1                 # 0 Fácil, 1 Normal, 2 Difícil (Ajustes)
var _ai_flank := false                 # la IA valora flanquear en esta decisión
var _roles_done := {}                  # bando -> ya repartió reserva y escolta
var player_officer_override := -1      # pruebas: 0/1 fija si vas de oficial
var abandon_chance_override := -1.0
var defect_chance_override := -1.0
var defections := 0

# --- Inicio ---

func start_battle(attacker_size: int, defender_size: int, walls: bool, a_cmd: Character, d_cmd: Character, place_name: String,
		player_companions: Array[Character] = [], enemy_companions: Array[Character] = []) -> void:
	attacker_cmd = a_cmd
	defender_cmd = d_cmd
	has_walls = walls
	location_name = place_name
	turn = 1
	ally_blunders = 0
	var reusing := reuse_terrain and not terrain.is_empty()
	if not reusing:
		max_turns = MAX_TURNS   # (con el campo reutilizado se conservan sus turnos: el río alarga el asedio)
	is_over = false
	units.clear()
	pending_challenge = {}
	betrayed_side = -1
	if not reusing:   # rehacer el despliegue antes del primer golpe no borra lo ya pactado
		negotiated = false
		player_family = -1
	pending_retreat = false
	covering = false
	cover_turns_left = 0
	deserted = false
	retreating_side = -1
	mastery_gains.clear()
	betrayed_characters.clear()
	pending_encounters.clear()
	encounter_hp.clear()
	defections = 0
	_own_companions = player_companions.filter(func(c: Character) -> bool: return c != null and not c.has_meta("faction_companion")).size()
	if player_leader == null:
		player_leader = _commander(player_side)
	_used_abilities.clear()
	_oriflamma_used.clear()
	_shield.clear()
	_power.clear()
	if random_conditions and not reusing:
		_roll_conditions()

	if not reusing:
		_generate_terrain()
	reuse_terrain = false
	for c: Character in [attacker_cmd, defender_cmd] + player_companions + enemy_companions:
		_seed_mastery(c)
	generals = {
		player_side: _pick_general(player_side, player_companions),
		_other_side(player_side): _pick_general(_other_side(player_side), enemy_companions),
	}
	_create_units(BattleEnums.Side.ATACANTE, attacker_size)
	_create_units(BattleEnums.Side.DEFENSOR, defender_size)
	wounded_companions.clear()
	_assign_companions(player_side, player_companions)
	_assign_companions(_other_side(player_side), enemy_companions)
	_assign_captains(BattleEnums.Side.ATACANTE)
	_assign_captains(BattleEnums.Side.DEFENSOR)
	_assign_officers(player_side, player_companions)
	_assign_officers(_other_side(player_side), enemy_companions)
	for side: int in [BattleEnums.Side.ATACANTE, BattleEnums.Side.DEFENSOR]:
		_assign_families(side)
		_mark_general(side)
		_share_soldiers(side)
		if side == player_side:
			_apply_allocation(side)
			_apply_player_family()
		_place_side(side)
	_mark_own_units()
	_roles_done.clear()
	for u: BattleUnit in units:
		u.facing = Vector2i(1, 0) if u.side == BattleEnums.Side.ATACANTE else Vector2i(-1, 0)
		u.formation = BattleEnums.Formation.LINEA
		u.reserve = false
		u.escort = false
	_initial_soldiers = {
		BattleEnums.Side.ATACANTE: total_soldiers(BattleEnums.Side.ATACANTE),
		BattleEnums.Side.DEFENSOR: total_soldiers(BattleEnums.Side.DEFENSOR),
	}
	_own_initial = _soldiers_own()

	log_message.emit("¡Comienza la batalla por %s! %d atacantes contra %d defensores." % [
		location_name, _initial_soldiers[BattleEnums.Side.ATACANTE], _initial_soldiers[BattleEnums.Side.DEFENSOR]])
	log_message.emit("Clima: %s" % conditions_text())
	if not map_feature.is_empty():
		log_message.emit("El campo de batalla: %s." % map_feature)
	if _has_skill(attacker_cmd, SKILL_GRITO_GUERRA):
		log_message.emit("%s lanza un Grito de Guerra: la moral de sus tropas se eleva." % attacker_cmd.full_name())

	# Si un lado no tiene tropas, la batalla se decide de inmediato.
	_check_end()
	state_updated.emit()

# Densidad de bosque y colinas y rasgos posibles del campo según la región.
const BIOME_STYLES := {
	"bosque": {"forest": 0.25, "hill": 0.06, "features": {"bosque espeso": 3.0, "río": 2.0, "aldea": 1.0}},
	"montaña": {"forest": 0.08, "hill": 0.25, "features": {"colinas": 3.0, "río": 1.0, "aldea": 1.0}},
	"hielo": {"forest": 0.08, "hill": 0.18, "features": {"río": 2.0, "colinas": 2.0, "aldea": 1.0}},
	"desierto": {"forest": 0.03, "hill": 0.2, "features": {"colinas": 2.0, "aldea": 2.0, "río": 0.5}},
	"llanura": {"forest": 0.13, "hill": 0.12, "features": {"río": 2.0, "aldea": 3.0, "bosque espeso": 1.0, "colinas": 1.0}},
}

func _biome_style() -> Dictionary:
	match biome:
		KingdomEnums.Kingdom.BOSQUE, KingdomEnums.Kingdom.ESMERALDA: return BIOME_STYLES["bosque"]
		KingdomEnums.Kingdom.CUMBRES, KingdomEnums.Kingdom.GRIS: return BIOME_STYLES["montaña"]
		KingdomEnums.Kingdom.HIELO: return BIOME_STYLES["hielo"]
		KingdomEnums.Kingdom.DESIERTO: return BIOME_STYLES["desierto"]
	return BIOME_STYLES["llanura"]

# Las zonas de despliegue (dos columnas por bando) quedan despejadas; la muralla, solo en los asedios.
# El centro varía según la región, y los asedios añaden un rasgo: un río con vados y puente, una aldea,
# un bosque espeso o una loma. Las escaramuzas son en campo abierto.
func _generate_terrain() -> void:
	terrain.clear()
	for x in range(GRID_W):
		var column: Array = []
		for y in range(GRID_H):
			column.append(BattleEnums.Terrain.MURALLA if has_walls and x >= GRID_W - WALL_COLUMNS else BattleEnums.Terrain.LLANO)
		terrain.append(column)
	var style: Dictionary = _biome_style()
	var last_col := GRID_W - WALL_COLUMNS - 1
	for x in range(2, last_col):
		for y in range(GRID_H):
			var r := randf()
			if r < style.forest:
				terrain[x][y] = BattleEnums.Terrain.BOSQUE
			elif r < style.forest + style.hill:
				terrain[x][y] = BattleEnums.Terrain.COLINA
	map_feature = ""
	if not has_walls:
		return
	match _weighted_key(style.features):
		"río": _add_river(last_col)
		"aldea": _add_village(last_col)
		"bosque espeso": _add_thick_forest(last_col)
		"colinas": _add_ridge(last_col)

func _weighted_key(weights: Dictionary) -> Variant:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := randf() * total
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return weights.keys().back()

# Un río que serpentea de arriba abajo: solo se cruza por un puente y uno o dos vados.
func _add_river(last_col: int) -> void:
	var x := randi_range(4, 6)
	var rows_with_river := []
	for y in range(GRID_H):
		var cols := [x]
		if y > 0 and randf() < 0.3:
			var nx := clampi(x + [-1, 1].pick_random(), 3, last_col - 2)
			if nx != x:
				cols.append(nx)
				x = nx
		for c in cols:
			terrain[c][y] = BattleEnums.Terrain.RIO
		rows_with_river.append(cols)
	var rows := range(GRID_H)
	rows.shuffle()
	var crossings: Array[int] = []
	var wanted := randi_range(3, 4)
	for y in rows:
		if crossings.size() >= wanted:
			break
		if crossings.all(func(c: int) -> bool: return absi(c - y) >= 2):
			crossings.append(y)
	for i in crossings.size():
		for c in rows_with_river[crossings[i]]:
			terrain[c][crossings[i]] = BattleEnums.Terrain.PUENTE if i == 0 else BattleEnums.Terrain.VADO
	map_feature = "un río que solo se cruza por el puente y %d vados" % (crossings.size() - 1)
	max_turns = MAX_TURNS + RIVER_EXTRA_TURNS

func _add_village(last_col: int) -> void:
	var cx := randi_range(4, last_col - 2)
	var cy := randi_range(1, GRID_H - 3)
	for cell in [Vector2i(cx, cy), Vector2i(cx + 1, cy), Vector2i(cx, cy + 1), Vector2i(cx + 1, cy + 1), Vector2i(cx + [-1, 2].pick_random(), cy + randi_range(0, 1))]:
		if cell.x >= 2 and cell.x < last_col:
			terrain[cell.x][cell.y] = BattleEnums.Terrain.ALDEA
	map_feature = "una aldea en medio del camino (defensa +30%)"

# Bosque cerrado con un camino despejado que lo atraviesa.
func _add_thick_forest(last_col: int) -> void:
	var road := randi_range(1, GRID_H - 2)
	for x in range(3, last_col):
		for y in range(GRID_H):
			if y == road:
				terrain[x][y] = BattleEnums.Terrain.LLANO
			elif randf() < 0.45:
				terrain[x][y] = BattleEnums.Terrain.BOSQUE
	map_feature = "un bosque espeso que solo un camino atraviesa"

# Una loma que cruza el campo, con un par de pasos llanos.
func _add_ridge(last_col: int) -> void:
	var x := randi_range(4, last_col - 2)
	var gaps := [randi_range(0, GRID_H - 1), randi_range(0, GRID_H - 1)]
	for y in range(GRID_H):
		terrain[x][y] = BattleEnums.Terrain.LLANO if y in gaps else BattleEnums.Terrain.COLINA
	map_feature = "una loma que domina el campo (arqueros en lo alto: +1 de alcance)"

# --- Clima y hora ---

func _roll_conditions() -> void:
	# Sin el árbol de escenas (pruebas sueltas) se toma un mes de verano.
	var gm: Node = Engine.get_main_loop().root.get_node_or_null("GameManager") if Engine.get_main_loop() is SceneTree else null
	var month: int = gm.current_month if gm != null else 6
	var winter := month in [12, 1, 2]
	var cold := biome in [KingdomEnums.Kingdom.HIELO, KingdomEnums.Kingdom.CUMBRES]
	var dry := biome == KingdomEnums.Kingdom.DESIERTO
	var wet := biome in [KingdomEnums.Kingdom.BOSQUE, KingdomEnums.Kingdom.ESMERALDA, KingdomEnums.Kingdom.AZUL]
	var snow := 0.0
	if cold:
		snow = 5.0 if winter else 1.5
	elif winter and not dry:
		snow = 1.5
	var w := {
		BattleEnums.Weather.DESPEJADO: 5.0,
		BattleEnums.Weather.LLUVIA: 0.3 if dry else (2.5 if wet else 1.5),
		BattleEnums.Weather.NIEBLA: 0.3 if dry else (2.0 if wet else 1.0),
		BattleEnums.Weather.NIEVE: snow,
	}
	weather = int(_weighted_key(w))
	time_of_day = int(_weighted_key({BattleEnums.TimeOfDay.DIA: 6.0, BattleEnums.TimeOfDay.ATARDECER: 2.0, BattleEnums.TimeOfDay.NOCHE: 2.0}))

## Distancia a la que se ve a los enemigos (0 = sin límite): niebla y noche la reducen.
func vision_range() -> int:
	var v := 0
	if weather == BattleEnums.Weather.NIEBLA:
		v = FOG_VISION
	if time_of_day == BattleEnums.TimeOfDay.NOCHE:
		v = NIGHT_VISION if v == 0 else mini(v, NIGHT_VISION)
	return v

## ¿Ve el bando "side" a este pelotón? Con niebla o de noche, solo si alguno de los suyos está cerca.
func is_visible_to(side: int, u: BattleUnit) -> bool:
	var v := vision_range_for(side)
	if v == 0 or u.side == side:
		return true
	for own: BattleUnit in active_units(side):
		if distance(own.cell, u.cell) <= v:
			return true
	return false

## Clima, hora y lo que suponen, para mostrarlo al empezar.
func conditions_text() -> String:
	var effects: Array[String] = []
	match weather:
		BattleEnums.Weather.LLUVIA: effects.append("los arqueros causan un 30% menos de bajas")
		BattleEnums.Weather.NIEVE: effects.append("la caballería avanza una casilla menos")
	if weather == BattleEnums.Weather.NIEBLA or time_of_day == BattleEnums.TimeOfDay.NOCHE:
		effects.append("los arqueros disparan una casilla menos y solo ves a los enemigos a %d casillas de tus tropas" % vision_range())
	var head := "%s · %s" % [BattleEnums.weather_name(weather), BattleEnums.time_name(time_of_day)]
	return head + (" — " + "; ".join(effects) if not effects.is_empty() else " — sin efectos en el combate")

func _create_units(side: int, total: int) -> void:
	if total <= 0:
		return
	# [soldados, pelotones como mucho, aliado]: en una batalla ajena tus pelotones y los de tu anfitrión van aparte.
	var groups: Array = [[total, MAX_UNITS_PER_SIDE, false]]
	if side == player_side and ally_soldiers <= 0 and not own_allocation.is_empty():
		groups = [[total, MAX_UNITS_PER_SIDE, false, own_allocation.size()]]   # un pelotón por cada jefe tuyo, como poco
	if side == player_side and ally_soldiers > 0:
		var mine: int = maxi(0, total - ally_soldiers)
		# Tu pelotón y uno por cada compañero que te acompaña (todos los mueves tú).
		var wanted: int = maxi(ceili(mine / float(SOLDIERS_PER_UNIT)), 1 + _own_companions)
		var own_units: int = clampi(wanted, 1, maxi(PLAYER_MAX_UNITS, mini(PLAYER_MAX_OWN_UNITS, 1 + _own_companions))) if mine > 0 else 0
		if not own_allocation.is_empty() and mine > 0:
			own_units = mini(own_allocation.size(), PLAYER_MAX_OWN_UNITS)
		# Tus pelotones no le quitan sitio al anfitrión: su ejército conserva su número natural de pelotones
		# (si se apretara en dos pelotones de 50, apenas huiría y cada compañero valdría ~+18% de victoria).
		var ally_units: int = clampi(ceili(ally_soldiers / float(SOLDIERS_PER_UNIT)), 1, mini(MAX_UNITS_PER_SIDE, MAX_UNITS_WITH_ALLIES - own_units))
		groups = [[mine, own_units, false, own_units if not own_allocation.is_empty() else 1 + _own_companions], [ally_soldiers, ally_units, true, 1]]
	var start_morale := _start_morale(side)

	for g: Array in groups:
		var amount: int = g[0]
		if amount <= 0 or g[1] <= 0:
			continue
		# Al menos tantos pelotones como jefes propios (tú y tus compañeros), sin pasar de los soldados que hay.
		var min_count: int = mini(int(g[3]) if g.size() > 3 else 1, amount)
		var count: int = clampi(maxi(ceili(amount / float(SOLDIERS_PER_UNIT)), min_count), 1, g[1])
		var types := _composition(side, count)
		var per_unit: int = amount / count
		var remainder: int = amount % count
		for i in range(count):
			var u := BattleUnit.new()
			u.side = side
			u.type = types[i]
			u.ally = g[2]
			u.soldiers = per_unit + (1 if i < remainder else 0)
			u.max_soldiers = u.soldiers
			u.morale = start_morale
			if side == BattleEnums.Side.DEFENSOR and has_walls and BattleEnums.is_cavalry(u.type):
				u.morale = clampi(start_morale + int(cavalry_bonus[1]), 0, 100)
			units.append(u)
	_place_side(side)

## Coloca un bando: infantería, piqueros y caballería en primera línea; arqueros, ballesteros y el general detrás.
func _place_side(side: int) -> void:
	var front_col: int = 1 if side == BattleEnums.Side.ATACANTE else GRID_W - 2
	var back_col: int = 0 if side == BattleEnums.Side.ATACANTE else GRID_W - 1
	var front: Array[BattleUnit] = []
	var back: Array[BattleUnit] = []
	for u: BattleUnit in units:
		if u.side != side:
			continue
		if BattleEnums.is_ranged(u.type) or u.general:
			back.append(u)   # los tiradores y el general (con su escolta) en la retaguardia
		else:
			front.append(u)
	_place_column(front, front_col)
	_place_column(back, back_col)

func _start_morale(side: int) -> int:
	var commander := _commander(side)
	var start_morale: int = BASE_MORALE + (commander.leadership if commander != null else 5)
	if _has_skill(commander, SKILL_GRITO_GUERRA):
		start_morale += GRITO_GUERRA_MORALE
	# Táctica Defensiva: tras la muralla, los defensores se sienten más seguros.
	if side == BattleEnums.Side.DEFENSOR and has_walls and _has_skill(commander, SKILL_TACTICA_DEFENSIVA):
		start_morale += TACTICA_DEFENSIVA_WALL_MORALE
	start_morale += roundi(SkillEffects.fx(commander, "morale_start"))
	return clampi(start_morale, 0, 100)

## Tropas de un bando: el reparto base de familias, inclinado hacia lo que domina su general.
## Siempre hay al menos un pelotón de infantería o piqueros en primera línea.
func _composition(side: int, count: int) -> Array[int]:
	var gen := general_of(side)
	var weights := {}
	var total := 0.0
	for f: int in BASE_FAMILY_WEIGHTS:
		var w: float = BASE_FAMILY_WEIGHTS[f]
		if gen != null:
			w *= 1.0 + MASTERY_WEIGHT_PER_LEVEL * (gen.mastery(f) - 1)
		weights[f] = w
		total += w
	# Reparto por restos mayores: determinista para un mismo general.
	var counts := {}
	var given := 0
	var rests: Array = []
	for f: int in weights:
		var exact: float = count * weights[f] / total
		counts[f] = int(floor(exact))
		given += counts[f]
		rests.append([exact - counts[f], f])
	rests.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for i in count - given:
		counts[rests[i % rests.size()][1]] += 1
	if counts[BattleEnums.Family.INFANTERIA] + counts[BattleEnums.Family.PIQUEROS] == 0:
		var donor: int = BattleEnums.Family.ARQUERIA if counts[BattleEnums.Family.ARQUERIA] > 0 else BattleEnums.Family.CABALLERIA
		counts[donor] -= 1
		counts[BattleEnums.Family.INFANTERIA] += 1
	var result: Array[int] = []
	for f: int in [BattleEnums.Family.INFANTERIA, BattleEnums.Family.PIQUEROS, BattleEnums.Family.ARQUERIA, BattleEnums.Family.CABALLERIA]:
		var advanced := gen != null and gen.mastery(f) >= VETERAN_MASTERY
		for i in counts[f]:
			result.append(BattleEnums.advanced_type(f) if advanced else BattleEnums.basic_type(f))
	return result

func _place_column(group: Array[BattleUnit], column: int) -> void:
	var start_y: int = (GRID_H - group.size()) / 2
	for i in range(group.size()):
		group[i].cell = Vector2i(column, start_y + i)

# --- Consultas ---

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID_W and cell.y < GRID_H

func terrain_at(cell: Vector2i) -> int:
	return terrain[cell.x][cell.y]

func unit_at(cell: Vector2i) -> BattleUnit:
	for u: BattleUnit in units:
		if u.is_active() and u.cell == cell:
			return u
	return null

func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func active_units(side: int) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for u: BattleUnit in units:
		if u.side == side and u.is_active():
			result.append(u)
	return result

func total_soldiers(side: int) -> int:
	# Incluye pelotones en huida: esos soldados se reagrupan después de la batalla.
	var sum := 0
	for u: BattleUnit in units:
		if u.side == side:
			sum += u.soldiers
	return sum

## Pelotón que mueves tú (no los aliados de la IA que luchan a tu lado).
func is_player_unit(u: BattleUnit) -> bool:
	return u != null and u.side == player_side and not u.ally

## De tu bando, lo muevas tú o la IA aliada.
func is_friendly(u: BattleUnit) -> bool:
	return u != null and u.side == player_side

## ¿Luchan a tu lado pelotones que mueve la IA (batalla ajena)?
func has_allies() -> bool:
	for u: BattleUnit in units:
		if u.side == player_side and u.ally and u.is_active():
			return true
	return false

func can_move(u: BattleUnit) -> bool:
	return not is_over and u.is_active() and not u.has_moved and not u.has_acted and u.order != BattleEnums.Order.MANTENER

func can_attack(u: BattleUnit) -> bool:
	return not is_over and u.is_active() and not u.has_acted

func move_cost(u: BattleUnit, cell: Vector2i) -> int:
	var cavalry := BattleEnums.is_cavalry(u.type)
	match terrain_at(cell):
		BattleEnums.Terrain.BOSQUE: return 3 if cavalry else 2
		BattleEnums.Terrain.COLINA: return 2
		BattleEnums.Terrain.MURALLA: return 3 if cavalry else 2
		BattleEnums.Terrain.RIO: return IMPASSABLE
		BattleEnums.Terrain.VADO: return 3 if cavalry else 2
		BattleEnums.Terrain.ALDEA: return 2 if cavalry else 1
	return 1

func effective_move_range(u: BattleUnit) -> int:
	var r := u.move_range()
	r += u.bonus_move
	if BattleEnums.is_cavalry(u.type):
		r += roundi(_unit_fx(u, "cav_move"))
		if weather == BattleEnums.Weather.NIEVE:
			r -= SNOW_CAV_MOVE_PENALTY
	# Las tropas muy fatigadas avanzan más lento.
	if u.formation == BattleEnums.Formation.CUADRO:
		r = maxi(1, r - CUADRO_MOVE)
	if u.fatigue >= 70:
		return maxi(1, r - 1)
	return r

func effective_attack_range(u: BattleUnit) -> int:
	return _range_from(u, u.cell)

# Alcance que tendría el pelotón desde esa casilla (la IA lo usa para colocarse).
func _range_from(u: BattleUnit, cell: Vector2i) -> int:
	var r := u.attack_range()
	if BattleEnums.is_ranged(u.type):
		r += roundi(_unit_fx(u, "arch_range"))
		if terrain_at(cell) in [BattleEnums.Terrain.COLINA, BattleEnums.Terrain.MURALLA]:
			r += 1   # la altura da alcance extra a los arqueros
		if weather == BattleEnums.Weather.NIEBLA or time_of_day == BattleEnums.TimeOfDay.NOCHE:
			r = maxi(MIN_ARCHER_RANGE, r - RANGE_PENALTY)
	return r

func reachable_cells(u: BattleUnit) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not can_move(u):
		return result
	var budget := effective_move_range(u)
	var best := {u.cell: 0}
	var frontier: Array[Vector2i] = [u.cell]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for dir in DIRS:
			var next: Vector2i = current + dir
			if not in_bounds(next) or unit_at(next) != null:
				continue
			var cost: int = best[current] + move_cost(u, next)
			if cost > budget:
				continue
			if best.has(next) and best[next] <= cost:
				continue
			best[next] = cost
			frontier.append(next)
	for cell in best.keys():
		if cell != u.cell:
			result.append(cell)
	return result

func targets_in_range(u: BattleUnit) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	if not u.is_active():
		return result
	var r := effective_attack_range(u)
	for other: BattleUnit in units:
		if other.side != u.side and other.is_active() and distance(u.cell, other.cell) <= r and is_visible_to(u.side, other):
			result.append(other)
	return result

# --- Acciones ---

func move_unit(u: BattleUnit, cell: Vector2i) -> bool:
	if not cell in reachable_cells(u):
		return false
	u.last_move_distance = distance(u.cell, cell)
	_face(u, cell)
	u.cell = cell
	u.has_moved = true
	u.fatigue = mini(100, u.fatigue + _fatigue_gain(u, 8 if BattleEnums.is_cavalry(u.type) else 5))
	state_updated.emit()
	return true

func attack(attacker: BattleUnit, target: BattleUnit) -> bool:
	if not can_attack(attacker) or not target in targets_in_range(attacker):
		return false

	var dist := distance(attacker.cell, target.cell)
	_face(attacker, target.cell)
	if use_encounters and dist == 1:
		return _encounter(attacker, target, dist)
	var flank := flank_of(attacker, target)
	var casualties := _compute_casualties(attacker, target, dist, true)
	_apply_casualties(target, casualties)
	var text := "%s (%s) ataca a %s (%s): %d bajas." % [
		BattleEnums.unit_type_name(attacker.type), _side_label(attacker.side),
		BattleEnums.unit_type_name(target.type), _side_label(target.side), casualties]
	text += _flank_morale(target, flank)
	# La carga y los golpes reforzados se gastan con el primer golpe.
	var charged := attacker.order == BattleEnums.Order.CARGAR and dist == 1
	if charged:
		text = "¡Carga! " + text
		attacker.order = BattleEnums.Order.NINGUNA
	attacker.surge = 1.0

	# Respuesta cuerpo a cuerpo: el defensor devuelve parte del golpe si sigue en pie
	# (salvo ante una carga de caballería con Carga Letal).
	var counter := 0
	if _is_charge(attacker):
		text += " ¡La carga los arrolla sin darles tiempo a responder!"
	elif dist == 1 and target.is_active() and not BattleEnums.is_ranged(target.type):
		counter = int(_compute_casualties(target, attacker, dist, true) * _retaliation(target))
		if counter > 0:
			_apply_casualties(attacker, counter)
			text += " Responden causando %d bajas." % counter
	unit_attacked.emit(attacker, target, casualties, counter, dist > 1)

	attacker.has_acted = true
	attacker.has_moved = true
	attacker.fatigue = mini(100, attacker.fatigue + _fatigue_gain(attacker, roundi(10 * CHARGE_FATIGUE) if charged else 10))
	log_message.emit(text)

	_check_rout(target)
	_check_rout(attacker)
	_check_end()
	state_updated.emit()
	return true

# --- Órdenes ---

## Mantener posición (no se mueve y recibe menos bajas) o Cargar (su primer golpe cuerpo a cuerpo hace
## más daño, pero se cansa más). Dar la misma orden otra vez la anula. No gasta el turno del pelotón.
func set_order(u: BattleUnit, order: int) -> bool:
	if is_over or not u.is_active() or u.has_acted:
		return false
	if order == BattleEnums.Order.CARGAR and BattleEnums.is_ranged(u.type):
		return false
	u.order = BattleEnums.Order.NINGUNA if u.order == order else order
	if u.order != BattleEnums.Order.NINGUNA:
		log_message.emit("%s (%s): «%s»." % [BattleEnums.unit_type_name(u.type), _side_label(u.side), BattleEnums.order_name(u.order)])
	state_updated.emit()
	return true

## Formación del pelotón (Línea, Cuña, Cuadro). No gasta el turno.
func set_formation(u: BattleUnit, f: int) -> bool:
	if is_over or not u.is_active() or u.has_acted:
		return false
	u.formation = f
	log_message.emit("%s (%s): formación en %s." % [BattleEnums.unit_type_name(u.type), _side_label(u.side), BattleEnums.formation_name(f)])
	state_updated.emit()
	return true

## Pasa a la siguiente formación: Línea → Cuña → Cuadro → Línea.
func cycle_formation(u: BattleUnit) -> bool:
	return set_formation(u, (u.formation + 1) % BattleEnums.Formation.size())

## 0 = de frente, 1 = por el flanco, 2 = por la espalda, según hacia dónde mira el objetivo.
## El Cuadro apenas tiene flancos: le quita un nivel. from_cell: desde otra casilla (la IA lo usa).
func flank_of(attacker: BattleUnit, target: BattleUnit, from_cell: Vector2i = Vector2i(-99, -99)) -> int:
	var c := attacker.cell if from_cell == Vector2i(-99, -99) else from_cell
	var d := c - target.cell
	var f := target.facing
	var along := d.x * f.x + d.y * f.y
	var across := absi(d.x * f.y - d.y * f.x)
	var level := 0 if along >= across else (2 if -along >= across else 1)
	if target.formation == BattleEnums.Formation.CUADRO:
		level = maxi(0, level - 1)
	return level

## Mira hacia la casilla (eje dominante).
func _face(u: BattleUnit, toward: Vector2i) -> void:
	var d := toward - u.cell
	if d == Vector2i.ZERO:
		return
	u.facing = Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))

## Moral extra que pierde quien recibe por el flanco o la espalda; devuelve el texto para el registro.
func _flank_morale(target: BattleUnit, flank: int) -> String:
	if flank <= 0 or not target.is_active():
		return ""
	target.morale = maxi(0, target.morale - (REAR_MORALE if flank == 2 else FLANK_MORALE))
	return " ¡Por la espalda!" if flank == 2 else " ¡Por el flanco!"

func can_withdraw(u: BattleUnit) -> bool:
	return not is_over and u.is_active() and not u.has_moved and not u.has_acted

## Replegarse: el pelotón retrocede hacia su retaguardia, recompone filas (moral) y gasta su turno.
func withdraw(u: BattleUnit) -> bool:
	if not can_withdraw(u):
		return false
	u.order = BattleEnums.Order.NINGUNA
	var back := -1 if u.side == BattleEnums.Side.ATACANTE else 1
	var best := u.cell
	var best_score := 0.0
	for cell in reachable_cells(u):
		if distance(u.cell, cell) > WITHDRAW_STEPS:
			continue
		var score := (cell.x - u.cell.x) * back * 10.0 - absi(cell.y - u.cell.y) + (_terrain_defense(terrain_at(cell)) - 1.0) * 5.0
		if score > best_score:
			best_score = score
			best = cell
	u.cell = best
	u.last_move_distance = 0
	u.has_moved = true
	u.has_acted = true
	var gain := WITHDRAW_MORALE + roundi(_unit_fx(u, "rally"))
	u.morale = mini(100, u.morale + gain)
	u.fatigue = maxi(0, u.fatigue - WITHDRAW_FATIGUE)
	log_message.emit("%s (%s) se repliega y recompone filas (moral +%d)." % [BattleEnums.unit_type_name(u.type), _side_label(u.side), gain])
	state_updated.emit()
	return true

# --- Habilidades de mando ---

## Habilidades de mando (ids de ABILITIES) que dan las habilidades de batalla de un personaje.
func abilities_of(c: Character) -> Array[String]:
	var result: Array[String] = []
	if c == null:
		return result
	for id: String in ABILITIES:
		for sk: Skill in c.battle_skills:
			if sk != null and sk.skill_name in ABILITIES[id].skills and not id in result:
				result.append(id)
	return result

## Quienes pueden usar una habilidad en este bando: el comandante y los compañeros aún al mando.
## En tu bando, "group" distingue lo que mandas tú (ABILITY_PLAYER) de lo que manda la IA aliada (ABILITY_ALLY).
func ability_users(side: int, group: int = ABILITY_ANY) -> Array[Character]:
	var result: Array[Character] = []
	var allied_battle := side == player_side and has_allies()
	var cmd := _commander(side)
	# En una batalla ajena el comandante es tu anfitrión: sus órdenes las da la IA aliada.
	if cmd != null and not abilities_of(cmd).is_empty() and _group_ok(group, ABILITY_ALLY if allied_battle else ABILITY_PLAYER, side):
		result.append(cmd)
	for u: BattleUnit in active_units(side):
		var c: Character = u.companion
		if c == null and allied_battle and not u.ally and u.captain == player_leader:
			c = player_leader
		if c == null or c in result or abilities_of(c).is_empty():
			continue
		if _group_ok(group, ABILITY_ALLY if u.ally else ABILITY_PLAYER, side):
			result.append(c)
	return result

func _group_ok(group: int, member_group: int, side: int) -> bool:
	return group == ABILITY_ANY or side != player_side or group == member_group

func ability_used_by(c: Character) -> bool:
	return int(_used_abilities.get(c, 0)) >= _ability_limit(c)

# Una habilidad de mando por batalla; el Olifante (pieza única) da una más.
func _ability_limit(c: Character) -> int:
	return 2 if SkillEffects.has_unique(c, SkillEffects.UNIQUE_OLIFANT) else 1

func can_use_ability(c: Character, id: String, side: int) -> bool:
	return not is_over and not ability_used_by(c) and id in abilities_of(c) and c in ability_users(side)

func use_ability(c: Character, id: String, side: int) -> bool:
	if not can_use_ability(c, id, side):
		return false
	_used_abilities[c] = int(_used_abilities.get(c, 0)) + 1
	var own := active_units(side)
	log_message.emit("%s ordena: «%s». %s" % [c.full_name(), ABILITIES[id].name, ABILITIES[id].desc])
	ability_used.emit(c, id, side)
	var k := ability_scale(c)
	match id:
		"grito":
			for u: BattleUnit in own:
				u.morale = mini(100, u.morale + roundi(GRITO_MORALE * k))
		"flechas":
			for u: BattleUnit in own:
				if BattleEnums.is_ranged(u.type):
					_volley(u, k)
		"carga":
			for u: BattleUnit in own:
				if BattleEnums.is_cavalry(u.type):
					u.bonus_move += CARGA_BONUS_MOVE
					u.order = BattleEnums.Order.CARGAR
		"muro":
			_shield[side] = 1.0 + (MURO_DEFENSE - 1.0) * k
		"reagrupar":
			for u: BattleUnit in own:
				u.morale = mini(100, u.morale + roundi(REAGRUPAR_MORALE * k))
				u.fatigue = maxi(0, u.fatigue - roundi(REAGRUPAR_FATIGUE * k))
		"emboscada":
			for u: BattleUnit in own:
				if terrain_at(u.cell) in [BattleEnums.Terrain.BOSQUE, BattleEnums.Terrain.ALDEA]:
					u.surge = 1.0 + (EMBOSCADA_SURGE - 1.0) * k
		"coordinado":
			_power[side] = 1.0 + (COORDINADO_POWER - 1.0) * k
	_check_end()
	state_updated.emit()
	return true

# Andanada gratuita de un pelotón de arqueros contra el enemigo visible más cercano a su alcance (+1).
func _volley(u: BattleUnit, k: float = 1.0) -> void:
	var best: BattleUnit = null
	var reach := effective_attack_range(u) + VOLLEY_EXTRA_RANGE
	for e: BattleUnit in active_units(_other_side(u.side)):
		var d := distance(u.cell, e.cell)
		if d <= reach and is_visible_to(u.side, e) and (best == null or d < distance(u.cell, best.cell)):
			best = e
	if best == null:
		return
	var dmg := maxi(1, roundi(_compute_casualties(u, best, maxi(2, distance(u.cell, best.cell)), true) * VOLLEY_FACTOR * k))
	_apply_casualties(best, dmg)
	unit_attacked.emit(u, best, dmg, 0, true)
	log_message.emit("La andanada cae sobre %s (%s): %d bajas." % [BattleEnums.unit_type_name(best.type), _side_label(best.side), dmg])
	_check_rout(best)

# Vista previa sin azar de un ataque: bajas esperadas para el objetivo y la respuesta que sufriría el atacante.
func preview_attack(attacker: BattleUnit, target: BattleUnit) -> Dictionary:
	var dist := distance(attacker.cell, target.cell)
	var casualties := _compute_casualties(attacker, target, dist, false)
	var counter := 0
	if dist == 1 and casualties < target.soldiers and not BattleEnums.is_ranged(target.type) and not _is_charge(attacker):
		counter = int(_compute_casualties(target, attacker, dist, false) * _retaliation(target))
	return {"casualties": casualties, "counter": counter}

func _is_charge(attacker: BattleUnit) -> bool:
	return BattleEnums.is_cavalry(attacker.type) and attacker.last_move_distance >= CARGA_MIN_DISTANCE \
		and _has_skill(_commander(attacker.side), SKILL_CARGA_LETAL)

## Proporción de soldados perdidos por ambos bandos (0 al empezar), para la intensidad de la música.
func casualty_fraction() -> float:
	var initial: int = _initial_soldiers.get(BattleEnums.Side.ATACANTE, 0) + _initial_soldiers.get(BattleEnums.Side.DEFENSOR, 0)
	if initial <= 0:
		return 0.0
	var now := total_soldiers(BattleEnums.Side.ATACANTE) + total_soldiers(BattleEnums.Side.DEFENSOR)
	return 1.0 - float(now) / initial

func end_player_turn() -> void:
	if is_over or not pending_challenge.is_empty() or pending_retreat:
		return
	var ai_side := _other_side(player_side)

	# Tus aliados mueven después de ti (y sus jefes también retan).
	if has_allies():
		_ai_try_challenge(player_side)
		if is_over:
			return
		_run_ai(player_side)
		if is_over:
			return
	_rest_side(player_side)
	_reset_side(ai_side)
	if _ai_try_challenge(ai_side):
		return   # la IA retó a uno de tus jefes: el turno sigue con answer_challenge()
	_enemy_phase()

func _enemy_phase() -> void:
	if is_over:
		return
	var ai_side := _other_side(player_side)
	_run_ai(ai_side)
	if is_over:
		return
	_rest_side(ai_side)

	turn += 1
	if covering:
		cover_turns_left -= 1
		if cover_turns_left <= 0:
			_end_battle(_other_side(player_side), "Cubriste la retirada de tu bando: el enemigo se queda con el campo, pero los tuyos se salvaron.")
			return
	if turn > max_turns:
		if not has_walls:
			# En campo abierto cae la noche: se queda el campo quien ha ganado el intercambio (ha perdido menos hombres).
			# Antes contaba la parte del ejército que quedaba, y eso premiaba al mayor aunque el cambio fuera parejo.
			var keep := _night_winner()
			_end_battle(keep, "Cae la noche sobre el campo: %s ha sufrido menos bajas y se queda con él." % ("tu bando" if keep == player_side else "el enemigo"))
			return
		# Asedio al límite de turnos: si la guarnición está deshecha y el asaltante sigue entero, el castillo cae.
		if _strength_ratio(BattleEnums.Side.DEFENSOR) < SIEGE_BREAK_RATIO 				and _strength_ratio(BattleEnums.Side.ATACANTE) > _strength_ratio(BattleEnums.Side.DEFENSOR):
			_end_battle(BattleEnums.Side.ATACANTE, "La guarnición de %s, diezmada, rinde el castillo al caer la noche." % location_name)
			return
		_end_battle(BattleEnums.Side.DEFENSOR, "El asedio se prolonga demasiado y los atacantes deben levantar el campamento.")
		return
	if _ai_general_retreats(_other_side(player_side)):
		var g := general_of(_other_side(player_side))
		retreating_side = _other_side(player_side)
		_end_battle(player_side, "%s, general enemigo, ordena la retirada: el campo es vuestro." % (g.full_name() if g != null else "El general enemigo"))
		return
	if has_allies() and not covering and _ai_general_retreats(player_side):
		pending_retreat = true
		var g := general_of(player_side)
		log_message.emit("%s ordena la retirada." % (g.full_name() if g != null else "Tu general"))
		retreat_ordered.emit(g)
	_check_defections()
	if is_over:
		return
	_reset_side(player_side)
	log_message.emit("— Turno %d de %d —" % [turn, max_turns])
	state_updated.emit()

func retreat() -> void:
	if is_over:
		return
	if not has_allies() or is_player_general():
		retreating_side = player_side
		_end_battle(_other_side(player_side), "Tus tropas se retiran del campo de batalla.")
		return
	# En una batalla ajena solo el general ordena la retirada: irte por tu cuenta es desertar.
	deserted = true
	pending_challenge = {}
	for u: BattleUnit in active_units(player_side):
		if not u.ally:
			_withdraw_from_field(u, "%s (%s) abandona el campo: la batalla sigue sin ti." % [BattleEnums.unit_type_name(u.type), _side_label(u.side)])
	var guard := 0
	while not is_over and guard < MAX_TURNS * 3:
		end_player_turn()
		guard += 1
	if not is_over:
		_check_end()

# --- Cálculo de combate ---

func _compute_casualties(attacker: BattleUnit, target: BattleUnit, dist: int, with_variance: bool) -> int:
	var strength: float = attacker.soldiers * _base_power(attacker.type)
	strength *= _matchup(attacker.type, target.type, dist)
	if BattleEnums.is_cavalry(attacker.type) and _has_skill(_commander(attacker.side), SKILL_CARGA_LETAL):
		strength *= CARGA_LETAL_FACTOR
	strength *= 0.5 + attacker.morale / 200.0          # 0.5 .. 1.0
	strength *= 1.0 - attacker.fatigue / 250.0         # 1.0 .. 0.6
	var cmd := _commander(attacker.side)
	if cmd != null:
		strength *= 1.0 + (cmd.leadership + cmd.strategy) / COMMANDER_DIVISOR
	strength *= 1.0 + MASTERY_POWER_PER_LEVEL * (_unit_mastery(attacker) - 1)
	if attacker.general:
		strength *= GENERAL_MOUNTED_POWER if BattleEnums.is_cavalry(attacker.type) else GENERAL_POWER
	# Habilidades, rasgos y equipo del comandante y del compañero al mando del pelotón.
	strength *= maxf(0.3, 1.0 + _unit_fx(attacker, "unit_power") + _unit_fx(attacker, _type_power_key(attacker.type)))
	if attacker.companion != null:
		strength *= 1.0 + (attacker.companion.combat + attacker.companion.leadership) / COMPANION_DIVISOR
	# Órdenes, habilidades de mando y clima.
	if attacker.order == BattleEnums.Order.CARGAR and dist == 1:
		strength *= HEAVY_CHARGE_POWER if attacker.type == BattleEnums.UnitType.CABALLERIA_PESADA else CHARGE_POWER
	strength *= attacker.surge * float(_power.get(attacker.side, 1.0))
	if BattleEnums.is_ranged(attacker.type) and weather == BattleEnums.Weather.LLUVIA:
		strength *= RAIN_ARCHER_FACTOR
	if BattleEnums.is_cavalry(attacker.type) and attacker.side == BattleEnums.Side.DEFENSOR and has_walls:
		strength *= 1.0 + float(cavalry_bonus[0])   # establos del castillo

	var flank := flank_of(attacker, target)
	strength *= REAR_DAMAGE if flank == 2 else (FLANK_DAMAGE if flank == 1 else 1.0)
	if attacker.formation == BattleEnums.Formation.CUNA:
		strength *= CUNA_POWER
	elif attacker.formation == BattleEnums.Formation.CUADRO:
		strength *= CUADRO_POWER

	var t := terrain_at(target.cell)
	var defense: float = unit_terrain_defense(target, target.cell)
	if target.formation == BattleEnums.Formation.CUADRO:
		defense *= CUADRO_VS_CAVALRY if BattleEnums.is_cavalry(attacker.type) else CUADRO_DEFENSE
	elif target.formation == BattleEnums.Formation.CUNA and flank > 0:
		defense *= CUNA_FLANK_DEFENSE
	# Defensa propia del tipo (lanceros, pesados); los ballesteros atraviesan armaduras.
	var pierce := attacker.type == BattleEnums.UnitType.BALLESTEROS
	if not pierce:
		defense *= BattleEnums.stat(target.type, "defense")
		if BattleEnums.is_ranged(attacker.type) and target.type == BattleEnums.UnitType.INFANTERIA_PESADA:
			defense *= ARROW_RESIST
	if target.general:
		defense *= (GENERAL_MOUNTED_DEFENSE if BattleEnums.is_cavalry(target.type) else GENERAL_DEFENSE) \
			* (1.0 + SkillEffects.fx(general_of(target.side), "general_def"))
	if t in [BattleEnums.Terrain.COLINA, BattleEnums.Terrain.MURALLA] and _has_skill(_commander(target.side), SKILL_TACTICA_DEFENSIVA):
		defense *= TACTICA_DEFENSIVA_FACTOR
	if _terrain_defense(t) > 1.0:
		defense *= 1.0 + _unit_fx(target, "terrain_def")
	if target.order == BattleEnums.Order.MANTENER:
		defense *= HOLD_DEFENSE
	defense *= float(_shield.get(target.side, 1.0))
	if t == BattleEnums.Terrain.MURALLA:
		strength *= 1.0 + _unit_fx(attacker, "wall_assault")
		if target.side == BattleEnums.Side.DEFENSOR:
			defense *= 1.0 + wall_bonus   # murallas mejoradas del castillo

	var value := strength / defense
	if with_variance:
		value *= randf_range(0.85, 1.15)
	return clampi(roundi(value), 1, maxi(1, target.soldiers))

func _base_power(t: int) -> float:
	return BattleEnums.stat(t, "power")

## Círculo de ventajas entre familias (BattleEnums.BEATS): quien aplasta a su presa hace +30%,
## quien ataca a su depredador hace −20%; los arqueros cuerpo a cuerpo rinden poco.
func _matchup(a: int, d: int, dist: int) -> float:
	if BattleEnums.is_ranged(a) and dist == 1:
		return RANGED_MELEE_FACTOR
	var fa := BattleEnums.family_of(a)
	var fd := BattleEnums.family_of(d)
	if BattleEnums.beats(fa, fd):
		return ADVANTAGE_FACTOR
	if BattleEnums.beats(fd, fa):
		return DISADVANTAGE_FACTOR
	return 1.0

func _terrain_defense(t: int) -> float:
	match t:
		BattleEnums.Terrain.BOSQUE: return 1.25
		BattleEnums.Terrain.COLINA: return 1.2
		BattleEnums.Terrain.MURALLA: return 1.5
		BattleEnums.Terrain.ALDEA: return 1.3
		BattleEnums.Terrain.VADO: return 0.8    # con el agua por las rodillas, nadie se defiende bien
	return 1.0

func _apply_casualties(u: BattleUnit, amount: int) -> void:
	u.soldiers = maxi(0, u.soldiers - amount)
	var loss_ratio: float = amount / float(maxi(1, u.max_soldiers))
	var loss := (loss_ratio * 60.0 + 5) * clampf(1.0 + _unit_fx(u, "morale_loss"), 0.2, 2.0)
	if u.general:
		loss *= GENERAL_MORALE_LOSS
	u.morale = maxi(0, u.morale - int(loss))
	# Un compañero prestado por el señor no arriesga la vida por un pelotón que se hunde.
	if u.companion != null and u.companion.has_meta("faction_companion") and u.morale < FACTION_DESERT_MORALE and u.soldiers > 0:
		log_message.emit("%s abandona el mando de su pelotón." % u.companion.full_name())
		u.companion = null

# Oriflama de San Dionisio: el primer pelotón del bando que iba a huir aguanta, con la moral justa para seguir.
const ORIFLAMMA_MORALE := 5
func _oriflamma_holds(u: BattleUnit) -> bool:
	if _oriflamma_used.has(u.side) or not SkillEffects.has_unique(_commander(u.side), SkillEffects.UNIQUE_ORIFLAMMA):
		return false
	_oriflamma_used[u.side] = true
	u.morale = BattleUnit.ROUT_MORALE + ORIFLAMMA_MORALE
	log_message.emit("¡La Oriflama ondea y %s (%s) se rehace en vez de huir!" % [BattleEnums.unit_type_name(u.type), _side_label(u.side)])
	return true

func _check_rout(u: BattleUnit) -> void:
	if u.routed:
		return
	if u.soldiers <= 0:
		u.routed = true
		log_message.emit("¡%s (%s) ha sido aniquilado!" % [BattleEnums.unit_type_name(u.type), _side_label(u.side)])
		unit_routed.emit(u, true)
		_wound_companion(u, WOUND_CHANCE_ANNIHILATED)
	elif u.morale < BattleUnit.ROUT_MORALE and _oriflamma_holds(u):
		return
	elif u.morale < BattleUnit.ROUT_MORALE:
		u.routed = true
		log_message.emit("¡%s (%s) rompe filas y huye!" % [BattleEnums.unit_type_name(u.type), _side_label(u.side)])
		unit_routed.emit(u, false)
		_wound_companion(u, WOUND_CHANCE_ROUTED)
	else:
		return
	# Ver huir a los compañeros desmoraliza al resto del bando (menos si era un puñado de hombres).
	var contagion := roundi(ROUT_CONTAGION * minf(1.0, float(u.max_soldiers) / SOLDIERS_PER_UNIT))
	for ally: BattleUnit in active_units(u.side):
		ally.morale = maxi(0, ally.morale - contagion)

func _rest_side(side: int) -> void:
	_power.erase(side)
	for u: BattleUnit in active_units(side):
		if not u.has_moved and not u.has_acted:
			u.fatigue = maxi(0, u.fatigue - 15)
			u.morale = mini(100, u.morale + 3 + roundi(_unit_fx(u, "rally")))

func _reset_side(side: int) -> void:
	_shield.erase(side)   # el Muro de escudos dura hasta el siguiente turno de quien lo alzó
	for u: BattleUnit in units:
		if u.side == side:
			u.reset_turn()

# --- IA (controla el bando que no es del jugador) ---

## Jefe que manda a los aliados: el general del bando si no eres tú; si no, el señor que te invitó.
func ally_commander() -> Character:
	var g := general_of(player_side)
	if g != null and g != player_leader:
		return g
	return _commander(player_side)

## 0 = torpe, 1 = tan hábil como la IA enemiga. Depende del Liderazgo y la Estrategia de su jefe.
func ally_competence() -> float:
	if ally_competence_override >= 0.0:
		return clampf(ally_competence_override, 0.0, 1.0)
	var c := ally_commander()
	if c == null:
		return 0.0
	return clampf(float(c.leadership + c.strategy - ALLY_SKILL_LOW) / float(ALLY_SKILL_FULL - ALLY_SKILL_LOW), 0.0, 1.0)

## ¿Comete un error este pelotón aliado en esta decisión? (los del enemigo y los tuyos, nunca)
func _ally_blunder(u: BattleUnit) -> bool:
	if u == null or u.side != player_side or not u.ally:
		return false
	if randf() >= ALLY_MAX_BLUNDER * (1.0 - ally_competence()):
		return false
	ally_blunders += 1
	return true

## Movimiento sin mirar el terreno ni los peligros: la casilla alcanzable más cercana al objetivo.
func _ai_naive_cell(u: BattleUnit, target: BattleUnit) -> Vector2i:
	var best_cell := u.cell
	var best_d := _path_dist(u.cell, target.cell)
	for cell in reachable_cells(u):
		var d := _path_dist(cell, target.cell)
		if d < best_d:
			best_d = d
			best_cell = cell
	return best_cell

func _run_ai(side: int) -> void:
	# Primero disparan los arqueros (ablandan), después carga la caballería y por último la infantería.
	_path_cache.clear()
	_ai_assign_roles(side)
	_ai_use_ability(side)
	var order: Array[BattleUnit] = []
	for u: BattleUnit in active_units(side):
		if side != player_side or u.ally:
			order.append(u)
	order.sort_custom(func(a: BattleUnit, b: BattleUnit): return AI_ORDER[a.family()] < AI_ORDER[b.family()])
	var walled := has_walls and side == BattleEnums.Side.DEFENSOR
	for u: BattleUnit in order:
		if is_over:
			return
		if not u.is_active():
			continue
		# El general se cuida en campo abierto; tras la muralla defiende el muro como uno más.
		if u.general and active_units(side).size() > 1 and not walled:
			_ai_general_turn(u)
			continue
		u.order = BattleEnums.Order.NINGUNA if u.order == BattleEnums.Order.MANTENER else u.order
		_ai_pick_formation(u)
		var nearest := _nearest_enemy(u)
		# Con la moral baja y el enemigo encima, se repliega para reagruparse en vez de luchar hasta huir.
		if nearest != null and not walled and u.morale < AI_REGROUP_MORALE and distance(u.cell, nearest.cell) <= AI_REGROUP_DIST \
				and can_withdraw(u) and _ai_smart(u):
			withdraw(u)
			continue
		# Un pelotón deshecho y acosado se repliega para no romper filas.
		if nearest != null and distance(u.cell, nearest.cell) <= 1 and u.morale < AI_WITHDRAW_MORALE \
				and u.soldiers < u.max_soldiers * 0.4 and randf() < 0.5:
			withdraw(u)
			continue
		# La reserva espera detrás hasta que hace falta.
		if u.reserve:
			if _ai_reserve_needed(u):
				u.reserve = false
				log_message.emit("La reserva (%s) entra en combate." % _side_label(side))
			else:
				_follow_line(u, AI_RESERVE_BEHIND, AI_REGROUP_DIST)
				continue
		# La escolta no se aleja del general y caza a quien se le acerque.
		var guard_target: BattleUnit = null
		if u.escort:
			var g := _general_unit(side)
			if g == null or active_units(side).size() < AI_ESCORT_MIN_UNITS:
				u.escort = false
			else:
				guard_target = _threat_to(g)
				if guard_target == null:
					var near := targets_in_range(u)
					if not near.is_empty():
						attack(u, _ai_best_target(u, near))
					elif distance(u.cell, g.cell) > 1:
						_ai_move_near(u, g)
					continue
				nearest = guard_target
		var targets := targets_in_range(u)
		if targets.is_empty():
			if nearest == null:
				continue
			var goal := nearest
			if guard_target == null and _ai_smart(u):
				goal = _ai_move_target(u, nearest)
			var engaged := distance(u.cell, goal.cell) <= AI_ENGAGE_DISTANCE
			# Tras la muralla, el defensor espera; la caballería sale a cazar igual.
			if engaged or not has_walls or BattleEnums.is_cavalry(u.type) or side == BattleEnums.Side.ATACANTE:
				# Si llega al cuerpo a cuerpo este turno, entra a la carga.
				if not BattleEnums.is_ranged(u.type) and distance(u.cell, goal.cell) <= effective_move_range(u) + 1:
					u.order = BattleEnums.Order.CARGAR
				_ai_flank = _ai_smart(u)
				var cell := _ai_pick_cell(u, goal)
				_ai_flank = false
				if _ally_blunder(u) or _ai_sloppy(u):
					# Un jefe torpe duda (se queda donde está) o se lanza sin mirar el terreno.
					var hesitate := ALLY_HESITATE_SHARE_SIEGE if has_walls else ALLY_HESITATE_SHARE
					cell = u.cell if randf() < hesitate else _ai_naive_cell(u, goal)
				if cell != u.cell:
					move_unit(u, cell)
			targets = targets_in_range(u)
		elif not BattleEnums.is_ranged(u.type) and can_move(u) and _ai_smart(u):
			# Ya en contacto: si puede rodear al objetivo y darle por el flanco, se mueve antes de golpear.
			_ai_flank_step(u, _ai_best_target(u, targets))
			targets = targets_in_range(u)
		if not targets.is_empty():
			# Sin buena coordinación, a veces golpea al que tiene delante en vez de concentrar el fuego.
			var sloppy := targets.size() > 1 and (_ally_blunder(u) or _ai_sloppy(u))
			attack(u, targets.pick_random() if sloppy else _ai_best_target(u, targets))
		# Infantería y arqueros con el enemigo encima se plantan para aguantar su turno.
		if u.is_active() and not BattleEnums.is_cavalry(u.type) and nearest != null and nearest.is_active() \
				and distance(u.cell, nearest.cell) <= 2 and not _ally_blunder(u):
			u.order = BattleEnums.Order.MANTENER

## ¿Elige la IA lo mejor esta vez? Depende de la dificultad (y, en los aliados, de la competencia de su jefe).
func _ai_smart(u: BattleUnit) -> bool:
	var p: float = AI_SMART_CHANCE[clampi(ai_difficulty, 0, AI_SMART_CHANCE.size() - 1)]
	if u.side == player_side:
		p *= ally_competence()
	return randf() < p

## En Fácil, el enemigo a veces actúa sin pensar.
func _ai_sloppy(u: BattleUnit) -> bool:
	if u.side == player_side:
		return false
	return randf() < float(AI_SLOPPY_CHANCE[clampi(ai_difficulty, 0, AI_SLOPPY_CHANCE.size() - 1)])

func _ai_controls(u: BattleUnit) -> bool:
	return u.side != player_side or u.ally

## Al empezar: una escolta para el general y un pelotón de reserva (solo en campo abierto).
func _ai_assign_roles(side: int) -> void:
	if _roles_done.get(side, false):
		return
	_roles_done[side] = true
	if has_walls:
		return   # en un asedio no hay tiempo para reservas: se asalta o se defiende el muro
	var mine: Array[BattleUnit] = active_units(side).filter(func(o: BattleUnit) -> bool: return _ai_controls(o))
	if mine.is_empty() or not _ai_smart(mine[0]):
		return
	var g := _general_unit(side)
	var foe := _other_side(side)
	var free: Array[BattleUnit] = mine.filter(func(o: BattleUnit) -> bool: return not o.general and not BattleEnums.is_ranged(o.type))
	if g != null and _ai_controls(g) and mine.size() >= AI_ESCORT_MIN_UNITS and not free.is_empty():
		free.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool: return distance(a.cell, g.cell) < distance(b.cell, g.cell))
		free[0].escort = true
		free.remove_at(0)
	if mine.size() >= AI_RESERVE_MIN_UNITS and not free.is_empty():
		# La caballería es la mejor reserva; si no, el más alejado del enemigo.
		free.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
			var ca := BattleEnums.is_cavalry(a.type)
			var cb := BattleEnums.is_cavalry(b.type)
			if ca != cb:
				return ca
			return _min_enemy_dist(a.cell, foe) > _min_enemy_dist(b.cell, foe))
		free[0].reserve = true

func _min_enemy_dist(cell: Vector2i, foe: int) -> int:
	var best := 999
	for e: BattleUnit in active_units(foe):
		best = mini(best, distance(cell, e.cell))
	return best

func _general_unit(side: int) -> BattleUnit:
	for u: BattleUnit in active_units(side):
		if u.general:
			return u
	return null

## El enemigo más cercano al general que está a menos de AI_ESCORT_RADIUS de él.
func _threat_to(g: BattleUnit) -> BattleUnit:
	var best: BattleUnit = null
	var best_d := AI_ESCORT_RADIUS + 1
	for e: BattleUnit in active_units(_other_side(g.side)):
		var d := distance(e.cell, g.cell)
		if d < best_d:
			best_d = d
			best = e
	return best

func _ai_reserve_needed(u: BattleUnit) -> bool:
	if turn >= AI_RESERVE_TURN:
		return true
	if _min_enemy_dist(u.cell, _other_side(u.side)) <= AI_RESERVE_TRIGGER:
		return true
	var g := _general_unit(u.side)
	if g != null and _threat_to(g) != null:
		return true
	return _strength_ratio(u.side) < _strength_ratio(_other_side(u.side)) - AI_RESERVE_LOSING

## Se acerca al pelotón amigo (la casilla alcanzable más cercana).
func _ai_move_near(u: BattleUnit, friend: BattleUnit) -> void:
	var best_cell := u.cell
	var best_d := distance(u.cell, friend.cell)
	for cell in reachable_cells(u):
		var d := distance(cell, friend.cell)
		if d < best_d or (d == best_d and d > 0 and _terrain_defense(terrain_at(cell)) > _terrain_defense(terrain_at(best_cell))):
			best_d = d
			best_cell = cell
	if best_cell != u.cell:
		move_unit(u, best_cell)

## Hacia quién avanza: el más débil, aislado o fácil de flanquear al alcance de este turno (o el más cercano).
func _ai_move_target(u: BattleUnit, nearest: BattleUnit) -> BattleUnit:
	var reach := effective_move_range(u) + _range_from(u, u.cell) + 1
	var best := nearest
	var best_value := -INF
	for e: BattleUnit in active_units(_other_side(u.side)):
		var d := distance(u.cell, e.cell)
		if d > reach or not is_visible_to(u.side, e):
			continue
		var value := _ai_target_value(u, e) - d * 0.5
		if value > best_value:
			best_value = value
			best = e
	return best

func _ai_target_value(u: BattleUnit, e: BattleUnit) -> float:
	var value := (1.0 - float(e.soldiers) / maxi(1, e.max_soldiers)) * AI_FOCUS_WEIGHT + (100 - e.morale) * 0.05
	if _isolated(e):
		value += AI_ISOLATED_WEIGHT
	if e.general:
		value += AI_GENERAL_TARGET
	if BattleEnums.beats(u.family(), e.family()):
		value += 2.0
	elif BattleEnums.beats(e.family(), u.family()):
		value -= 2.0
	return value

## Sin ningún amigo a 2 casillas.
func _isolated(e: BattleUnit) -> bool:
	for o: BattleUnit in active_units(e.side):
		if o != e and distance(o.cell, e.cell) <= 2:
			return false
	return true

## Ya en contacto: busca una casilla junto al objetivo desde la que darle por el flanco o la espalda.
func _ai_flank_step(u: BattleUnit, t: BattleUnit) -> void:
	var best_cell := u.cell
	var best_level := flank_of(u, t)
	for cell in reachable_cells(u):
		if distance(cell, t.cell) != 1:
			continue
		var level := flank_of(u, t, cell)
		if level > best_level:
			best_level = level
			best_cell = cell
	if best_cell != u.cell:
		move_unit(u, best_cell)

## Formación según la situación: cuadro si amenaza caballería, cuña la caballería, línea el resto.
func _ai_pick_formation(u: BattleUnit) -> void:
	if not _ai_smart(u):
		return
	var f := BattleEnums.Formation.LINEA
	if BattleEnums.is_cavalry(u.type):
		f = BattleEnums.Formation.CUNA
	elif not BattleEnums.is_ranged(u.type) and u.family() != BattleEnums.Family.PIQUEROS:
		for e: BattleUnit in active_units(_other_side(u.side)):
			if BattleEnums.is_cavalry(e.type) and distance(u.cell, e.cell) <= effective_move_range(e) + 1:
				f = BattleEnums.Formation.CUADRO
				break
	u.formation = f

## Sigue a su ejército a "behind" casillas por detrás, sin acercarse a menos de "danger" del enemigo.
func _follow_line(u: BattleUnit, behind: int, danger: int) -> void:
	var front := -1 if u.side == BattleEnums.Side.ATACANTE else 1   # hacia atrás: −x el atacante
	var others: Array[BattleUnit] = active_units(u.side).filter(func(o: BattleUnit) -> bool: return o != u and not o.reserve)
	if others.is_empty():
		return
	var line_x := 0.0
	var mid_y := 0.0
	for o: BattleUnit in others:
		line_x += o.cell.x
		mid_y += o.cell.y
	line_x /= others.size()
	mid_y /= others.size()
	var goal := Vector2(line_x + front * behind, mid_y)
	var best_cell := u.cell
	var best_score := Vector2(u.cell).distance_to(goal)
	for cell in reachable_cells(u):
		if _enemy_near_cell(u.side, cell, danger):
			continue
		var score := Vector2(cell).distance_to(goal) - (_terrain_defense(terrain_at(cell)) - 1.0)
		if score < best_score:
			best_score = score
			best_cell = cell
	if best_cell != u.cell:
		var keep := u.facing
		move_unit(u, best_cell)
		u.facing = keep   # recolocarse detrás no le hace dar la espalda al enemigo

const AI_GENERAL_SAFE_RATIO := 1.5     # el general solo golpea si causa 1,5 veces las bajas que recibe
const AI_GENERAL_DANGER := 2           # y se repliega si el enemigo está así de cerca
const AI_GENERAL_BEHIND := 1          # el general sigue al ejército a esta distancia por detrás de su línea

# Si el general cae, el bando pierde: la IA lo mantiene detrás de sus líneas y solo golpea sobre seguro.
func _ai_general_turn(u: BattleUnit) -> void:
	var best: BattleUnit = null
	var best_value := 0.0
	for t: BattleUnit in targets_in_range(u):
		var p := preview_attack(u, t)
		if p.casualties >= maxf(1.0, p.counter * AI_GENERAL_SAFE_RATIO) and p.casualties > best_value:
			best_value = p.casualties
			best = t
	if best != null:
		attack(u, best)
		return
	if _enemy_within(u, AI_GENERAL_DANGER):
		if can_withdraw(u):
			withdraw(u)
		return
	# Sigue a su ejército por detrás, sin acercarse a menos de AI_GENERAL_DANGER del enemigo.
	_follow_line(u, AI_GENERAL_BEHIND, AI_GENERAL_DANGER)

# Parte de su ejército inicial que le queda a un bando.
## Al caer la noche en campo abierto: gana quien perdió menos hombres (más la moral que le queda).
## Un empate ajustado lo resuelve quien defendía el terreno.
func _night_winner() -> int:
	var a := BattleEnums.Side.ATACANTE
	var d := BattleEnums.Side.DEFENSOR
	var score_a: float = -float(_initial_soldiers.get(a, 0) - total_soldiers(a)) + _avg_morale(a) * NIGHT_MORALE_WEIGHT
	var score_d: float = -float(_initial_soldiers.get(d, 0) - total_soldiers(d)) + _avg_morale(d) * NIGHT_MORALE_WEIGHT
	return a if score_a > score_d else d

func _avg_morale(side: int) -> float:
	var list := active_units(side)
	if list.is_empty():
		return 0.0
	var sum := 0.0
	for u: BattleUnit in list:
		sum += u.morale
	return sum / list.size()

func _strength_ratio(side: int) -> float:
	return total_soldiers(side) / float(maxi(1, _initial_soldiers.get(side, 1)))

func _enemy_near_cell(side: int, cell: Vector2i, dist: int) -> bool:
	for e: BattleUnit in active_units(_other_side(side)):
		if distance(cell, e.cell) <= dist:
			return true
	return false

# La IA usa como mucho una habilidad de mando por turno, cuando le conviene.
func _ai_use_ability(side: int) -> void:
	for c: Character in ability_users(side, ABILITY_ALLY if side == player_side else ABILITY_ANY):
		if ability_used_by(c):
			continue
		for id: String in abilities_of(c):
			if _ai_wants_ability(id, side):
				if side == player_side and randf() < ALLY_MAX_BLUNDER * (1.0 - ally_competence()):
					ally_blunders += 1   # el jefe aliado deja pasar el momento
					return
				use_ability(c, id, side)
				return

func _ai_wants_ability(id: String, side: int) -> bool:
	var own := active_units(side)
	if own.is_empty():
		return false
	var morale := 0.0
	var fatigue := 0.0
	for u: BattleUnit in own:
		morale += u.morale
		fatigue += u.fatigue
	morale /= own.size()
	fatigue /= own.size()
	var close := _units_near_enemy(side, 2)
	match id:
		"grito":
			return morale < 55 or close >= 2
		"flechas":
			for u: BattleUnit in own:
				if BattleEnums.is_ranged(u.type) and _enemy_within(u, effective_attack_range(u) + VOLLEY_EXTRA_RANGE):
					return true
		"carga":
			for u: BattleUnit in own:
				if BattleEnums.is_cavalry(u.type) and not u.has_moved and _enemy_within(u, effective_move_range(u) + CARGA_BONUS_MOVE + 1):
					return true
		"muro":
			return close >= 2
		"reagrupar":
			return morale < 50 or fatigue > 45
		"emboscada":
			for u: BattleUnit in own:
				if terrain_at(u.cell) in [BattleEnums.Terrain.BOSQUE, BattleEnums.Terrain.ALDEA] and _enemy_within(u, effective_attack_range(u) + 1):
					return true
		"coordinado":
			return _units_near_enemy(side, 3) >= 2
	return false

func _enemy_within(u: BattleUnit, dist: int) -> bool:
	for e: BattleUnit in active_units(_other_side(u.side)):
		if distance(u.cell, e.cell) <= dist:
			return true
	return false

func _units_near_enemy(side: int, dist: int) -> int:
	var n := 0
	for u: BattleUnit in active_units(side):
		if _enemy_within(u, dist):
			n += 1
	return n

# Coste del camino (sin contar pelotones) desde cada casilla hasta "goal": así la IA busca los vados
# y puentes en vez de quedarse mirando el río.
func _path_dist(cell: Vector2i, goal: Vector2i) -> int:
	if not _path_cache.has(goal):
		var best := {goal: 0}
		var frontier: Array[Vector2i] = [goal]
		while not frontier.is_empty():
			var current: Vector2i = frontier.pop_front()
			for dir in DIRS:
				var next: Vector2i = current + dir
				if not in_bounds(next) or terrain_at(next) == BattleEnums.Terrain.RIO:
					continue
				var cost: int = best[current] + (2 if terrain_at(next) in [BattleEnums.Terrain.VADO, BattleEnums.Terrain.BOSQUE] else 1)
				if best.has(next) and best[next] <= cost:
					continue
				best[next] = cost
				frontier.append(next)
		_path_cache[goal] = best
	return _path_cache[goal].get(cell, 999)

func _nearest_enemy(u: BattleUnit) -> BattleUnit:
	var best: BattleUnit = null
	var best_dist := 9999
	for other: BattleUnit in active_units(_other_side(u.side)):
		var d := distance(u.cell, other.cell)
		if d < best_dist:
			best_dist = d
			best = other
	return best

func _ai_pick_cell(u: BattleUnit, target: BattleUnit) -> Vector2i:
	var best_cell := u.cell
	var best_score := _ai_cell_score(u, u.cell, target)
	for cell in reachable_cells(u):
		var s := _ai_cell_score(u, cell, target)
		if s < best_score:
			best_score = s
			best_cell = cell
	return best_cell

func _ai_cell_score(u: BattleUnit, cell: Vector2i, target: BattleUnit) -> float:
	# Menor es mejor: quedar justo al alcance máximo del objetivo, preferiblemente en terreno defensivo.
	var d := distance(cell, target.cell)
	var r := _range_from(u, cell)
	var score: float = float(r - d) if d <= r else 100.0 + _path_dist(cell, target.cell)
	score -= (_terrain_defense(terrain_at(cell)) - 1.0) * AI_TERRAIN_WEIGHT
	if _ai_flank and d <= r:
		score -= AI_FLANK_WEIGHT * flank_of(u, target, cell)
	# Los arqueros no se dejan alcanzar por la infantería o la caballería enemigas.
	if BattleEnums.is_ranged(u.type):
		for enemy: BattleUnit in active_units(_other_side(u.side)):
			if not BattleEnums.is_ranged(enemy.type) and distance(cell, enemy.cell) <= enemy.move_range():
				score += AI_ARCHER_DANGER
	return score

func _ai_best_target(u: BattleUnit, targets: Array[BattleUnit]) -> BattleUnit:
	var best: BattleUnit = targets[0]
	var best_value := -1.0
	for t: BattleUnit in targets:
		# Prioriza el daño esperado, rematar pelotones debilitados (fuego concentrado) y evitar respuestas caras.
		var preview := preview_attack(u, t)
		var value := float(preview.casualties) + (100 - t.morale) * 0.15
		value += (1.0 - float(t.soldiers) / maxi(1, t.max_soldiers)) * AI_FOCUS_WEIGHT
		if preview.casualties >= t.soldiers:
			value += AI_FINISH_BONUS
		if _isolated(t):
			value += AI_ISOLATED_WEIGHT * 0.5
		if t.general:
			value += AI_GENERAL_TARGET
		value -= preview.counter * 0.8
		if value > best_value:
			best_value = value
			best = t
	return best

# --- Fin de la batalla ---

func _check_end() -> void:
	if is_over:
		return
	for side: int in [player_side, _other_side(player_side)]:
		var fallen := _fallen_general_unit(side)
		if fallen != null:
			_end_battle(_other_side(side), "Cae %s, general de %s: su bando se rinde." % [
				fallen.leader().full_name() if fallen.leader() != null else "el general", "tu bando" if side == player_side else "los enemigos"])
			return
	if active_units(BattleEnums.Side.DEFENSOR).is_empty():
		_end_battle(BattleEnums.Side.ATACANTE, "Los defensores de %s han caído." % location_name)
	elif active_units(BattleEnums.Side.ATACANTE).is_empty():
		_end_battle(BattleEnums.Side.DEFENSOR, "El ejército atacante ha sido derrotado.")

func _end_battle(winner_side: int, reason: String) -> void:
	is_over = true
	pending_retreat = false
	_grant_mastery(winner_side)
	var report := {
		"winner_side": winner_side,
		"reason": reason,
		"turns": turn,
		"attacker_initial": _initial_soldiers.get(BattleEnums.Side.ATACANTE, 0),
		"defender_initial": _initial_soldiers.get(BattleEnums.Side.DEFENSOR, 0),
		"attacker_survivors": total_soldiers(BattleEnums.Side.ATACANTE),
		"defender_survivors": total_soldiers(BattleEnums.Side.DEFENSOR),
		"wounded_companions": wounded_companions.duplicate(),
		"betrayed_side": betrayed_side,
		# Soldados de cada bando que no son tuyos (tu gente no se suma a castillos ni ejércitos ajenos).
		"attacker_ai_survivors": _soldiers_not_own(BattleEnums.Side.ATACANTE),
		"defender_ai_survivors": _soldiers_not_own(BattleEnums.Side.DEFENSOR),
		"own_initial": _own_initial,
		"own_survivors": _soldiers_own(),
		"covered_retreat": covering and _soldiers_own() > 0,
		"deserted": deserted,
		"mastery_gains": mastery_gains.duplicate(),
		"general_player": general_of(player_side) == player_leader and player_leader != null,
	}
	log_message.emit(reason)
	state_updated.emit()
	battle_ended.emit(winner_side, report)

# --- Utilidades ---

func _soldiers_not_own(side: int) -> int:
	var sum := 0
	for u: BattleUnit in units:
		if u.side == side and not u.own:
			sum += u.soldiers
	return sum

func _soldiers_own() -> int:
	var sum := 0
	for u: BattleUnit in units:
		if u.own:
			sum += u.soldiers
	return sum

func _other_side(side: int) -> int:
	return BattleEnums.Side.DEFENSOR if side == BattleEnums.Side.ATACANTE else BattleEnums.Side.ATACANTE

func _commander(side: int) -> Character:
	return attacker_cmd if side == BattleEnums.Side.ATACANTE else defender_cmd

func _side_label(side: int) -> String:
	return "tuyo" if side == player_side else "enemigo"

# --- Efectos y compañeros ---

const AI_ORDER := {BattleEnums.Family.ARQUERIA: 0, BattleEnums.Family.CABALLERIA: 1, BattleEnums.Family.PIQUEROS: 2, BattleEnums.Family.INFANTERIA: 3}
const AI_TERRAIN_WEIGHT := 3.0
const AI_ARCHER_DANGER := 3.0
const AI_FOCUS_WEIGHT := 6.0
const AI_FINISH_BONUS := 8.0
const AI_WITHDRAW_MORALE := 40

# Suma de un efecto del comandante del bando y del compañero al mando del pelotón.
func _unit_fx(u: BattleUnit, key: String) -> float:
	var value := SkillEffects.fx(_commander(u.side), key)
	if u.companion != null:
		value += SkillEffects.fx(u.companion, key)
	return value

func _type_power_key(t: int) -> String:
	match BattleEnums.family_of(t):
		BattleEnums.Family.ARQUERIA: return "arch_power"
		BattleEnums.Family.CABALLERIA: return "cav_power"
		BattleEnums.Family.PIQUEROS: return "pike_power"
	return "inf_power"

func _retaliation(u: BattleUnit) -> float:
	return RETALIATION_FACTOR * maxf(0.0, 1.0 + _unit_fx(u, "retaliation"))

func _fatigue_gain(u: BattleUnit, base: int) -> int:
	var charge := CHARGE_FATIGUE if u.order == BattleEnums.Order.CARGAR else 1.0
	return maxi(1, roundi(base * charge * clampf(1.0 + _unit_fx(u, "fatigue"), 0.2, 2.0)))

# Cada compañero dirige el pelotón que mejor le va: caballería al más combativo,
# arqueros al mejor estratega, infantería al resto. Sube la fuerza y la moral del pelotón.
func _assign_companions(side: int, companions: Array[Character]) -> void:
	var free: Array[BattleUnit] = []
	for u: BattleUnit in units:
		if u.side == side and not u.ally:
			free.append(u)
	# En una batalla ajena el pelotón mayor lo encabezas tú: los compañeros llevan los demás.
	if side == player_side and (ally_soldiers > 0 or not own_allocation.is_empty()) and not free.is_empty():
		var biggest: BattleUnit = free[0]
		for u: BattleUnit in free:
			if u.soldiers > biggest.soldiers:
				biggest = u
		free.erase(biggest)
	var commander := _commander(side)
	for c: Character in companions:
		if c == null or free.is_empty() or c.is_wounded() or _is_party_officer(c):
			continue
		# Cada jefe lleva su tropa: la que le asignó el Consejo de guerra o la que decide el general.
		var fam := _family_for(c, side)
		var unit: BattleUnit = free[0]
		for u: BattleUnit in free:
			if u.family() == fam:
				unit = u
				break
		free.erase(unit)
		unit.companion = c
		_set_family(unit, fam, c)
		var morale_bonus := c.leadership / COMPANION_MORALE_DIVISOR + SkillEffects.companion_loyalty(commander)
		if c.has_meta("faction_companion"):
			morale_bonus -= FACTION_MORALE_PENALTY
		unit.morale = clampi(unit.morale + morale_bonus, 0, 100)
		log_message.emit("%s dirige un pelotón de %s (%s)." % [c.full_name(), BattleEnums.unit_type_name(unit.type).to_lower(), _side_label(side)])

# --- General, tropas y comandancia ---

func _autoload(node_name: String) -> Node:
	var loop := Engine.get_main_loop()
	return loop.root.get_node_or_null(node_name) if loop is SceneTree else null

## General del bando (null si nadie con nombre lo manda).
func general_of(side: int) -> Character:
	return generals.get(side)

func is_player_general() -> bool:
	return player_leader != null and general_of(player_side) == player_leader

## El señor del bando nombra general a quien más fama, mando y rango reúne. Si el ejército es tuyo
## (no te invitaron), el general eres tú.
func _pick_general(side: int, companions: Array[Character]) -> Character:
	var cmd := _commander(side)
	if side == player_side and ally_soldiers <= 0 and player_leader != null:
		return player_leader
	var candidates: Array[Character] = []
	if cmd != null:
		candidates.append(cmd)
	for c: Character in companions:
		if c != null and not c.is_wounded() and not c in candidates:
			candidates.append(c)
	if side == player_side and player_leader != null and not player_leader in candidates:
		candidates.append(player_leader)
	var best: Character = null
	var best_score := -INF
	for c: Character in candidates:
		var score := general_score(c)
		if score > best_score:
			best_score = score
			best = c
	return best

static func general_score(c: Character) -> float:
	if c == null:
		return -INF
	return c.fame * GENERAL_SCORE_FAME + c.leadership * GENERAL_SCORE_LEADERSHIP \
		+ c.strategy * GENERAL_SCORE_STRATEGY + c.rank() * GENERAL_SCORE_RANK + SkillEffects.fx(c, "general_score")

const SEED_MASTERY_XP_PER_RANK := 45   # experiencia de mando con la que llega un PNJ a su primera batalla, por rango
const SEED_MAIN_SHARE := 0.6           # la mayor parte, en la tropa que le pide el cuerpo

## Un PNJ llega a su primera batalla con el mando que le dan su rango y su carácter (se guarda en su ficha).
func _seed_mastery(c: Character) -> void:
	if not _named(c) or c == player_leader or c.mastery_xp.has("seeded"):
		return
	var total := c.rank() * SEED_MASTERY_XP_PER_RANK + randi_range(0, SEED_MASTERY_XP_PER_RANK)
	var main := _stat_family(c)
	var other: int = [0, 1, 2, 3].filter(func(f: int) -> bool: return f != main).pick_random()
	c.mastery_xp[str(main)] = int(c.mastery_xp.get(str(main), 0)) + roundi(total * SEED_MAIN_SHARE)
	c.mastery_xp[str(other)] = int(c.mastery_xp.get(str(other), 0)) + roundi(total * (1.0 - SEED_MAIN_SHARE))
	c.mastery_xp["seeded"] = 1

static func _named(c: Character) -> bool:
	return c != null and not c.has_meta("captain")

## Quién dirige de verdad un pelotón: su jefe con nombre o, si lo lleva un capitán, el general del bando.
func _effective_leader(u: BattleUnit) -> Character:
	var c := u.leader()
	if _named(c):
		return c
	var g := general_of(u.side)
	return g if g != null else _commander(u.side)

func _unit_mastery(u: BattleUnit) -> int:
	var c := _effective_leader(u)
	if c == null:
		return 1
	# Un capitán sin nombre solo hereda parte del mando del general (si no, un general veterano mejoraba a todo el ejército).
	if not _named(u.leader()):
		return 1 + int((c.mastery(u.family()) - 1) * CAPTAIN_MASTERY_SHARE)
	return c.mastery(u.family())

## Tropa que le toca a un jefe. Con Consejo de guerra (assigned_family) o siendo el general, la elige;
## si no, el general le da su mejor tropa con una probabilidad que crece con su maestría en ella.
func _family_for(c: Character, side: int) -> int:
	if c == null:
		return BattleEnums.Family.INFANTERIA
	# Lo que eligió el jugador para sí mismo se respeta (también siendo general).
	if c == player_leader and c.assigned_family >= 0:
		return c.assigned_family
	var best := _stat_family(c) if _all_mastery_basic(c) else c.best_family()
	if c == general_of(side):
		var own: int = c.assigned_family if c.assigned_family >= 0 else best
		# La escolta del general es su guardia y lucha cuerpo a cuerpo: un general arquero manda más arqueros,
		# pero su propio pelotón no es una batería intocable en la retaguardia.
		return GENERAL_ESCORT_FAMILY if BattleEnums.is_ranged(BattleEnums.basic_type(own)) else own
	if c.assigned_family >= 0:
		return c.assigned_family
	if randf() < ASSIGN_BEST_BASE + ASSIGN_BEST_PER_LEVEL * c.mastery(best):
		return best
	var others: Array = [0, 1, 2, 3].filter(func(f: int) -> bool: return f != best)
	return others[randi() % others.size()]

static func _all_mastery_basic(c: Character) -> bool:
	for f in 4:
		if c.mastery(f) > 1:
			return false
	return true

# Sin experiencia de mando, cada uno tira hacia lo que le pide el cuerpo.
static func _stat_family(c: Character) -> int:
	if c.combat >= c.strategy + 2:
		return BattleEnums.Family.CABALLERIA
	if c.strategy >= c.combat + 2:
		return BattleEnums.Family.ARQUERIA
	if c.defense >= c.combat + 2:
		return BattleEnums.Family.PIQUEROS
	return BattleEnums.Family.INFANTERIA

## Pone al pelotón la tropa de esa familia: la avanzada si su jefe la domina (maestría 5+).
func _set_family(u: BattleUnit, fam: int, leader: Character) -> void:
	var advanced := leader != null and leader.mastery(fam) >= Character.MASTERY_ADVANCED
	# La escolta de un general veterano (aunque su tropa sea de tiro) también es de élite.
	if leader != null and fam == GENERAL_ESCORT_FAMILY and leader == general_of(u.side):
		advanced = advanced or leader.mastery(leader.best_family()) >= Character.MASTERY_ADVANCED
	u.type = BattleEnums.advanced_type(fam) if advanced else BattleEnums.basic_type(fam)

# Los pelotones con jefe con nombre llevan su tropa; los de capitanes, la del reparto.
func _assign_families(side: int) -> void:
	for u: BattleUnit in units:
		if u.side != side:
			continue
		var c := u.leader()
		if _named(c) and c != u.companion:   # los compañeros ya la tienen
			_set_family(u, _family_for(c, side), c)
		if _named(c):
			u.morale = clampi(u.morale + MASTERY_MORALE_PER_LEVEL * (c.mastery(u.family()) - 1), 0, 100)

func _mark_general(side: int) -> void:
	var g := general_of(side)
	if g == null:
		return
	for u: BattleUnit in units:
		if u.side == side and u.leader() == g:
			u.general = true
			u.morale = clampi(u.morale + GENERAL_MORALE, 0, 100)
			return

## Reparte los soldados de cada grupo (tuyo / aliado) según el mando de cada jefe: el general y los
## buenos mandos se llevan más hombres.
func _share_soldiers(side: int) -> void:
	for group_ally: bool in [false, true]:
		var group: Array[BattleUnit] = []
		var total := 0
		for u: BattleUnit in units:
			if u.side == side and u.ally == group_ally:
				group.append(u)
				total += u.soldiers
		if group.size() < 2:
			continue
		var weights: Array[float] = []
		var wsum := 0.0
		for u: BattleUnit in group:
			var w := 1.0 + MASTERY_SHARE_PER_LEVEL * (_unit_mastery(u) - 1) if _named(u.leader()) else 1.0
			if u.general:
				w += GENERAL_SHARE
			weights.append(w)
			wsum += w
		var given := 0
		for i in group.size():
			var n := maxi(1, int(total * weights[i] / wsum)) if i < group.size() - 1 else maxi(1, total - given)
			group[i].soldiers = n
			group[i].max_soldiers = n
			given += n

## Aplica el reparto que eligió el jugador (own_allocation) a sus pelotones. En una batalla ajena el total
## ya es la suma del reparto; en tu propio ejército lo que no asignas queda para los pelotones de capitanes.
func _apply_allocation(side: int) -> void:
	if own_allocation.is_empty():
		return
	var led: Array[BattleUnit] = []
	var others: Array[BattleUnit] = []
	var total := 0
	for u: BattleUnit in units:
		if u.side != side or u.ally:
			continue
		total += u.soldiers
		var who := u.leader()
		if who != null and own_allocation.has(who.full_name()) and (who == player_leader or u.companion == who):
			led.append(u)
		else:
			others.append(u)
	if led.is_empty():
		return
	var wanted := 0
	for u: BattleUnit in led:
		wanted += maxi(1, int(own_allocation[u.leader().full_name()]))
	# Siempre queda algo para los pelotones de capitán: si no llega, el reparto se reduce en proporción.
	var reserve := others.size() * CAPTAIN_MIN_SOLDIERS
	var scale := 1.0 if wanted <= total - reserve or others.is_empty() else float(maxi(led.size(), total - reserve)) / wanted
	var given := 0
	for u: BattleUnit in led:
		var n := maxi(1, int(int(own_allocation[u.leader().full_name()]) * scale))
		u.soldiers = n
		u.max_soldiers = n
		given += n
	var rest := total - given
	if others.is_empty():
		if rest != 0 and ally_soldiers <= 0:   # tu ejército entero: lo que sobra (o falta) va a tu pelotón
			var mine := player_unit()
			if mine != null:
				mine.soldiers = maxi(1, mine.soldiers + rest)
				mine.max_soldiers = mine.soldiers
		return
	var old_sum := 0
	for u: BattleUnit in others:
		old_sum += u.soldiers
	var handed := 0
	for i in others.size():
		var u: BattleUnit = others[i]
		var n := maxi(1, int(rest * u.soldiers / float(maxi(1, old_sum)))) if i < others.size() - 1 else maxi(1, rest - handed)
		u.soldiers = n
		u.max_soldiers = n
		handed += n

## Tu pelotón (el que encabezas tú).
func player_unit() -> BattleUnit:
	for u: BattleUnit in units:
		if u.side == player_side and player_leader != null and u.leader() == player_leader and u.is_active():
			return u
	return null

## Probabilidad de que el general te conceda esa familia de tropa.
func negotiation_chance(fam: int) -> float:
	var c := player_leader
	var g := general_of(player_side)
	if c == null:
		return 0.0
	if g == null or g == c:
		return 1.0
	var rel := 0
	var rd := _autoload("RelationsData")
	if rd != null:
		var r = rd.get_relation(g.full_name())
		if r != null:
			rel = maxi(int(r.affinity), int(r.affection))
	var chance := NEGOTIATE_BASE + NEGOTIATE_PER_MASTERY * c.mastery(fam) + NEGOTIATE_PER_CHARISMA * c.charisma \
		+ NEGOTIATE_PER_FAME * c.fame + NEGOTIATE_PER_RELATION * rel + NEGOTIATE_PER_STRATEGY * c.strategy \
		+ SkillEffects.fx(c, "negotiate")
	return clampf(chance, NEGOTIATE_MIN, NEGOTIATE_MAX)

## Pides al general otra tropa (una vez por batalla, antes del primer golpe). Devuelve {ok, text}.
func negotiate_unit(fam: int) -> Dictionary:
	var u := player_unit()
	if u == null:
		return {"ok": false, "text": "No encabezas ningún pelotón."}
	if negotiated:
		return {"ok": false, "text": "Ya hablaste con el general antes de la batalla."}
	if u.family() == fam:
		return {"ok": false, "text": "Ya llevas %s." % BattleEnums.family_name(fam).to_lower()}
	negotiated = true
	var g := general_of(player_side)
	var chance := negotiation_chance(fam)
	if chance >= 1.0 or randf() < chance:
		player_family = fam
		_set_family(u, fam, player_leader)
		_place_side(player_side)
		state_updated.emit()
		var who := "Como general, eliges" if g == null or g == player_leader else "%s accede: llevarás" % g.full_name()
		return {"ok": true, "text": "%s %s." % [who, BattleEnums.unit_type_name(u.type).to_lower()]}
	var rd := _autoload("RelationsData")
	if rd != null and g != null:
		var r = rd.get_relation(g.full_name())
		if r != null:
			r.adjust(-NEGOTIATE_FAIL_RELATION)
	return {"ok": false, "text": "%s no lo ve claro y te mantiene con %s (afinidad −%d)." % [
		g.full_name() if g != null else "El general", BattleEnums.unit_type_name(u.type).to_lower(), NEGOTIATE_FAIL_RELATION]}

func _fallen_general_unit(side: int) -> BattleUnit:
	for u: BattleUnit in units:
		if u.side == side and u.general and not u.is_active():
			return u
	return null

## ¿El general de la IA de este bando da la batalla por perdida?
func _ai_general_retreats(side: int) -> bool:
	var g := general_of(side)
	if g == null or g == player_leader or turn < AI_RETREAT_MIN_TURN or has_walls and side == BattleEnums.Side.DEFENSOR:
		return false
	var mine := total_soldiers(side)
	var theirs := total_soldiers(_other_side(side))
	return mine < _initial_soldiers.get(side, 0) * AI_RETREAT_RATIO and theirs > mine * AI_RETREAT_EDGE

## Tu general ordenó la retirada: te vas con el ejército o te quedas cubriéndola con tus pelotones.
func answer_retreat(stay: bool) -> void:
	if not pending_retreat:
		return
	pending_retreat = false
	if not stay:
		retreating_side = player_side
		_end_battle(_other_side(player_side), "Te retiras con el ejército por orden del general.")
		return
	covering = true
	cover_turns_left = COVER_TURNS
	for u: BattleUnit in active_units(player_side):
		u.general = false
		if not u.own:
			_withdraw_from_field(u, "%s (%s) se retira tras la orden del general." % [BattleEnums.unit_type_name(u.type), _side_label(u.side)])
	generals.erase(player_side)
	log_message.emit("Te quedas con tus hombres cubriendo la retirada: aguanta %d turnos." % COVER_TURNS)
	_check_end()
	state_updated.emit()

# Experiencia de mando de la familia que dirigió cada jefe con nombre.
func _grant_mastery(winner_side: int) -> void:
	var seen: Array[Character] = []
	for u: BattleUnit in units:
		var c := u.leader()
		if not _named(c) or c in seen:
			continue
		seen.append(c)
		var gained := c.add_mastery_xp(u.family(), MASTERY_XP_WIN if u.side == winner_side else MASTERY_XP_LOSS)
		mastery_gains.append([c.full_name(), u.family(), gained])
		if gained > 0 and c == player_leader:
			log_message.emit("Tu mando de %s sube a nivel %d." % [BattleEnums.family_name(u.family()).to_lower(), c.mastery(u.family())])

## Las habilidades de mando rinden más (o menos) según la Estrategia de quien las da.
static func ability_scale(c: Character) -> float:
	if c == null:
		return 1.0
	return clampf(1.0 + (c.strategy - ABILITY_STRATEGY_PIVOT) * ABILITY_STRATEGY_PER_POINT, ABILITY_SCALE_MIN, ABILITY_SCALE_MAX)

## Mejor Estrategia entre el general y los jefes con nombre del bando.
func best_strategy(side: int) -> int:
	var best := 0
	var g := general_of(side)
	if g != null:
		best = g.strategy
	for u: BattleUnit in active_units(side):
		if _named(u.leader()):
			best = maxi(best, u.leader().strategy)
	return best

## Visión con niebla o de noche: la base, más lo que lee el mejor estratega del bando.
func vision_range_for(side: int) -> int:
	var v := vision_range()
	if v == 0:
		return 0
	return v + clampi((best_strategy(side) - VISION_STRATEGY_BASE) / VISION_STRATEGY_STEP, 0, VISION_STRATEGY_MAX)

## Defensa que da el terreno a un pelotón: su jefe (o el general) le saca más partido con Estrategia;
## en el vado, la misma lectura mitiga la penalización.
func unit_terrain_defense(u: BattleUnit, cell: Vector2i) -> float:
	var base := _terrain_defense(terrain_at(cell))
	var bonus := terrain_strategy_bonus(u)
	if base > 1.0:
		return base + bonus
	if base < 1.0:
		return minf(1.0, base + bonus)
	return base

func terrain_strategy_bonus(u: BattleUnit) -> float:
	var c := _effective_leader(u)
	if c == null:
		return 0.0
	return clampf((c.strategy - TERRAIN_STRATEGY_PIVOT) * TERRAIN_STRATEGY_PER_POINT, 0.0, TERRAIN_STRATEGY_CAP)

## «Bosque +25% (+6% por Estrategia)»: para fichas y vistas previas.
func terrain_text(u: BattleUnit) -> String:
	var t := terrain_at(u.cell)
	var base := _terrain_defense(t)
	var text := BattleEnums.terrain_name(t)
	if base != 1.0:
		text += " %+d%%" % roundi((base - 1.0) * 100)
	var bonus := terrain_strategy_bonus(u)
	if base != 1.0 and bonus > 0.0:
		text += " (+%d%% por Estrategia)" % roundi(bonus * 100)
	return text

## Lo que parece que hará un pelotón enemigo (para quien sabe leer al rival).
func intent_of(u: BattleUnit) -> Dictionary:
	var target := _nearest_enemy(u)
	if target == null:
		return {}
	var d := distance(u.cell, target.cell)
	var verb := "avanzar hacia"
	if d <= effective_attack_range(u):
		verb = "disparar a" if BattleEnums.is_ranged(u.type) else "atacar a"
	elif d <= effective_move_range(u) + effective_attack_range(u):
		verb = "cargar contra" if BattleEnums.is_cavalry(u.type) else "atacar a"
	elif has_walls and u.side == BattleEnums.Side.DEFENSOR and d > AI_ENGAGE_DISTANCE and not BattleEnums.is_cavalry(u.type):
		return {"target": null, "text": "aguantar tras la muralla"}
	return {"target": target, "text": "%s %s" % [verb, BattleEnums.unit_type_name(target.type).to_lower()]}

## Alcance de tu lectura del enemigo (0 si tu Estrategia no llega).
func intent_range() -> int:
	var c := player_leader
	if c == null or c.strategy + roundi(SkillEffects.fx(c, "intent")) < INTENT_MIN_STRATEGY:
		return 0
	return INTENT_RANGE_BASE + (c.strategy - INTENT_MIN_STRATEGY) / INTENT_STEP + roundi(SkillEffects.fx(c, "intent"))

## La tropa pactada para tu pelotón (negociación o Consejo de guerra) se mantiene al rehacer las tropas.
func _apply_player_family() -> void:
	var u := player_unit()
	if player_family >= 0 and u != null and u.family() != player_family:
		_set_family(u, player_family, player_leader)

## Tras el Consejo de guerra (antes del primer golpe): los jefes de tu bando toman la tropa asignada.
func apply_assignments() -> void:
	if turn > 1:
		return
	for u: BattleUnit in units:
		var c := u.leader()
		if u.side == player_side and not u.ally and _named(c) and c.assigned_family >= 0 \
				and c.assigned_family != u.family() and (c != player_leader or u == player_unit()):
			_set_family(u, c.assigned_family, c)
			if c == player_leader:
				player_family = c.assigned_family
	_place_side(player_side)
	state_updated.emit()

## Pelotones enemigos cercanos cuya intención adivinas: [[pelotón, intención], ...].
func visible_intents() -> Array:
	var result: Array = []
	var r := intent_range()
	if r <= 0:
		return result
	for e: BattleUnit in active_units(_other_side(player_side)):
		if not is_visible_to(player_side, e):
			continue
		for own: BattleUnit in active_units(player_side):
			if distance(own.cell, e.cell) <= r:
				var it := intent_of(e)
				if not it.is_empty():
					result.append([e, it])
				break
	return result

# Cada pelotón tiene a alguien al mando: el comandante encabeza el mayor pelotón sin compañero
# (caballería si la hay) y el resto lo dirigen capitanes de tropa, con el retrato de su oficio.
# En una batalla ajena tu pelotón lo encabezas tú y el del anfitrión, él.
func _assign_captains(side: int) -> void:
	var commander := _commander(side)
	for group_ally: bool in [false, true]:
		var free: Array[BattleUnit] = []
		for u: BattleUnit in units:
			if u.side == side and u.companion == null and u.ally == group_ally:
				free.append(u)
		if free.is_empty():
			continue
		free.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
			return (BattleEnums.is_cavalry(a.type)) and not (BattleEnums.is_cavalry(b.type)) or a.soldiers > b.soldiers)
		var head: Character = commander
		if side == player_side and ally_soldiers > 0 and not group_ally:
			head = player_leader
		for i in free.size():
			if i == 0 and head != null:
				free[i].captain = head
			else:
				free[i].captain = _make_captain(free[i].type)

# Pelotones propios: en una batalla ajena, todos los que mueves; en la tuya, el que encabezas y los de
# tu séquito (los capitanes y los compañeros prestados son tropa de tu señor).
func _mark_own_units() -> void:
	for u: BattleUnit in units:
		if u.side != player_side or u.ally:
			continue
		u.own = ally_soldiers > 0 or (player_leader != null and u.leader() == player_leader) \
			or (u.companion != null and not u.companion.has_meta("faction_companion"))

func _make_captain(type: int) -> Character:
	var c := Character.new()
	var cavalry := BattleEnums.is_cavalry(type)
	c.first_name = "Capitán de %s" % BattleEnums.unit_type_name(type).to_lower()
	c.set_meta("captain", true)
	c.role = Character.Role.CABALLERO if cavalry else Character.Role.SOLDADO
	var portrait_path := "res://assets/portraits/roles/%s.png" % ("caballero" if cavalry else "soldado")
	if ResourceLoader.exists(portrait_path):
		c.portrait = load(portrait_path)
	return c

func companions_of(side: int) -> Array[Character]:
	var result: Array[Character] = []
	for u: BattleUnit in units:
		if u.side == side and u.companion != null:
			result.append(u.companion)
	return result

func _wound_companion(u: BattleUnit, chance: float) -> void:
	if u.companion == null or randf() >= chance:
		return
	u.companion.wound_months = maxi(u.companion.wound_months, COMPANION_WOUND_MONTHS)
	wounded_companions.append(u.companion.full_name())
	log_message.emit("%s cae herido en la refriega." % u.companion.full_name())

func _has_skill(cmd: Character, skill_name: String) -> bool:
	if cmd == null:
		return false
	for s: Skill in cmd.battle_skills:
		if s != null and s.skill_name == skill_name:
			return true
	return false

# --- Duelos singulares entre jefes (campo abierto) ---

## Por qué el jefe de "u" no puede retar ahora al de "target" ("" si puede).
func challenge_blocker(u: BattleUnit, target: BattleUnit) -> String:
	if is_over:
		return "La batalla ha terminado."
	if has_walls:
		return "Solo en campo abierto: en un asedio nadie sale de la muralla a batirse."
	if u == null or target == null or not u.is_active() or not target.is_active() or u.side == target.side:
		return "Elige un pelotón enemigo."
	if u.has_acted:
		return "Ese pelotón ya actuó este turno."
	if u.challenged:
		return "Su jefe ya se batió (o retó) en esta batalla."
	if target.challenged:
		return "Ese jefe ya se batió en esta batalla."
	var a := u.leader()
	var b := target.leader()
	if a == null or b == null:
		return "No hay nadie al mando con quien batirse."
	if not a.is_alive() or a.is_wounded():
		return "%s está demasiado %s para batirse." % [a.full_name(), "malherida" if a.gender == CharacterEnums.Gender.FEMENINO else "malherido"]
	if a.honor < CHALLENGE_MIN_HONOR:
		return "%s necesita %d de honor para retar a un jefe enemigo (tiene %d)." % [a.full_name(), CHALLENGE_MIN_HONOR, a.honor]
	if not is_visible_to(u.side, target) or distance(u.cell, target.cell) > maxi(1, effective_attack_range(u)):
		return "El jefe enemigo está demasiado lejos: tiene que estar a tiro."
	return ""

func can_challenge(u: BattleUnit, target: BattleUnit) -> bool:
	return challenge_blocker(u, target).is_empty()

## Jefes enemigos a los que el de "u" puede retar ahora mismo.
func challenge_targets(u: BattleUnit) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	if u == null:
		return result
	for t: BattleUnit in active_units(_other_side(u.side)):
		if can_challenge(u, t):
			result.append(t)
	return result

## ¿Acepta el reto quien no mandas tú? Según su carácter, y se lo piensa si el retador es mucho mejor.
func accepts_challenge(challenger: Character, challenged: Character) -> bool:
	var chance: float = CHALLENGE_ACCEPT_BY_PERSONALITY.get(challenged.personality, CHALLENGE_ACCEPT_BASE)
	if challenged.combat + challenged.defense + CHALLENGE_WEAKER_GAP <= challenger.combat + challenger.defense:
		chance -= CHALLENGE_WEAKER_PENALTY
	# Un general sabe que, si cae, cae su bando: se lo piensa dos veces.
	if challenged == general_of(BattleEnums.Side.ATACANTE) or challenged == general_of(BattleEnums.Side.DEFENSOR):
		chance *= GENERAL_ACCEPT_FACTOR
	return randf() < clampf(chance, 0.05, 0.98)

## El retado rehúsa: el reto gasta la acción del retador y su bando pierde moral.
func refuse_challenge(challenger: BattleUnit, target: BattleUnit) -> void:
	challenger.challenged = true
	target.challenged = true
	challenger.has_acted = true
	for u: BattleUnit in active_units(target.side):
		u.morale = maxi(0, u.morale - CHALLENGE_REFUSE_MORALE)
	var text := "%s rehúsa el reto de %s: su bando pierde moral (−%d)." % [
		target.leader().full_name(), challenger.leader().full_name(), CHALLENGE_REFUSE_MORALE]
	log_message.emit(text)
	challenge_resolved.emit(text)
	state_updated.emit()

## Desenlace de un duelo de jefes: quien pierde se retira del campo con su pelotón.
func finish_challenge(challenger: BattleUnit, target: BattleUnit, challenger_won: bool) -> void:
	challenger.challenged = true
	target.challenged = true
	challenger.has_acted = true
	var winner := challenger if challenger_won else target
	var loser := target if challenger_won else challenger
	var text := "%s vence a %s en duelo singular: %s (%s) se retira del campo con su pelotón." % [
		winner.leader().full_name(), loser.leader().full_name(), BattleEnums.unit_type_name(loser.type), _side_label(loser.side)]
	_withdraw_from_field(loser, text)
	for u: BattleUnit in active_units(winner.side):
		u.morale = mini(100, u.morale + CHALLENGE_WIN_MORALE)
	challenge_resolved.emit(text)
	_check_end()
	state_updated.emit()

## Responde al reto que la IA lanzó a uno de tus jefes (y sigue el turno enemigo).
## Si aceptaste, "challenger_won" es el resultado del duelo que jugaste.
func answer_challenge(accepted: bool, challenger_won: bool = false) -> void:
	if pending_challenge.is_empty():
		return
	var u: BattleUnit = pending_challenge.challenger
	var t: BattleUnit = pending_challenge.target
	pending_challenge = {}
	if accepted:
		finish_challenge(u, t, challenger_won)
	else:
		refuse_challenge(u, t)
	_enemy_phase()

## Duelo entre dos jefes que no maneja el jugador: lo pelean las IA de duelo. Devuelve el ganador
## (o null si alguien huye) y cuenta en el registro cómo fue.
func auto_duel(a: Character, b: Character) -> Character:
	var d := DuelManager.new()
	var holder: Array = [null, ""]
	d.duel_ended.connect(func(w: Character, reason: String):
		holder[0] = w
		holder[1] = reason)
	d.start_duel(a, b)
	var actor := d.roll_first(a, b)
	var turns := 0
	while not d.is_over and turns < AUTO_DUEL_MAX_TURNS:
		var other := d.opponent_of(actor)
		var choice := DuelAI.choose(d, actor, other)
		d.set_posture(actor, choice.posture)
		d.take_turn(actor, choice.action)
		actor = other
		turns += 1
	var winner: Character = holder[0]
	if not d.is_over:
		# Nadie cae: los separan sus hombres y vence a los puntos quien conserva más vida.
		winner = a if a.current_health / float(maxi(1, a.max_health)) >= b.current_health / float(maxi(1, b.max_health)) else b
		holder[1] = "Los separan sus hombres; a los puntos, vence %s." % winner.full_name()
	log_message.emit("Duelo singular: %s contra %s — %d asaltos. %s" % [a.full_name(), b.full_name(), turns, holder[1]])
	for c: Character in [a, b]:
		c.after_fight_recovery()
	return winner

# La IA lanza como mucho un reto por turno, cuando su jefe cree poder ganar.
# Devuelve true si el reto es para uno de tus jefes y hay que esperar tu respuesta.
func _ai_try_challenge(side: int) -> bool:
	if has_walls or is_over or randf() >= AI_CHALLENGE_CHANCE:
		return false
	var best: Array = []
	var best_edge := -INF
	for u: BattleUnit in active_units(side):
		if side == player_side and not u.ally:
			continue   # tus pelotones solo retan cuando tú lo ordenas
		for t: BattleUnit in challenge_targets(u):
			var a := u.leader()
			var b := t.leader()
			var edge: float = (a.combat + a.defense) - (b.combat + b.defense) + randf()
			# Un general de la IA solo arriesga el bando en duelo si se sabe muy superior.
			if u.general and edge < AI_GENERAL_CHALLENGE_EDGE:
				continue
			if edge >= AI_CHALLENGE_MIN_EDGE and edge > best_edge:
				best_edge = edge
				best = [u, t]
	if best.is_empty():
		return false
	var challenger: BattleUnit = best[0]
	var target: BattleUnit = best[1]
	log_message.emit("¡%s reta a duelo singular a %s!" % [challenger.leader().full_name(), target.leader().full_name()])
	if is_player_unit(target):
		pending_challenge = {"challenger": challenger, "target": target}
		challenge_offered.emit(challenger, target)
		return true
	if not accepts_challenge(challenger.leader(), target.leader()):
		refuse_challenge(challenger, target)
		return false
	var winner := auto_duel(challenger.leader(), target.leader())
	finish_challenge(challenger, target, winner == challenger.leader())
	return false

func _withdraw_from_field(u: BattleUnit, text: String) -> void:
	u.routed = true
	u.left_field = true
	u.order = BattleEnums.Order.NINGUNA
	log_message.emit(text)
	unit_routed.emit(u, false)
	_check_end()

# --- Traición: tus pelotones se pasan al enemigo en plena batalla ---

## Por qué no puedes traicionar ahora ("" si puedes).
func betrayal_blocker() -> String:
	if is_over:
		return "La batalla ha terminado."
	if betrayed_side >= 0:
		return "Ya cambiaste de bando en esta batalla."
	if not pending_challenge.is_empty():
		return "Primero responde al reto."
	var own_units := 0
	var others := 0
	for u: BattleUnit in active_units(player_side):
		if u.own:
			own_units += 1
		else:
			others += 1
	if own_units == 0:
		return "No te queda ningún pelotón propio."
	if others == 0:
		return "Aquí solo luchas por ti: no hay bando al que traicionar."
	if _commander(_other_side(player_side)) == null:
		return "El enemigo no tiene a nadie al mando ante quien pasarte."
	return ""

## Cómo acabó cada jefe con nombre de un bando (para las capturas): "destroyed" (su pelotón fue
## aniquilado), "routed" (huyó), "withdrew" (se retiró a tiempo o perdió un duelo de jefes),
## "left" (abandonó el campo por su cuenta) o "standing" (seguía en pie). Devuelve [[Character, fate]].
func capture_fates(side: int) -> Array:
	var result: Array = []
	var seen: Array[Character] = []
	for u: BattleUnit in units:
		var c := u.leader()
		if u.side != side or not _named(c) or c in seen:
			continue
		seen.append(c)
		var fate := "standing"
		if u.soldiers <= 0:
			fate = "destroyed"
		elif u.left_field:
			fate = "left" if c == player_leader and deserted else "withdrew"
		elif u.routed:
			fate = "routed"
		elif retreating_side == side:
			fate = "withdrew"
		result.append([c, fate])
	var cmd := _commander(side)
	if _named(cmd) and not cmd in seen:
		result.append([cmd, "withdrew" if retreating_side == side else "standing"])
	return result

## Quienes lideran o mandan en un bando (sin contarte a ti), los que ven lo que haces.
func characters_on_side(side: int) -> Array[Character]:
	var result: Array[Character] = []
	var cmd := _commander(side)
	if cmd != null and cmd != player_leader:
		result.append(cmd)
	for u: BattleUnit in units:
		if u.side != side or u.own:
			continue
		var c := u.leader()
		if c != null and c != player_leader and not c in result:
			result.append(c)
	return result

## Te pasas al enemigo con tus pelotones (y los de tu séquito). Devuelve el texto del cartel.
func betray() -> String:
	var blocker := betrayal_blocker()
	if not blocker.is_empty():
		return blocker
	var old_side := player_side
	var new_side := _other_side(old_side)
	betrayed_characters = characters_on_side(old_side)
	for u: BattleUnit in units:
		u.officers.erase(player_leader)
		if u.side == old_side and u.own:
			_switch_unit_side(u, new_side, false)
		elif u.side == old_side:
			u.ally = false
		elif u.side == new_side:
			u.ally = true
	player_side = new_side
	betrayed_side = old_side
	if generals.get(old_side) == player_leader:
		generals.erase(old_side)
	# Si mandabas tú el bando traicionado, lo toma el jefe de mayor rango que quede.
	if _commander(old_side) == player_leader:
		var heir: Character = null
		for u: BattleUnit in active_units(old_side):
			if u.leader() != null:
				heir = u.leader()
				break
		if heir == null:
			heir = _make_captain(BattleEnums.UnitType.INFANTERIA)
		if old_side == BattleEnums.Side.ATACANTE:
			attacker_cmd = heir
		else:
			defender_cmd = heir
	var text := "¡%s traiciona a su bando y se pasa con sus hombres al lado de %s!" % [
		player_leader.full_name() if player_leader != null else "Tu capitán", _commander(new_side).full_name()]
	log_message.emit(text)
	_check_end()
	state_updated.emit()
	return text

# --- Fase 4: oficiales, choques RPG y deserciones ---

func _is_party_officer(c: Character) -> bool:
	var pd := _autoload("PartyData")
	return pd != null and pd.has_method("is_officer") and pd.is_officer(c)

## Oficiales: los del grupo marcados como oficiales y los que no tienen pelotón (más compañeros que pelotones)
## van con tu pelotón; en el otro bando, con los de su señor. Si tu señor te asigna, vas de oficial de su general.
func _assign_officers(side: int, companions: Array[Character]) -> void:
	var pool: Array[Character] = []
	var leading := {}
	for u: BattleUnit in units:
		if u.side == side:
			u.officers.clear()
		if u.leader() != null:
			leading[u.leader()] = true
	for c: Character in companions:
		if c != null and not c.is_wounded() and not leading.has(c) and not c in pool:
			pool.append(c)
	for c in faction_officers.get("player" if side == player_side else "enemy", []):
		if c is Character and not c.is_wounded() and not leading.has(c) and not c in pool:
			pool.append(c)
	if side == player_side:
		player_is_officer = _player_goes_as_officer(pool)
		if player_is_officer:
			var host := _officer_host(side)
			for u: BattleUnit in units:
				if u.side == side and u.captain == player_leader and u.companion == null:
					u.captain = _make_captain(u.type)
			if host != null:
				host.officers.append(player_leader)
				log_message.emit("Tu señor te pone de oficial de %s." % host.leader().full_name())
	var order: Array[BattleUnit] = []
	for u: BattleUnit in units:
		if u.side == side and u.is_active():
			order.append(u)
	# Primero tu pelotón (o el del general), luego los demás.
	order.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
		return _officer_priority(a) > _officer_priority(b))
	for c: Character in pool:
		for u: BattleUnit in order:
			if u.officers.size() < CampalEncounters.MAX_OFFICERS:
				u.officers.append(c)
				log_message.emit("%s va de oficial con %s." % [c.full_name(), u.leader().full_name() if u.leader() != null else "su pelotón"])
				break

func _officer_priority(u: BattleUnit) -> int:
	if player_leader != null and u.leader() == player_leader:
		return 3
	if u.general:
		return 2
	return 1 if not u.ally else 0

func _player_goes_as_officer(pool: Array[Character]) -> bool:
	if player_officer_override >= 0:
		return player_officer_override == 1
	# Sin séquito ni hombres propios en una batalla ajena, tu señor te pone en el pelotón de su general.
	var own_men := 0
	for u: BattleUnit in units:
		if u.side == player_side:
			own_men += u.soldiers
	return ally_soldiers > 0 and own_men - ally_soldiers < CAPTAIN_MIN_SOLDIERS and _own_companions == 0 		and pool.is_empty() and general_of(player_side) != player_leader

func _officer_host(side: int) -> BattleUnit:
	var best: BattleUnit = null
	for u: BattleUnit in units:
		if u.side != side or u.leader() == null or u.leader() == player_leader or u.leader().has_meta("captain"):
			continue
		if best == null or (u.general and not best.general):
			best = u
	return best

func abandon_chance() -> float:
	return abandon_chance_override if abandon_chance_override >= 0.0 else CampalEncounters.ABANDON_CHANCE

## ¿Este choque se juega en la pantalla RPG? Con tu grupo dentro, sí; los ajenos de tu bando, según Ajustes.
func encounter_is_played(enc: Dictionary) -> bool:
	if not interactive_encounters:
		return false
	if CampalEncounters.involves_player(self, enc):
		return true
	return not auto_resolve_others and (is_friendly(enc.attacker) or is_friendly(enc.target))

func _encounter(attacker: BattleUnit, target: BattleUnit, dist: int) -> bool:
	var enc := CampalEncounters.make(self, attacker, target, dist)
	attacker.has_acted = true
	attacker.has_moved = true
	var charged := attacker.order == BattleEnums.Order.CARGAR
	attacker.fatigue = mini(100, attacker.fatigue + _fatigue_gain(attacker, roundi(10 * CHARGE_FATIGUE) if charged else 10))
	if encounter_is_played(enc):
		pending_encounters.append(enc)
		log_message.emit("¡Choque! %s contra %s." % [enc.a[0].full_name(), enc.b[0].full_name()])
		encounter_pending.emit(enc)
		state_updated.emit()
		return true
	resolve_encounter(enc, CampalEncounters.auto_fight(self, enc))
	return true

## Aplica el resultado de un choque (bando 0 = atacante). Lo llama la pantalla tras jugarlo o «Resolver».
func resolve_encounter(enc: Dictionary, result: Dictionary) -> void:
	pending_encounters.erase(enc)
	var att: BattleUnit = enc.attacker
	var tgt: BattleUnit = enc.target
	if att.order == BattleEnums.Order.CARGAR:
		att.order = BattleEnums.Order.NINGUNA
	att.surge = 1.0
	var before := [tgt.soldiers, att.soldiers]
	var text := CampalEncounters.apply(self, enc, result)
	text += _flank_morale(tgt, int(enc.get("flank", 0)))
	unit_attacked.emit(att, tgt, before[0] - tgt.soldiers, before[1] - att.soldiers, false)
	log_message.emit(text)
	_check_rout(tgt)
	_check_rout(att)
	_check_end()
	state_updated.emit()

## Resolver solo el choque pendiente (mismas reglas que si lo juegas).
func auto_resolve_pending(enc: Dictionary) -> void:
	resolve_encounter(enc, CampalEncounters.auto_fight(self, enc))

## Un pelotón con jefe desleal puede pasarse al enemigo si su bando no va ganando; un oficial desleal, cambiar de pelotón.
func _check_defections() -> void:
	var chance := defect_chance_override if defect_chance_override >= 0.0 else CampalEncounters.DEFECT_CHANCE
	for u: BattleUnit in units.duplicate():
		if not u.is_active() or u.general or is_over:
			continue
		var lead := u.leader()
		var losing := _strength_ratio(u.side) <= _strength_ratio(_other_side(u.side)) * CampalEncounters.DEFECT_MAX_RATIO
		if lead != null and lead != player_leader and CampalEncounters._disloyal(lead) and losing and randf() < chance:
			var to := _other_side(u.side)
			_switch_unit_side(u, to, true)
			defections += 1
			var text := "¡%s se pasa al enemigo con sus %d hombres!" % [lead.full_name(), u.soldiers] if to != player_side \
				else "¡%s abandona a su señor y se une a tu bando!" % lead.full_name()
			log_message.emit(text)
			unit_defected.emit(u)
			continue
		for o: Character in u.officers.duplicate():
			if o != player_leader and CampalEncounters._disloyal(o) and losing and randf() < chance * CampalEncounters.OFFICER_DEFECT_CHANCE / CampalEncounters.DEFECT_CHANCE:
				u.officers.erase(o)
				for foe: BattleUnit in active_units(_other_side(u.side)):
					if foe.officers.size() < CampalEncounters.MAX_OFFICERS:
						foe.officers.append(o)
						break
				log_message.emit("¡%s, oficial desleal, se pasa al enemigo!" % o.full_name())
	_check_end()

## Cambio de bando de un pelotón (traición del jugador o deserción).
func _switch_unit_side(u: BattleUnit, new_side: int, by_ai: bool) -> void:
	u.side = new_side
	u.general = false
	u.reserve = false
	u.escort = false
	u.order = BattleEnums.Order.NINGUNA
	u.ally = by_ai and new_side == player_side
	if by_ai:
		u.own = false
		u.has_acted = true
		u.has_moved = true
