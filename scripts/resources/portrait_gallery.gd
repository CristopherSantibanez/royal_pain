class_name PortraitGallery

static func get_portraits_for_gender(gender: int) -> Array[String]:
	var folder := "male" if gender == CharacterEnums.Gender.MASCULINO else "female"
	var path := "res://assets/portraits/characters/%s/" % folder
	var result: Array[String] = []

	var dir := DirAccess.open(path)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			# En un juego exportado las imágenes solo aparecen como "x.png.import": se usa la ruta
			# original, que load() resuelve igual. En el editor se exige que la imagen exista, para
			# ignorar .import huérfanos de imágenes borradas.
			var image_name := file_name.trim_suffix(".import")
			var full := path + image_name
			var exists := FileAccess.file_exists(full) if not OS.has_feature("template") else ResourceLoader.exists(full)
			if _is_image(image_name) and not full in result and exists:
				result.append(full)
		file_name = dir.get_next()
	dir.list_dir_end()

	result.sort()
	return result

static func _is_image(file_name: String) -> bool:
	var lower := file_name.to_lower()
	return lower.ends_with(".png") or lower.ends_with(".jpg") or lower.ends_with(".jpeg") or lower.ends_with(".webp")
