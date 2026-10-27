extends RefCounted
# Qué música suena en cada contexto. Uso: const MusicCatalog = preload("res://scripts/resources/music_catalog.gd")
# Las pistas están en assets/music/ (tools/generate_music.py y tools/generate_music_extra.py).
# En el mapa y el castillo se suma la variación de la cultura del lugar: map_<cultura>, castle_<cultura>.

# Orden = NameCatalog.Culture.
const CULTURE_KEYS := ["franca", "inglesa", "castellana", "imperial", "romana", "prusiana", "italiana", "borgonona", "aragonesa"]
const CULTURE_WEIGHT := 2   # la pieza de la cultura del lugar sale el doble que las genéricas

const POOLS := {
	"menu": ["menu"],
	"map": ["map", "map_b"],
	"travel": ["travel_a", "travel_b", "travel_c"],
	"castle": ["castle", "castle_b"],
	"court": ["court_a", "court_b"],
	"duel": ["duel", "duel_b", "duel_c"],
	"battle": ["battle", "battle_b", "battle_c"],
	"mourning": ["mourning_a", "mourning_b"],
	"captivity": ["captivity_a", "captivity_b"],
}
# Contextos que suman la pieza de la cultura: contexto -> prefijo del archivo.
const CULTURE_PREFIX := {"map": "map_", "travel": "map_", "castle": "castle_"}
# Contextos de combate: la pista no cambia a mitad de pelea (su capa de tensión va a tempo).
const NO_ROTATION := ["menu", "duel", "battle"]
const STINGS := ["sting_victory_a", "sting_victory_b", "sting_victory_c"]

# Escena -> contexto. Las escenas que no aparecen conservan lo que suena.
const SCENE_CONTEXT := {
	"main_menu": "menu", "new_game": "menu", "character_creation": "menu", "character_summary": "menu",
	"save_slots": "menu", "fighter_select": "menu",
	"map": "map", "relations": "court", "castle_interior": "castle",
	"combat": "duel", "battle": "battle", "succession": "mourning",
}

static func culture_key(culture: int) -> String:
	return CULTURE_KEYS[culture] if culture >= 0 and culture < CULTURE_KEYS.size() else ""

## Pistas candidatas (con repeticiones como peso). exists filtra las que no están en disco.
static func pool(context: String, culture: int, exists: Callable = Callable()) -> Array[String]:
	var out: Array[String] = []
	var ck := culture_key(culture)
	if CULTURE_PREFIX.has(context) and not ck.is_empty():
		var name: String = CULTURE_PREFIX[context] + ck
		for i in CULTURE_WEIGHT:
			out.append(name)
	for t: String in POOLS.get(context, []):
		out.append(t)
	if exists.is_valid():
		out = out.filter(func(t: String) -> bool: return exists.call(t))
	return out

## Elige una pista del contexto sin repetir la última (si hay alternativa).
static func pick(context: String, culture: int, last: String, exists: Callable = Callable()) -> String:
	var candidates := pool(context, culture, exists)
	if candidates.is_empty():
		return ""
	var fresh := candidates.filter(func(t: String) -> bool: return t != last)
	var from: Array = fresh if not fresh.is_empty() else candidates
	return from[randi() % from.size()]
