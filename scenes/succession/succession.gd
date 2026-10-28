extends Control
# Sucesión: el jugador ha muerto. Si tiene hijos adultos, elige quién continúa la casa;
# si no, el linaje se extingue y la partida termina.

const MAP_SCENE := "res://scenes/map/map.tscn"
const MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"

var _box: VBoxContainer

func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	panel.add_child(_box)

	var deceased := DynastyData.deceased_name()
	var cause := DynastyData.death_cause()
	_box.add_child(_label("Ha muerto %s" % deceased if not deceased.is_empty() else "Fin de una vida", &"HeaderLabel", true))
	if not cause.is_empty():
		_box.add_child(_label("%s muere %s." % [deceased, cause], &"MutedLabel", true))
	_box.add_child(HSeparator.new())

	var heirs := DynastyData.adult_children()
	if heirs.is_empty() or not DynastyData.needs_succession():
		_show_end()
	else:
		_box.add_child(_label("¿Quién toma las riendas de la casa?", &"", true))
		for c: Character in heirs:
			_box.add_child(_heir_card(c))
	UiAnim.fade_in(panel, 0.4)
	UiAnim.focus_first(_box)

func _label(text: String, variation: StringName = &"", centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if variation != &"":
		l.theme_type_variation = variation
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _heir_card(c: Character) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	row.add_child(FaceIcon.make(c, 84))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fem := c.gender == CharacterEnums.Gender.FEMENINO
	info.add_child(_label("%s · %s, %d años" % [c.full_name(), ("hija" if fem else "hijo") if DynastyData.is_own_child(c) else ("hermana" if fem else "hermano"), c.age], &"SubheaderLabel"))
	var traits: Array[String] = []
	for t: CharacterTrait in c.advantages:
		traits.append(t.trait_name)
	var faults: Array[String] = []
	for t: CharacterTrait in c.disadvantages:
		faults.append(t.trait_name)
	var stats := "%s · Liderazgo %d · Carisma %d · Estrategia %d · Combate %d · Defensa %d" % [
		LevelUpPanel._personality(c), c.leadership, c.charisma, c.strategy, c.combat, c.defense]
	if not traits.is_empty():
		stats += "\nVentajas: " + ", ".join(traits)
	if not faults.is_empty():
		stats += "\nDefectos: " + ", ".join(faults)
	var l := _label(stats, &"MutedLabel")
	l.add_theme_font_size_override("font_size", 15)
	info.add_child(l)
	row.add_child(info)
	var pick := Button.new()
	pick.text = "Elegir"
	pick.theme_type_variation = &"PrimaryButton"
	pick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pick.custom_minimum_size = Vector2(130, 0)
	pick.tooltip_text = "%s continúa la partida." % c.full_name()
	pick.pressed.connect(_choose.bind(c))
	row.add_child(pick)
	return card

const LevelUpPanel = preload("res://scripts/ui/level_up_panel.gd")

func _choose(heir: Character) -> void:
	var text := DynastyData.succeed(heir)
	if text.is_empty():
		return
	WorldEvents.notify("Larga vida a %s" % heir.full_name(), text)
	SaveSystem.save_game()
	get_tree().change_scene_to_file(MAP_SCENE)

func _show_end() -> void:
	var reason := DynastyData.end_lineage() if DynastyData.needs_succession() else "Tu linaje se ha extinguido."
	_box.add_child(_label(reason, &"BodyBoldLabel", true))
	_box.add_child(_label("Sin hijos adultos, nadie recoge tu nombre. Tu historia termina aquí.", &"MutedLabel", true))
	var menu := Button.new()
	menu.text = "Volver al menú"
	menu.theme_type_variation = &"PrimaryButton"
	menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu.custom_minimum_size = Vector2(220, 0)
	menu.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	_box.add_child(menu)
