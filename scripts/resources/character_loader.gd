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

static func make_test_character(char_name: String, role: int) -> Character:
	var c := Character.new()
	c.first_name = char_name
	c.role = role
	c.combat = 7
	c.defense = 5
	return c
