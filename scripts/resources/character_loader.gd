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

const RIVAL_MALE_NAMES := ["Godofredo", "Bertrand", "Rodrigo", "Aldric", "Tristán", "Leopoldo", "Hugo", "Gonzalo", "Wulfric", "Anselmo"]
const RIVAL_FEMALE_NAMES := ["Matilde", "Urraca", "Leonor", "Isolda", "Brunilda", "Jimena", "Adela", "Sancha", "Eloísa", "Gisela"]
const RIVAL_LAST_NAMES := ["de Valcerro", "Piedrahíta", "del Roble", "Mantonegro", "de Altamira", "Hierrofuerte", "de la Torre", "Lanzagris", "Vadoscuro", "de Montealto"]
const RIVAL_STAT_SPREAD := 2

# Genera un rival para un duelo de campaña, de rol y fuerza parecidos a los del jugador.
static func make_rival(player: Character) -> Character:
	var c := Character.new()
	var female := randf() < 0.5
	c.gender = CharacterEnums.Gender.FEMENINO if female else CharacterEnums.Gender.MASCULINO
	c.first_name = (RIVAL_FEMALE_NAMES if female else RIVAL_MALE_NAMES).pick_random()
	c.last_name = RIVAL_LAST_NAMES.pick_random()
	c.role = player.role
	c.personality = Character.Personality.values().pick_random()
	c.alignment = CharacterEnums.Alignment.values().pick_random()
	c.fighter_type = CharacterEnums.FighterType.values().pick_random()

	c.combat = clampi(player.combat + randi_range(-RIVAL_STAT_SPREAD, RIVAL_STAT_SPREAD), 1, 20)
	c.defense = clampi(player.defense + randi_range(-RIVAL_STAT_SPREAD, RIVAL_STAT_SPREAD), 1, 20)
	c.leadership = randi_range(3, 12)
	c.charisma = randi_range(3, 12)
	c.strategy = randi_range(3, 12)
	c.honor = randi_range(35, 65)

	var portraits := PortraitGallery.get_portraits_for_gender(c.gender)
	if not portraits.is_empty():
		c.portrait = load(portraits.pick_random())
	return c

static func make_test_character(char_name: String, role: int) -> Character:
	var c := Character.new()
	c.first_name = char_name
	c.role = role
	c.combat = 7
	c.defense = 5
	return c
