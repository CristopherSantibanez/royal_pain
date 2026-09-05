extends Control

@onready var summary_portrait: TextureRect = %SummaryPortrait
@onready var details_label: Label = %DetailsLabel
@onready var btn_volver_editar: Button = %BtnVolverEditar
@onready var btn_guardar: Button = %BtnGuardar

var character: Character

func _ready() -> void:
	character = CreationState.pending_character
	if character == null:
		# Nadie llegó aquí desde la creación normal; evita un crash.
		get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
		return

	summary_portrait.texture = character.get_portrait()
	summary_portrait.custom_minimum_size = Vector2(220, 330)
	summary_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	details_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	details_label.text = _build_summary_text()

	btn_volver_editar.pressed.connect(_on_volver_editar_pressed)
	btn_guardar.pressed.connect(_on_guardar_pressed)

func _build_summary_text() -> String:
	var lines: Array[String] = []
	lines.append("%s" % character.full_name())
	lines.append("Personalidad: %s | Alineación: %s | Tipo: %s" % [
		Character.Personality.keys()[character.personality],
		CharacterEnums.alignment_name(character.alignment),
		CharacterEnums.fighter_type_name(character.fighter_type),
	])
	lines.append("")
	lines.append("Liderazgo: %d   Carisma: %d   Estrategia: %d   Combate: %d   Defensa: %d" % [
		character.leadership, character.charisma, character.strategy, character.combat, character.defense
	])
	lines.append("")

	lines.append("Ventajas: %s" % _names_or_none(character.advantages, "trait_name"))
	lines.append("Desventajas: %s" % _names_or_none(character.disadvantages, "trait_name"))
	lines.append("")
	lines.append("Habilidades Generales: %s" % _names_or_none(character.general_skills, "skill_name"))
	lines.append("Habilidades de Combate: %s" % _names_or_none(character.combat_skills, "skill_name"))
	lines.append("Habilidades de Batalla: %s" % _names_or_none(character.battle_skills, "skill_name"))
	lines.append("")
	lines.append("Equipamiento: %s" % _names_or_none(character.equipment, "equipment_name"))
	lines.append("")

	if not character.biography.strip_edges().is_empty():
		lines.append("Biografía:")
		lines.append(character.biography)

	return "\n".join(lines)

func _names_or_none(arr: Array, prop: String) -> String:
	if arr.is_empty():
		return "Ninguna"
	var names: Array[String] = []
	for item in arr:
		names.append(item.get(prop))
	return ", ".join(names)

func _on_volver_editar_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_creation/character_creation.tscn")

func _on_guardar_pressed() -> void:
	var dir := DirAccess.open("user://")
	if not dir.dir_exists("characters"):
		dir.make_dir("characters")

	var safe_name := character.full_name().strip_edges().to_lower().replace(" ", "_")
	if safe_name.is_empty():
		safe_name = "personaje_sin_nombre"

	var save_path := "user://characters/%s.tres" % safe_name
	var result := ResourceSaver.save(character, save_path)

	if result == OK:
		btn_guardar.text = "¡Guardado!"
		btn_guardar.disabled = true
	else:
		btn_guardar.text = "Error al guardar (código %d)" % result
