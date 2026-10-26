class_name Relationship
extends Resource
# Relación del jugador con otro personaje del mundo: un señor de castillo, un rival de duelos,
# un cortesano (personaje generado que puebla los reinos y aún no se ha cruzado con el jugador)
# o su cónyuge.

enum Kind { SENOR, RIVAL_DUELO, CORTESANO, CONYUGE, PUEBLO }   # PUEBLO: campesinos y soldados
enum RivalryStage { CONOCIDO, RIVAL, NEMESIS, RESPETO }

@export var person_name: String = ""
@export var kind: Kind = Kind.SENOR
@export_range(-100, 100) var affinity: int = 0
@export var allied: bool = false              # alianza formal (solo señores)
@export var at_war: bool = false              # guerra declarada (solo señores)
@export var duels_won_against: int = 0        # duelos que el jugador le ganó
@export var duels_lost_against: int = 0
@export var character: Character              # ficha del personaje (retrato, stats) para duelos y batallas
@export var kingdom: int = -1                  # reino de origen (cortesanos)

@export_group("Rivalidad")
@export_range(-100, 100) var grudge: int = 0  # rencor hacia el jugador; muy negativo = respeto
@export var last_duel_month: int = -1         # meses de partida transcurridos en el último duelo

@export_group("Romance")
@export_range(0, 100) var affection: int = 0  # intimidad con el jugador (amistad o amor)
@export var romance: bool = false             # hay amor, no solo amistad (solo entre hombre y mujer)
@export var last_courted_month: int = -1
@export var rival_suitor: String = ""         # otro pretendiente que compite por su afecto

const ALLIANCE_MIN_AFFINITY := 40
const ALLIANCE_BREAK_AFFINITY := 10
const HOSTILE_AFFINITY := -20

const RIVAL_GRUDGE := 40
const NEMESIS_GRUDGE := 70
const RESPECT_GRUDGE := -20

const ROMANCE_INTEREST := 20
const ROMANCE_COURTSHIP := 50
const ROMANCE_IN_LOVE := 70

func adjust(amount: int) -> void:
	affinity = clampi(affinity + amount, -100, 100)

func adjust_grudge(amount: int) -> void:
	grudge = clampi(grudge + amount, -100, 100)

func adjust_affection(amount: int) -> void:
	affection = clampi(affection + amount, 0, 100)

func is_hostile() -> bool:
	return at_war or affinity <= HOSTILE_AFFINITY

func is_female() -> bool:
	return character != null and character.gender == CharacterEnums.Gender.FEMENINO

func _g(masc: String, fem: String) -> String:
	return fem if is_female() else masc

func rivalry_stage() -> int:
	if grudge <= RESPECT_GRUDGE:
		return RivalryStage.RESPETO
	if grudge >= NEMESIS_GRUDGE:
		return RivalryStage.NEMESIS
	if grudge >= RIVAL_GRUDGE:
		return RivalryStage.RIVAL
	return RivalryStage.CONOCIDO

func rivalry_text() -> String:
	match rivalry_stage():
		RivalryStage.RESPETO: return "Te respeta"
		RivalryStage.NEMESIS: return "Tu némesis"
		RivalryStage.RIVAL: return _g("Rival enconado", "Rival enconada")
	return _g("Conocido", "Conocida")

func romance_text() -> String:
	if kind == Kind.CONYUGE:
		return _g("Tu esposo", "Tu esposa")
	if not romance:
		return ""
	if affection >= ROMANCE_IN_LOVE: return _g("Enamorado de ti", "Enamorada de ti")
	if affection >= ROMANCE_COURTSHIP: return "Acepta tu cortejo"
	return "Siente interés"

func status_text() -> String:
	if allied:
		return _g("Aliado", "Aliada")
	if at_war:
		return "En guerra"
	if affinity >= 60: return _g("Muy amistoso", "Muy amistosa")
	if affinity >= 20: return _g("Amistoso", "Amistosa")
	if affinity > HOSTILE_AFFINITY: return "Neutral"
	if affinity > -60: return "Hostil"
	return _g("Enemigo jurado", "Enemiga jurada")
