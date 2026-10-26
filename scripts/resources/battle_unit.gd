class_name BattleUnit
extends RefCounted

# Umbral de moral bajo el cual el pelotón huye del campo
const ROUT_MORALE := 25

var side: BattleEnums.Side = BattleEnums.Side.ATACANTE
var type: BattleEnums.UnitType = BattleEnums.UnitType.INFANTERIA
var soldiers: int = 0
var max_soldiers: int = 0
var morale: int = 70
var fatigue: int = 0
var cell: Vector2i = Vector2i.ZERO

var has_moved: bool = false
var last_move_distance: int = 0   # casillas recorridas en su último movimiento de este turno (cargas)
var has_acted: bool = false
var routed: bool = false
var companion: Character           # compañero (séquito o de facción) que dirige este pelotón, o null
var captain: Character             # quien manda el pelotón si no hay compañero: el comandante o un capitán

## Quien encabeza el pelotón (su cara se ve sobre él en el tablero).
func leader() -> Character:
	return companion if companion != null else captain

func is_active() -> bool:
	return not routed and soldiers > 0

func move_range() -> int:
	match type:
		BattleEnums.UnitType.CABALLERIA: return 4
		_: return 2

func attack_range() -> int:
	match type:
		BattleEnums.UnitType.ARQUEROS: return 3
		_: return 1

func describe() -> String:
	var text := "%s — %d/%d soldados | Moral %d | Fatiga %d" % [
		BattleEnums.unit_type_name(type), soldiers, max_soldiers, morale, fatigue
	]
	if companion != null:
		text += "\nAl mando: %s%s" % [companion.full_name(), " (de facción)" if companion.has_meta("faction_companion") else ""]
	return text

func reset_turn() -> void:
	has_moved = false
	last_move_distance = 0
	has_acted = false
