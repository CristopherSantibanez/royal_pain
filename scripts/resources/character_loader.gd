class_name CharacterLoader

static func get_saved_character_paths() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open("user://characters")
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			result.append("user://characters/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	result.sort()
	return result

static func load_character(path: String) -> Character:
	var res = ResourceLoader.load(path)
	if res is Character:
		return res
	return null

const MALE_NAMES := ["Godofredo", "Bertrand", "Rodrigo", "Aldric", "Tristán", "Leopoldo", "Hugo", "Gonzalo", "Wulfric", "Anselmo",
	"Álvaro", "Beltrán", "Diego", "Fadrique", "Guillén", "Íñigo", "Lope", "Martín", "Nuño", "Ordoño", "Pelayo", "Sancho", "Tello", "Vela"]
const FEMALE_NAMES := ["Matilde", "Urraca", "Leonor", "Isolda", "Brunilda", "Jimena", "Adela", "Sancha", "Eloísa", "Gisela",
	"Aldonza", "Beatriz", "Catalina", "Dulce", "Estefanía", "Fronilde", "Guiomar", "Inés", "Juana", "María", "Oria", "Teresa", "Toda", "Violante"]
const LAST_NAMES := ["de Valcerro", "Piedrahíta", "del Roble", "Mantonegro", "de Altamira", "Hierrofuerte", "de la Torre", "Lanzagris",
	"Vadoscuro", "de Montealto", "Escudoviejo", "de Peñaluna", "Robledal", "de Fuentefría", "Aceroduro", "de Torrealba",
	"Valdecuervo", "de la Ribera", "Lobonegro", "de Castroverde"]
const RIVAL_STAT_SPREAD := 2

# Oro inicial aproximado según el rango (solo ambientación de los PNJ).
const GOLD_BY_ROLE := {
	Character.Role.CAMPESINO: 30, Character.Role.SOLDADO: 80, Character.Role.CABALLERO: 200,
	Character.Role.NOBLEZA_BAJA: 500, Character.Role.NOBLEZA_ALTA: 1500, Character.Role.REGENTE: 3000,
}

static func random_first_name(gender: int) -> String:
	return (FEMALE_NAMES if gender == CharacterEnums.Gender.FEMENINO else MALE_NAMES).pick_random()

static func random_last_name() -> String:
	return LAST_NAMES.pick_random()

# Personaje completo con todos sus parámetros al azar, siguiendo las mismas reglas que la creación:
# stats base por personalidad/alineación/tipo + 10 puntos libres, 3 ventajas, 2 desventajas,
# una habilidad por categoría y hasta 2 piezas de equipo.
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
	var points := GameData.FREE_POINTS
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
	c.general_skills.assign(_pick(GameData.general_skills, 1))
	c.combat_skills.assign(_pick(GameData.combat_skills, 1))
	c.battle_skills.assign(_pick(GameData.battle_skills, 1))
	c.equipment.assign(_pick(GameData.equipment_catalog, randi_range(0, 2)))
	c.apply_trait_and_equipment_modifiers()

	c.honor = randi_range(40, 70)
	c.gold = GOLD_BY_ROLE.get(role, 100)
	if portrait_path != "":
		c.portrait = load(portrait_path)
	return c

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
