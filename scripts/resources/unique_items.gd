extends RefCounted
# Piezas únicas (ContentCatalog, nivel 4): raras, pero puede haber varias en el mundo.
# Se ganan explorando (y en la Torre del Caballero Negro), como premio de campeón de torneo,
# forjándolas en una herrería de nivel 3 o como trofeo al vencer en duelo a quien lleva una.
#   const UniqueItems = preload("res://scripts/resources/unique_items.gd")

const SELL_FACTOR := 0.4                 # lo que vale la pieza que se deja al ponerse la nueva
const TOURNAMENT_CHANCE := 0.25          # el campeón de un torneo recibe a veces una pieza única
const TROPHY_HONOR_COST := 5             # despojar a un vencido de su pieza única no es de caballeros...
const TROPHY_GRUDGE := 15                # ...y el vencido no lo olvida

static func catalog() -> Array:
	return GameData.equipment_catalog.filter(func(e: Equipment) -> bool: return SkillEffects.is_unique_item(e))

## Entrega una pieza única al azar que el personaje no tenga (o la indicada por nombre).
## Si ya ocupa esa ranura, la pieza anterior se vende. Devuelve el texto del hallazgo ("" si no hay).
static func grant(character: Character, item_name: String = "") -> String:
	var pool: Array = catalog().filter(func(e: Equipment) -> bool:
		return not character.equipment.any(func(o: Equipment) -> bool: return o.equipment_name == e.equipment_name))
	if not item_name.is_empty():
		pool = pool.filter(func(e: Equipment) -> bool: return e.equipment_name == item_name)
	if pool.is_empty():
		return ""
	var found: Equipment = pool.pick_random()
	return "¡Pieza única! " + give(character, found)

## Pone la pieza al personaje (vendiendo la que ocupaba su ranura). Devuelve el texto.
static func give(character: Character, item: Equipment) -> String:
	var slot_taken := character.equipment.any(func(e: Equipment) -> bool: return e.slot == item.slot)
	if not slot_taken and character.equipment.size() >= GameData.MAX_EQUIPMENT:
		# Sin hueco: se deja la pieza más barata para hacerle sitio.
		var cheapest: Equipment = character.equipment[0]
		for e: Equipment in character.equipment:
			if e.price < cheapest.price:
				cheapest = e
		character.unequip(cheapest)
		character.gold += maxi(1, roundi(cheapest.price * SELL_FACTOR))
	var replaced := character.equip(item.duplicate() as Equipment)
	if replaced != null:
		var value := maxi(1, roundi(replaced.price * SELL_FACTOR))
		character.gold += value
		return "Consigues %s (vendes %s por %d de oro). %s" % [item.equipment_name, replaced.equipment_name, value, item.description]
	return "Consigues %s. %s" % [item.equipment_name, item.description]

## Pieza única que lleva un personaje (la primera), o null.
static func carried_by(c: Character) -> Equipment:
	if c == null:
		return null
	for e: Equipment in c.equipment:
		if SkillEffects.is_unique_item(e):
			return e
	return null

## El vencedor despoja al vencido de su pieza única: cuesta honor y el vencido guarda rencor.
static func claim_trophy(winner: Character, loser: Character) -> String:
	var item := carried_by(loser)
	if item == null or winner == null:
		return ""
	loser.unequip(item)
	var text := give(winner, item)
	winner.honor = clampi(winner.honor - TROPHY_HONOR_COST, 0, 100)
	var tree := Engine.get_main_loop() as SceneTree
	var relations := tree.root.get_node_or_null("RelationsData") if tree != null else null
	if relations != null:
		var r: Relationship = relations.get_relation(loser.full_name())
		if r != null:
			r.adjust_grudge(TROPHY_GRUDGE)
	return "Despojas a %s de %s como trofeo (−%d de honor; no lo olvidará). %s" % [loser.full_name(), item.equipment_name, TROPHY_HONOR_COST, text]
