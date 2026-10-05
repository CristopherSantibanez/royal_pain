extends Node
# Autoload — registrar como "MapData"

const MAP_WIDTH: float = 1536.0
const MAP_HEIGHT: float = 1024.0

var castles: Array[Castle] = []

func _ready() -> void:
	_load_castles()

func reset() -> void:
	_load_castles()

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
