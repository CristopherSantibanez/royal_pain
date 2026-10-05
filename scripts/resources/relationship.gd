class_name Relationship
extends Resource
# Relación del jugador con otro personaje del mundo: un señor de castillo, un rival de duelos
# o un cortesano (personaje generado que puebla los reinos y aún no se ha cruzado con el jugador).

enum Kind { SENOR, RIVAL_DUELO, CORTESANO }

@export var person_name: String = ""
@export var kind: Kind = Kind.SENOR
@export_range(-100, 100) var affinity: int = 0
@export var allied: bool = false              # alianza formal (solo señores)
@export var at_war: bool = false              # guerra declarada (solo señores)
@export var duels_won_against: int = 0        # duelos que el jugador le ganó
@export var duels_lost_against: int = 0
@export var character: Character              # ficha del personaje (retrato, stats) para duelos y batallas
@export var kingdom: int = -1                  # reino de origen (cortesanos)

const ALLIANCE_MIN_AFFINITY := 40
const ALLIANCE_BREAK_AFFINITY := 10
const HOSTILE_AFFINITY := -20

func adjust(amount: int) -> void:
	affinity = clampi(affinity + amount, -100, 100)

func is_hostile() -> bool:
	return at_war or affinity <= HOSTILE_AFFINITY

func status_text() -> String:
	if allied:
		return "Aliado"
	if at_war:
		return "En guerra"
	if affinity >= 60: return "Muy amistoso"
	if affinity >= 20: return "Amistoso"
	if affinity > HOSTILE_AFFINITY: return "Neutral"
	if affinity > -60: return "Hostil"
	return "Enemigo jurado"
