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

# Los nombres al azar salen de la cultura del lugar (ver NameCatalog y MapData.culture_of_kingdom).
const NameCatalog = preload("res://scripts/resources/name_catalog.gd")
const NPC_UNIQUE_CHANCE := 0.06       # probabilidad de que un PNJ de rango alto lleve una pieza única
const NPC_UNIQUE_MIN_RANK := 2        # desde Caballero
const RIVAL_STAT_SPREAD := 2
const ContentCatalog = preload("res://scripts/resources/content_catalog.gd")

# Calidad de los PNJ según su rango: puntos libres de estadística y número de habilidades por categoría.
const NPC_FREE_POINTS := {
	Character.Role.CAMPESINO: 4, Character.Role.SOLDADO: 8, Character.Role.CABALLERO: 10,
	Character.Role.NOBLEZA_BAJA: 12, Character.Role.NOBLEZA_ALTA: 14, Character.Role.REGENTE: 15,
	Character.Role.DUQUE: 15, Character.Role.MERCENARIO: 8, Character.Role.CAPITAN: 10, Character.Role.CONDOTIERO: 12, Character.Role.INAFILIADO: 6,
}
const NPC_SKILLS := {   # [generales, combate, batalla]
	Character.Role.CAMPESINO: [1, 0, 0], Character.Role.SOLDADO: [0, 1, 1], Character.Role.CABALLERO: [1, 1, 1],
	Character.Role.NOBLEZA_BAJA: [1, 1, 2], Character.Role.NOBLEZA_ALTA: [2, 2, 2], Character.Role.REGENTE: [2, 2, 3],
	Character.Role.DUQUE: [2, 2, 3], Character.Role.MERCENARIO: [0, 1, 1], Character.Role.CAPITAN: [0, 1, 2], Character.Role.CONDOTIERO: [1, 2, 2], Character.Role.INAFILIADO: [1, 0, 0],
}

# Oro inicial aproximado según el rango (solo ambientación de los PNJ).
const GOLD_BY_ROLE := {
	Character.Role.CAMPESINO: 30, Character.Role.SOLDADO: 80, Character.Role.CABALLERO: 200,
	Character.Role.NOBLEZA_BAJA: 500, Character.Role.NOBLEZA_ALTA: 1500, Character.Role.REGENTE: 3000,
	Character.Role.DUQUE: 2200, Character.Role.MERCENARIO: 60, Character.Role.CAPITAN: 250, Character.Role.CONDOTIERO: 700, Character.Role.INAFILIADO: 30,
}

## Nombre de pila al azar de una cultura (-1 = la del lugar donde está el jugador).
static func random_first_name(gender: int, culture: int = -1) -> String:
	return NameCatalog.first_name(_resolve_culture(culture), gender)

## Apellido al azar: casa noble desde Caballero, apellido llano por debajo.
static func random_last_name(culture: int = -1, gender: int = CharacterEnums.Gender.MASCULINO,
		rank: int = NameCatalog.NOBLE_RANK) -> String:
	return NameCatalog.surname(_resolve_culture(culture), gender, rank)

## Cultura del lugar donde está el jugador (o una al azar si no hay partida).
static func current_culture() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return -1
	var map_data := tree.root.get_node_or_null("MapData")
	var travel := tree.root.get_node_or_null("TravelData")
	var gm := tree.root.get_node_or_null("GameManager")
	if map_data == null or gm == null or not gm.is_game_active:
		return -1
	if travel != null:
		return map_data.culture_of_castle(travel.current_castle())
	return map_data.culture_of_kingdom(gm.player_kingdom)

## Cultura de un reino (para la gente que vive en él).
static func culture_of_kingdom(kingdom: int) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var map_data := tree.root.get_node_or_null("MapData") if tree != null else null
	return map_data.culture_of_kingdom(kingdom) if map_data != null else -1

static func _resolve_culture(culture: int) -> int:
	return NameCatalog.valid(culture if culture >= 0 else current_culture())

# Personaje completo con todos sus parámetros al azar, siguiendo las mismas reglas que la creación
# (stats base por personalidad/alineación/tipo, 3 ventajas, 2 desventajas), pero con calidad según
# su rango: más puntos libres, más habilidades y mejor equipo cuanto más alto está.
# Nunca recibe el retrato del jugador: si no se le pasa uno, se elige otro de la galería.
static func make_random_character(role: int, gender: int, portrait_path: String = "",
		first_name: String = "", last_name: String = "", culture: int = -1) -> Character:
	var c := Character.new()
	c.gender = gender
	culture = _resolve_culture(culture)
	c.first_name = first_name if first_name != "" else random_first_name(gender, culture)
	c.last_name = last_name if (last_name != "" or first_name != "") else random_last_name(culture, gender, Character.rank_of(role))
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
	c.age = random_age_for_role(role)
	if portrait_path == "":
		portrait_path = _free_portrait(gender)
	if portrait_path != "":
		c.portrait = load(portrait_path)
	return c

# --- Edades y descendencia ---

# Edad de los PNJ según su rango: [mínima, máxima].
const AGE_BY_ROLE := {
	Character.Role.CAMPESINO: [16, 50], Character.Role.SOLDADO: [17, 45], Character.Role.CABALLERO: [19, 45],
	Character.Role.NOBLEZA_BAJA: [22, 50], Character.Role.NOBLEZA_ALTA: [30, 60], Character.Role.REGENTE: [32, 62],
	Character.Role.DUQUE: [32, 62], Character.Role.MERCENARIO: [18, 45], Character.Role.CAPITAN: [24, 50], Character.Role.CONDOTIERO: [28, 55], Character.Role.INAFILIADO: [16, 40],
}
const CHILD_STAT_SPREAD := 2
const CHILD_INHERITED_ADVANTAGES := [1, 2]

static func random_age_for_role(role: int) -> int:
	var r: Array = AGE_BY_ROLE.get(role, [18, 45])
	return randi_range(r[0], r[1])

## Hijo de dos personajes: hereda la personalidad de uno de ellos (o una propia), 1–2 ventajas de los
## padres y atributos cercanos a la media de ambos. Nace sin retrato (se le asigna al hacerse adulto).
static func make_child(parent_a: Character, parent_b: Character, family_name: String) -> Character:
	var c := Character.new()
	c.gender = [CharacterEnums.Gender.MASCULINO, CharacterEnums.Gender.FEMENINO].pick_random()
	var tree := Engine.get_main_loop() as SceneTree
	var gm := tree.root.get_node_or_null("GameManager") if tree != null else null
	c.first_name = random_first_name(c.gender, culture_of_kingdom(gm.player_kingdom) if gm != null else -1)
	c.last_name = family_name
	c.age = 0
	c.role = parent_a.role
	var parents: Array[Character] = [parent_a]
	if parent_b != null:
		parents.append(parent_b)
	c.personality = parents.pick_random().personality if randf() < 0.5 else Character.Personality.values().pick_random()
	c.alignment = CharacterEnums.Alignment.values().pick_random()
	c.fighter_type = parents.pick_random().fighter_type
	for stat in ["leadership", "charisma", "strategy", "combat", "defense"]:
		var total := 0
		for p: Character in parents:
			total += int(p.get(stat))
		c.set(stat, clampi(roundi(float(total) / parents.size()) + randi_range(-CHILD_STAT_SPREAD, CHILD_STAT_SPREAD), 1, 20))
	var inherited: Array = []
	for p: Character in parents:
		for t: CharacterTrait in p.advantages:
			if not inherited.any(func(x: CharacterTrait) -> bool: return x.trait_name == t.trait_name):
				inherited.append(t)
	inherited.shuffle()
	c.advantages.assign(inherited.slice(0, randi_range(CHILD_INHERITED_ADVANTAGES[0], CHILD_INHERITED_ADVANTAGES[1])))
	c.disadvantages.assign(_pick(GameData.disadvantages, 2))
	c.general_skills.assign(_pick(GameData.general_skills, 1))
	c.honor = 50
	c.gold = 0
	return c

## El hijo cumple la mayoría de edad: recibe retrato propio (nunca el del jugador) y equipo de su rango.
static func grow_up(child: Character, portrait_path: String) -> void:
	if portrait_path == "":
		portrait_path = _free_portrait(child.gender)
	if portrait_path != "":
		child.portrait = load(portrait_path)
	child.equipment.assign(_pick_equipment(child.role))
	for e: Equipment in child.equipment:
		child.combat = clampi(child.combat + e.combat_mod, 1, 20)
		child.defense = clampi(child.defense + e.defense_mod, 1, 20)
	child.max_health = maxi(40, 100 + roundi(SkillEffects.fx(child, "max_health")))
	child.current_health = child.max_health

# Equipo del PNJ: una pieza por ranura, del nivel que corresponde a su rango.
static func _pick_equipment(role: int) -> Array:
	# La tabla va por rango (0 Campesino … 5 Regente); el Duque usa la fila más alta.
	var rules: Dictionary = ContentCatalog.NPC_EQUIPMENT_BY_ROLE.get(mini(Character.rank_of(role), 5), {"tiers": [1], "pieces": [0, 1]})
	var pieces := randi_range(rules.pieces[0], rules.pieces[1])
	var pool: Array = GameData.equipment_catalog.filter(func(e: Equipment): return e.tier in rules.tiers)
	pool.shuffle()
	var chosen: Array = []
	var used_slots := {}
	# Muy de vez en cuando un PNJ de alto rango lleva una pieza única (se le puede ganar en duelo).
	if Character.rank_of(role) >= NPC_UNIQUE_MIN_RANK and randf() < NPC_UNIQUE_CHANCE and pieces > 0:
		var uniques: Array = GameData.equipment_catalog.filter(func(e: Equipment): return e.tier == ContentCatalog.UNIQUE_TIER)
		if not uniques.is_empty():
			var u: Equipment = uniques.pick_random()
			used_slots[u.slot] = true
			chosen.append(u)
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
