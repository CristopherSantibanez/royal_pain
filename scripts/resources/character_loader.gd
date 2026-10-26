class_name CharacterLoader

# Personajes guardados (editor de personajes y PNJ guardados desde su ficha): archivos JSON
# en <datos>/characters (ver DataCodec). Los .tres de versiones anteriores se convierten al listarlos.

static func characters_dir() -> String:
	return DataPaths.path("characters")

static func get_saved_character_paths() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(characters_dir())
	if dir == null:
		return result
	_migrate_legacy_characters(dir)
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			result.append("%s/%s" % [characters_dir(), file_name])
	result.sort()
	return result

## Carga un personaje guardado; cada llamada devuelve una copia nueva. null si el archivo no vale.
static func load_character(path: String) -> Character:
	return DataCodec.read_file(path) as Character

## Guarda un personaje sin pisar otro con el mismo nombre. Devuelve la ruta, o "" si falla.
static func save_character(character: Character, overwrite: bool = false) -> String:
	var base_name := character.full_name().strip_edges().to_lower().replace(" ", "_")
	if base_name.is_empty():
		base_name = "personaje_sin_nombre"
	var path := "%s/%s.json" % [characters_dir(), base_name]
	var n := 2
	while not overwrite and FileAccess.file_exists(path):
		path = "%s/%s_%d.json" % [characters_dir(), base_name, n]
		n += 1
	return path if DataCodec.write_file(path, character) == OK else ""

static func _migrate_legacy_characters(dir: DirAccess) -> void:
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var old_path := "%s/%s" % [characters_dir(), file_name]
		var old := ResourceLoader.load(old_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Character
		if old != null and DataCodec.write_file(old_path.trim_suffix(".tres") + ".json", old) == OK:
			DirAccess.rename_absolute(old_path, old_path + ".migrado")

const MALE_NAMES := ["Godofredo", "Bertrand", "Rodrigo", "Aldric", "Tristán", "Leopoldo", "Hugo", "Gonzalo", "Wulfric", "Anselmo",
	"Álvaro", "Beltrán", "Diego", "Fadrique", "Guillén", "Íñigo", "Lope", "Martín", "Nuño", "Ordoño", "Pelayo", "Sancho", "Tello", "Vela"]
const FEMALE_NAMES := ["Matilde", "Urraca", "Leonor", "Isolda", "Brunilda", "Jimena", "Adela", "Sancha", "Eloísa", "Gisela",
	"Aldonza", "Beatriz", "Catalina", "Dulce", "Estefanía", "Fronilde", "Guiomar", "Inés", "Juana", "María", "Oria", "Teresa", "Toda", "Violante"]
const LAST_NAMES := ["de Valcerro", "Piedrahíta", "del Roble", "Mantonegro", "de Altamira", "Hierrofuerte", "de la Torre", "Lanzagris",
	"Vadoscuro", "de Montealto", "Escudoviejo", "de Peñaluna", "Robledal", "de Fuentefría", "Aceroduro", "de Torrealba",
	"Valdecuervo", "de la Ribera", "Lobonegro", "de Castroverde"]
const RIVAL_STAT_SPREAD := 2
const ContentCatalog = preload("res://scripts/resources/content_catalog.gd")

# Calidad de los PNJ según su rango: puntos libres de estadística y número de habilidades por categoría.
const NPC_FREE_POINTS := {
	Character.Role.CAMPESINO: 4, Character.Role.SOLDADO: 8, Character.Role.CABALLERO: 10,
	Character.Role.NOBLEZA_BAJA: 12, Character.Role.NOBLEZA_ALTA: 14, Character.Role.REGENTE: 15,
}
const NPC_SKILLS := {   # [generales, combate, batalla]
	Character.Role.CAMPESINO: [1, 0, 0], Character.Role.SOLDADO: [0, 1, 1], Character.Role.CABALLERO: [1, 1, 1],
	Character.Role.NOBLEZA_BAJA: [1, 1, 2], Character.Role.NOBLEZA_ALTA: [2, 2, 2], Character.Role.REGENTE: [2, 2, 3],
}

# Oro inicial aproximado según el rango (solo ambientación de los PNJ).
const GOLD_BY_ROLE := {
	Character.Role.CAMPESINO: 30, Character.Role.SOLDADO: 80, Character.Role.CABALLERO: 200,
	Character.Role.NOBLEZA_BAJA: 500, Character.Role.NOBLEZA_ALTA: 1500, Character.Role.REGENTE: 3000,
}

static func random_first_name(gender: int) -> String:
	return (FEMALE_NAMES if gender == CharacterEnums.Gender.FEMENINO else MALE_NAMES).pick_random()

static func random_last_name() -> String:
	return LAST_NAMES.pick_random()

# Personaje completo con todos sus parámetros al azar, siguiendo las mismas reglas que la creación
# (stats base por personalidad/alineación/tipo, 3 ventajas, 2 desventajas), pero con calidad según
# su rango: más puntos libres, más habilidades y mejor equipo cuanto más alto está.
# Nunca recibe el retrato del jugador: si no se le pasa uno, se elige otro de la galería.
static func make_random_character(role: int, gender: int, portrait_path: String = "",
		first_name: String = "", last_name: String = "") -> Character:
	var c := Character.new()
	c.gender = gender
	c.first_name = first_name if first_name != "" else random_first_name(gender)
	c.last_name = last_name if (last_name != "" or first_name != "") else random_last_name()
	c.role = role
	c.personality = Character.Personality.values().pick_random()
	c.alignment = CharacterEnums.Alignment.values().pick_random()
	c.fighter_type = CharacterEnums.FighterType.values().pick_random()

	var stats := GameData.get_base_stats(c.personality, c.alignment, c.fighter_type)
	var keys := stats.keys()
	var points: int = NPC_FREE_POINTS.get(role, GameData.FREE_POINTS)
	while points > 0:
		var k = keys.pick_random()
		if stats[k] < PointAllocator.STAT_MAX:
			stats[k] += 1
			points -= 1
	c.leadership = stats.leadership
	c.charisma = stats.charisma
	c.strategy = stats.strategy
	c.combat = stats.combat
	c.defense = stats.defense

	c.advantages.assign(_pick(GameData.advantages, 3))
	c.disadvantages.assign(_pick(GameData.disadvantages, 2))
	var skill_counts: Array = NPC_SKILLS.get(role, [1, 1, 1])
	c.general_skills.assign(_pick(GameData.general_skills, skill_counts[0]))
	c.combat_skills.assign(_pick(GameData.combat_skills, skill_counts[1]))
	c.battle_skills.assign(_pick(GameData.battle_skills, skill_counts[2]))
	c.equipment.assign(_pick_equipment(role))
	c.apply_trait_and_equipment_modifiers()

	c.honor = randi_range(40, 70)
	c.gold = GOLD_BY_ROLE.get(role, 100)
	if portrait_path == "":
		portrait_path = _free_portrait(gender)
	if portrait_path != "":
		c.portrait = load(portrait_path)
	return c

# Equipo del PNJ: una pieza por ranura, del nivel que corresponde a su rango.
static func _pick_equipment(role: int) -> Array:
	var rules: Dictionary = ContentCatalog.NPC_EQUIPMENT_BY_ROLE.get(role, {"tiers": [1], "pieces": [0, 1]})
	var pieces := randi_range(rules.pieces[0], rules.pieces[1])
	var pool: Array = GameData.equipment_catalog.filter(func(e: Equipment): return e.tier in rules.tiers)
	pool.shuffle()
	var chosen: Array = []
	var used_slots := {}
	for e: Equipment in pool:
		if chosen.size() >= mini(pieces, Character.MAX_EQUIPMENT):
			break
		if not used_slots.has(e.slot):
			used_slots[e.slot] = true
			chosen.append(e)
	return chosen

# Ruta del retrato que ve el jugador (propio o el genérico de su rol/sexo), para no repetirlo en un PNJ.
static func player_portrait_path() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var gm := tree.root.get_node_or_null("GameManager") if tree != null else null
	var player: Character = gm.player_character if gm != null else null
	if player == null:
		return ""
	var tex := player.get_portrait()
	return tex.resource_path if tex != null else ""

# Un retrato de la galería que no sea el del jugador (los PNJ pueden repetirse entre sí si se agotan).
static func _free_portrait(gender: int) -> String:
	var forbidden := player_portrait_path()
	var options := PortraitGallery.get_portraits_for_gender(gender).filter(func(path: String): return path != forbidden)
	return options.pick_random() if not options.is_empty() else ""

## Guarda una copia de un PNJ entre los personajes del editor (aparece en Nueva Partida,
## Duelo de práctica y el editor). Devuelve la ruta, o "" si falló.
static func save_npc(character: Character) -> String:
	if character == null:
		return ""
	var copy := character.duplicate(true) as Character
	copy.current_health = copy.max_health
	copy.current_stamina = copy.max_stamina
	copy.current_morale = copy.max_morale
	copy.wound_months = 0
	for meta in copy.get_meta_list():
		copy.remove_meta(meta)
	return save_character(copy)

static func _pick(source: Array, count: int) -> Array:
	var copy := source.duplicate()
	copy.shuffle()
	return copy.slice(0, mini(count, copy.size()))

# Genera un rival para un duelo de campaña, de rol y fuerza parecidos a los del jugador.
# Se usa solo si no queda nadie de la población del mundo para retar.
static func make_rival(player: Character, portrait_path: String = "", gender: int = -1) -> Character:
	if gender < 0:
		gender = [CharacterEnums.Gender.MASCULINO, CharacterEnums.Gender.FEMENINO].pick_random()
	var c := make_random_character(player.role, gender, portrait_path)
	c.combat = clampi(player.combat + randi_range(-RIVAL_STAT_SPREAD, RIVAL_STAT_SPREAD), 1, 20)
	c.defense = clampi(player.defense + randi_range(-RIVAL_STAT_SPREAD, RIVAL_STAT_SPREAD), 1, 20)
	c.honor = randi_range(35, 65)
	return c

static func make_test_character(char_name: String, role: int) -> Character:
	var c := Character.new()
	c.first_name = char_name
	c.role = role
	c.combat = 7
	c.defense = 5
	return c
