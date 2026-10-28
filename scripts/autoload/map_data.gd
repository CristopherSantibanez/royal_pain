extends Node
# Autoload — registrar como "MapData"

const MAP_WIDTH: float = 1536.0
const MAP_HEIGHT: float = 1024.0

# --- Mundo aleatorio: cada partida nueva tiene otros señores, otras fuerzas y otra diplomacia ---
const GARRISON_VARIATION := 0.25        # ±25% sobre la guarnición base de cada castillo
const RESOURCE_VARIATION := 0.3         # ±30% sobre oro y comida

const NameCatalog = preload("res://scripts/resources/name_catalog.gd")
const REALM_NAME_TRIES := 20
const LORD_NAME_TRIES := 20

var castles: Array[Castle] = []:
	set(value):
		castles = value
		refresh_kingdom_names()   # también al cargar una partida
var world_seed: int = 0
var world_used := false     # el mundo actual ya se jugó: una partida nueva debe generar otro

func _ready() -> void:
	new_world()

func reset() -> void:
	new_world()

## Genera un mundo nuevo (señores, recursos). seed < 0 = al azar.
func new_world(seed: int = -1) -> void:
	world_seed = seed if seed >= 0 else randi() % 1000000
	world_used = false
	_load_castles()
	_randomize_world()

# Señores con nombre, sexo y casa al azar; recursos con variación. El más fuerte lleva la corona.
func _randomize_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var strongest: Castle = null
	for c: Castle in castles:
		c.garrison_size = maxi(10, roundi(c.garrison_size * rng.randf_range(1.0 - GARRISON_VARIATION, 1.0 + GARRISON_VARIATION)))
		c.gold = maxi(0, roundi(c.gold * rng.randf_range(1.0 - RESOURCE_VARIATION, 1.0 + RESOURCE_VARIATION)))
		c.food = maxi(0, roundi(c.food * rng.randf_range(1.0 - RESOURCE_VARIATION, 1.0 + RESOURCE_VARIATION)))
		if c.kingdom == KingdomEnums.Kingdom.NEUTRAL:
			continue
		if strongest == null or c.garrison_size > strongest.garrison_size:
			strongest = c
	_assign_cultures(rng)
	_name_realms(rng)
	var used_lords := {}
	for c: Castle in castles:
		if c.kingdom == KingdomEnums.Kingdom.NEUTRAL:
			continue
		var female := rng.randf() < 0.5
		var crowned := c == strongest
		var title := ("Reina" if female else "Rey") if crowned else ("Lady" if female else "Lord")
		var gender := CharacterEnums.Gender.FEMENINO if female else CharacterEnums.Gender.MASCULINO
		var lord := ""
		for _attempt in LORD_NAME_TRIES:
			var first := NameCatalog.first_name(c.culture, gender, rng)
			var house := NameCatalog.gendered_surname(NameCatalog.house(c.culture, rng), c.culture, gender)
			lord = "%s %s %s" % [title, first, house]
			if not used_lords.has(lord):
				break
		used_lords[lord] = true
		c.owner_name = lord
		c.original_owner = c.owner_name

# Cada reino tiene una cultura (franca, anglonormanda, castellana...): de ella salen los nombres de su gente.
# Se reparten barajadas para que no haya dos reinos iguales mientras alcancen; la isla neutral toma una al azar.
func _assign_cultures(rng: RandomNumberGenerator) -> void:
	var order: Array = range(NameCatalog.CULTURE_COUNT)
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var by_kingdom := {}
	var next := 0
	for c: Castle in castles:
		if c.kingdom == KingdomEnums.Kingdom.NEUTRAL:
			c.culture = rng.randi() % NameCatalog.CULTURE_COUNT
			continue
		if not by_kingdom.has(c.kingdom):
			by_kingdom[c.kingdom] = order[next % order.size()]
			next += 1
		c.culture = by_kingdom[c.kingdom]

# Cada reino recibe un nombre de su cultura («Reino de Valdemora», «Ducado de Hohenstein»...), sin repetir.
# El castillo principal lleva el mismo nombre que su reino.
func _name_realms(rng: RandomNumberGenerator) -> void:
	var used := {}
	for c: Castle in castles:
		var realm := ""
		for _attempt in REALM_NAME_TRIES:
			realm = NameCatalog.realm_name(c.culture, rng, c.kingdom == KingdomEnums.Kingdom.NEUTRAL)
			if not used.has(realm):
				break
		used[realm] = true
		c.castle_name = realm
	refresh_kingdom_names()

## Nombres de los reinos del mundo actual, sacados del castillo de origen de cada uno. Las partidas
## antiguas guardan los nombres fijos en sus castillos, así que siguen viéndose igual.
func refresh_kingdom_names() -> void:
	KingdomEnums.custom_names.clear()
	for c: Castle in castles:
		var k: int = c.original_kingdom if c.original_kingdom >= 0 else c.kingdom
		if not KingdomEnums.custom_names.has(k) and not c.castle_name.is_empty():
			KingdomEnums.custom_names[k] = c.castle_name

## Cultura de la gente de un reino (la de su castillo de origen). Partidas antiguas: una fija por reino.
func culture_of_kingdom(kingdom: int) -> int:
	for c: Castle in castles:
		if c.original_kingdom == kingdom and c.culture >= 0:
			return c.culture
	for c: Castle in castles:
		if c.kingdom == kingdom and c.culture >= 0:
			return c.culture
	return absi(kingdom) % NameCatalog.CULTURE_COUNT

## Cultura del lugar donde está un castillo.
func culture_of_castle(castle: Castle) -> int:
	if castle == null:
		return -1
	return castle.culture if castle.culture >= 0 else culture_of_kingdom(castle.original_kingdom if castle.original_kingdom >= 0 else castle.kingdom)

## «Reino de X», o «Reino de X (ahora de Reino de Y)» si el castillo cambió de manos.
func place_label(castle: Castle) -> String:
	if castle == null:
		return ""
	var realm := KingdomEnums.kingdom_name(castle.kingdom)
	return castle.castle_name if castle.castle_name == realm else "%s (%s)" % [castle.castle_name, realm]

## Título del monarca del mundo actual (o "" si no hay).
func crown_holder() -> String:
	for c: Castle in castles:
		if c.owner_name.begins_with("Rey ") or c.owner_name.begins_with("Reina "):
			return c.owner_name
	return ""

## Resumen corto del mundo generado (para la pantalla de Nueva Partida).
func world_summary() -> String:
	var crown := crown_holder()
	var crown_castle: Castle = null
	for c: Castle in castles:
		if c.owner_name == crown:
			crown_castle = c
	var text := "Mundo n.º %d" % world_seed
	if crown_castle != null:
		text += " · Corona: %s (%s, %d soldados)" % [crown, KingdomEnums.kingdom_name(crown_castle.kingdom), crown_castle.garrison_size]
	return text

func get_castle_by_id(id: String) -> Castle:
	for c in castles:
		if c.castle_id == id:
			return c
	return null

func _pos(fx: float, fy: float) -> Vector2:
	return Vector2(fx * MAP_WIDTH, fy * MAP_HEIGHT)

func _make_castle(id: String, n: String, kingdom: int, fx: float, fy: float, connections: Array[String],
		owner_name: String = "Sin Señor", garrison: int = 50, gold: int = 200, food: int = 150) -> Castle:
	var c := Castle.new()
	c.castle_id = id
	c.castle_name = n
	c.kingdom = kingdom
	c.position_on_map = _pos(fx, fy)
	c.connected_castle_ids = connections
	c.owner_name = owner_name
	c.garrison_size = garrison
	c.gold = gold
	c.food = food
	c.original_kingdom = kingdom
	c.original_owner = owner_name
	return c

func _load_castles() -> void:
	castles = [
		_make_castle("hielo", "Reino de Hielo", KingdomEnums.Kingdom.HIELO, 0.18, 0.14, ["bosque", "azul"],
			"Lord Cairn Escarcha", 90, 400, 300),
		_make_castle("bosque", "Reino del Bosque", KingdomEnums.Kingdom.BOSQUE, 0.44, 0.18, ["hielo", "dorado", "carmesi"],
			"Lady Elowen Silvano", 70, 350, 500),
		_make_castle("dorado", "Reino Dorado", KingdomEnums.Kingdom.DORADO, 0.68, 0.17, ["bosque", "cumbres", "esmeralda"],
			"Lord Aurelio Dorado", 100, 700, 350),
		_make_castle("cumbres", "Reino de las Cumbres", KingdomEnums.Kingdom.CUMBRES, 0.82, 0.24, ["dorado", "esmeralda"],
			"Lord Baram Roca Alta", 120, 300, 200),
		_make_castle("azul", "Reino Azul", KingdomEnums.Kingdom.AZUL, 0.20, 0.33, ["hielo", "carmesi", "desierto"],
			"Lady Vess Marea", 80, 450, 350),
		_make_castle("carmesi", "Reino Carmesí", KingdomEnums.Kingdom.CARMESI, 0.36, 0.46, ["bosque", "azul", "desierto", "ambar", "gris", "neutral"],
			"Rey Draven Carmesí", 150, 800, 500),
		_make_castle("neutral", "Isla Neutral", KingdomEnums.Kingdom.NEUTRAL, 0.55, 0.43, ["carmesi", "esmeralda", "gris"],
			"Sin Señor", 20, 50, 100),
		_make_castle("esmeralda", "Reino Esmeralda", KingdomEnums.Kingdom.ESMERALDA, 0.75, 0.46, ["dorado", "cumbres", "neutral", "gris", "oliva"],
			"Lord Themis Verdemar", 95, 500, 450),
		_make_castle("desierto", "Reino del Desierto", KingdomEnums.Kingdom.DESIERTO, 0.11, 0.55, ["azul", "carmesi", "ambar"],
			"Lady Sahira Duna", 75, 550, 200),
		_make_castle("ambar", "Reino Ámbar", KingdomEnums.Kingdom.AMBAR, 0.23, 0.73, ["carmesi", "desierto", "gris"],
			"Lord Ferran Ámbar", 65, 300, 250),
		_make_castle("gris", "Reino Gris", KingdomEnums.Kingdom.GRIS, 0.47, 0.77, ["carmesi", "neutral", "esmeralda", "ambar", "oliva"],
			"Lord Malcorn Piedra Gris", 110, 400, 300),
		_make_castle("oliva", "Reino Oliva", KingdomEnums.Kingdom.OLIVA, 0.72, 0.74, ["esmeralda", "gris"],
			"Lady Iris Olivar", 70, 350, 400),
	]
