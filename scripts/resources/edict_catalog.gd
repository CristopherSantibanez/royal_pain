class_name EdictCatalog
# Edictos del Regente: una política activa a la vez, con efecto cada mes.
# Lógica pura: recibe los datos y devuelve un texto con lo aplicado; no referencia autoloads.

const LEVA := "leva"
const IMPUESTOS := "impuestos"
const TREGUA := "tregua"

const LEVA_GARRISON := 5          # por castillo de tu reino
const LEVA_FOOD := -10
const IMPUESTOS_GOLD := 40
const IMPUESTOS_HONOR := -1
const TREGUA_HONOR := 1
const TREGUA_AFFINITY := 2        # con todos los señores

const EDICTS := {
	LEVA: {"title": "Edicto de Leva",
		"description": "Cada mes, los castillos de tu reino suman %d soldados pero consumen %d de comida." % [LEVA_GARRISON, -LEVA_FOOD]},
	IMPUESTOS: {"title": "Edicto de Impuestos Altos",
		"description": "Cada mes ganas %d de oro, pero el pueblo murmura (honor %d)." % [IMPUESTOS_GOLD, IMPUESTOS_HONOR]},
	TREGUA: {"title": "Tregua del Rey",
		"description": "Cada mes ganas %d de honor y mejora %d la afinidad con todos los señores." % [TREGUA_HONOR, TREGUA_AFFINITY]},
}

static func title(id: String) -> String:
	return EDICTS[id].title if EDICTS.has(id) else "Ningún edicto"

static func description(id: String) -> String:
	return EDICTS[id].description if EDICTS.has(id) else ""

# Aplica el efecto mensual. Devuelve el texto para las noticias ("" si no hay edicto).
static func apply_monthly(id: String, player: Character, castles: Array[Castle], player_kingdom: int, relations: Array[Relationship]) -> String:
	if player == null or not EDICTS.has(id):
		return ""
	match id:
		LEVA:
			var n := 0
			for c: Castle in castles:
				if c.kingdom == player_kingdom:
					c.garrison_size += LEVA_GARRISON
					c.food = maxi(0, c.food + LEVA_FOOD)
					n += 1
			return "Edicto de Leva: %d castillos de tu reino reclutan %d soldados cada uno." % [n, LEVA_GARRISON]
		IMPUESTOS:
			var gold := SkillEffects.income(IMPUESTOS_GOLD, player)
			player.gold += gold
			player.honor = clampi(player.honor + IMPUESTOS_HONOR, 0, 100)
			return "Edicto de Impuestos: ingresan %d de oro a tus arcas." % gold
		TREGUA:
			player.honor = clampi(player.honor + TREGUA_HONOR, 0, 100)
			for r: Relationship in relations:
				if r.kind == Relationship.Kind.SENOR:
					r.adjust(TREGUA_AFFINITY)
			return "Tregua del Rey: los señores valoran tu paz."
	return ""
