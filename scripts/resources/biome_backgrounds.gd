extends RefCounted
# Fondos de combate por bioma. Para añadir fondos, deja imágenes (PNG/JPG/WebP) en
# assets/backgrounds/<bioma>/ ; se elige una al azar. Si la carpeta está vacía, se usa el fondo de serie.
# Biomas: hielo, montana, bosque, llanura, desierto, costa, torneo.
# Uso: const BiomeBackgrounds = preload("res://scripts/resources/biome_backgrounds.gd")

const DIR := "res://assets/backgrounds/%s/"
const EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const TOURNAMENT := "torneo"
const DEFAULT_BIOME := "llanura"

# Fondo de serie de cada bioma (los que ya existían).
const FALLBACK := {
	"hielo": "res://assets/TurnFight-Snow.png",
	"montana": "res://assets/TurnFight-Snow.png",
	"bosque": "res://assets/TurnFight-Meadow.png",
	"llanura": "res://assets/TurnFight-Meadow.png",
	"desierto": "res://assets/TurnFight-Desert.png",
	"costa": "res://assets/TurnFight-Seaside.png",
	"torneo": "res://assets/TurnFight-Trining_Ground.png",
}

static var _cache := {}   # bioma -> rutas encontradas (se lee la carpeta una sola vez)

## Bioma de un reino (KingdomEnums.Kingdom). Debe coincidir con el terreno de las batallas (BattleManager).
static func biome_of_kingdom(k: int) -> String:
	match k:
		KingdomEnums.Kingdom.HIELO: return "hielo"
		KingdomEnums.Kingdom.CUMBRES, KingdomEnums.Kingdom.GRIS: return "montana"
		KingdomEnums.Kingdom.BOSQUE, KingdomEnums.Kingdom.ESMERALDA: return "bosque"
		KingdomEnums.Kingdom.DESIERTO, KingdomEnums.Kingdom.AMBAR, KingdomEnums.Kingdom.DORADO: return "desierto"
		KingdomEnums.Kingdom.AZUL, KingdomEnums.Kingdom.NEUTRAL: return "costa"
	return DEFAULT_BIOME

## Bioma del lugar donde está el jugador ahora (castillo actual del viaje, o el de la escena).
static func current_biome() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return DEFAULT_BIOME
	var castle: Castle = null
	var travel := tree.root.get_node_or_null("TravelData")
	if travel != null and travel.has_method("current_castle"):
		castle = travel.current_castle()
	if castle == null:
		var gm := tree.root.get_node_or_null("GameManager")
		if gm != null:
			castle = gm.current_castle
	return biome_of_kingdom(castle.kingdom) if castle != null else DEFAULT_BIOME

## Textura de fondo para un bioma: una imagen al azar de su carpeta o, si no hay, la de serie.
static func texture_for(biome: String) -> Texture2D:
	var paths: Array = _paths(biome)
	var path: String = paths.pick_random() if not paths.is_empty() else FALLBACK.get(biome, FALLBACK[DEFAULT_BIOME])
	return load(path) if ResourceLoader.exists(path) else null

static func _paths(biome: String) -> Array:
	if _cache.has(biome):
		return _cache[biome]
	var found := []
	var dir := DIR % biome
	for f in DirAccess.get_files_at(dir):
		# En el juego exportado las imágenes aparecen como «x.png.import»: se usa la ruta original.
		var name := f.trim_suffix(".import")
		if name.get_extension().to_lower() in EXTENSIONS and not (dir + name) in found:
			found.append(dir + name)
	_cache[biome] = found
	return found
