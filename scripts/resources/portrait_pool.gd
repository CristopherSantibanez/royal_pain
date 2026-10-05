class_name PortraitPool
extends RefCounted
# Reparte retratos sin repetir, separados por género. Se construye excluyendo los ya usados
# (el del jugador y los de personajes generados antes), así nadie comparte cara.

var _available := {
	CharacterEnums.Gender.MASCULINO: [],
	CharacterEnums.Gender.FEMENINO: [],
}

func _init(used_paths: Array = []) -> void:
	for gender in _available.keys():
		var paths := PortraitGallery.get_portraits_for_gender(gender)
		paths.shuffle()
		for p in paths:
			if not p in used_paths:
				_available[gender].append(p)

func remaining(gender: int) -> int:
	return _available[gender].size()

# Devuelve la ruta de un retrato libre de ese género, o "" si se agotaron.
func take(gender: int) -> String:
	if _available[gender].is_empty():
		return ""
	return _available[gender].pop_back()

# Elige un género en proporción a los retratos que quedan, para no agotar uno antes de tiempo.
func pick_gender() -> int:
	var male := remaining(CharacterEnums.Gender.MASCULINO)
	var female := remaining(CharacterEnums.Gender.FEMENINO)
	if male + female == 0:
		return [CharacterEnums.Gender.MASCULINO, CharacterEnums.Gender.FEMENINO].pick_random()
	return CharacterEnums.Gender.MASCULINO if randi_range(1, male + female) <= male else CharacterEnums.Gender.FEMENINO
