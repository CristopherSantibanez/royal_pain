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
var order: int = BattleEnums.Order.NINGUNA   # Mantener posición o Cargar (dura hasta cambiarla o, la carga, hasta golpear)
var bonus_move: int = 0            # casillas extra este turno (habilidad Carga de caballería)
var surge: float = 1.0             # multiplicador de su próximo golpe (habilidades como Emboscada)
var ally: bool = false             # de tu bando, pero lo mueve la IA aliada (batallas a las que te invitan)
var own: bool = false              # tuyo de verdad (tu pelotón y los de tu séquito): se pasa de bando contigo si traicionas
var challenged: bool = false       # su jefe ya retó (o fue retado) a duelo en esta batalla
var left_field: bool = false       # se retiró del campo tras perder un duelo de jefes
var general: bool = false          # lo encabeza el general del bando: si cae, el bando pierde

## Quien encabeza el pelotón (su cara se ve sobre él en el tablero).
func leader() -> Character:
	return companion if companion != null else captain

func is_active() -> bool:
	return not routed and soldiers > 0

func move_range() -> int:
	return BattleEnums.stat(type, "move")

func attack_range() -> int:
	return BattleEnums.stat(type, "range")

func family() -> int:
	return BattleEnums.family_of(type)

func describe() -> String:
	var text := "%s — %d/%d soldados | Moral %d | Fatiga %d" % [
		BattleEnums.unit_type_name(type), soldiers, max_soldiers, morale, fatigue
	]
	var trait_text := BattleEnums.unit_type_trait(type)
	if not trait_text.is_empty():
		text += "\n" + trait_text
	if general and leader() != null:
		text += "\nGeneral del bando: %s (si cae, su bando pierde)" % leader().full_name()
	if companion != null:
		text += "\nAl mando: %s%s" % [companion.full_name(), " (de facción)" if companion.has_meta("faction_companion") else ""]
	if ally:
		text += "\nAliado: lo mueve su señor, no tú"
	if order != BattleEnums.Order.NINGUNA:
		text += "\nOrden: " + BattleEnums.order_name(order)
	if surge > 1.0:
		text += "\nPróximo golpe: +%d%%" % roundi((surge - 1.0) * 100)
	return text

func reset_turn() -> void:
	has_moved = false
	last_move_distance = 0
	has_acted = false
	bonus_move = 0
