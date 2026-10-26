extends Control
# Ficha de un personaje conocido: retrato, carácter, atributos, habilidades, rasgos, equipo
# y lo que os une. Se abre encima de cualquier pantalla:
#   const CharacterProfile = preload("res://scripts/ui/character_profile.gd")
#   CharacterProfile.open(self, relacion)

const PORTRAIT_SIZE := Vector2(180, 260)

var relation: Relationship

static func open(host: Node, r: Relationship) -> Control:
	var panel: Control = load("res://scripts/ui/character_profile.gd").new()
	panel.relation = r
	host.add_child(panel)
	return panel

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 500)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var c := relation.character
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# Columna izquierda: retrato y lo esencial.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(PORTRAIT_SIZE.x, 0)
	body.add_child(left)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = PORTRAIT_SIZE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = c.get_portrait()
	left.add_child(portrait)
	_label(left, "%s\n%s" % [c.role_name(), KingdomEnums.kingdom_name(relation.kingdom) if relation.kingdom >= 0 else "Sin reino"], "MutedLabel").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Columna derecha: datos en pestañas cortas.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	_label(right, c.full_name(), "HeaderLabel")
	_label(right, "%s — %s" % [DialogueCatalog.personality_name(c.personality), RelationsData.catalog("personality_description", [c.personality], "")], "")
	_label(right, "Alineamiento: %s · Estilo: %s" % [
		_enum_name(CharacterEnums.Alignment, c.alignment), _enum_name(CharacterEnums.FighterType, c.fighter_type)], "MutedLabel")
	_label(right, "Combate %d · Defensa %d · Liderazgo %d · Carisma %d · Estrategia %d · Vida %d/%d · Honor %d · Fama %d" % [
		c.combat, c.defense, c.leadership, c.charisma, c.strategy, c.current_health, c.max_health, c.honor, c.fame], "BodyBoldLabel")
	right.add_child(HSeparator.new())
	_label(right, _relation_text(), "")
	right.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(details)
	_section(details, "Habilidades", _names(c.general_skills + c.combat_skills + c.battle_skills, "skill_name"))
	_section(details, "Ventajas", _names(c.advantages, "trait_name"))
	_section(details, "Desventajas", _names(c.disadvantages, "trait_name"))
	_section(details, "Equipamiento", _names(c.equipment, "equipment_name"))
	if not c.biography.is_empty():
		_section(details, "Historia", c.biography)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	root.add_child(buttons)
	var feedback := _label(buttons, "", "MutedLabel")
	feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var save_btn := Button.new()
	save_btn.text = "Guardar en el editor"
	save_btn.tooltip_text = "Guarda una copia de este personaje para usarlo en Nueva Partida, el duelo de práctica o el editor."
	save_btn.pressed.connect(func():
		var has_save := (CharacterLoader as Script).get_script_method_list().any(func(m): return m.name == "save_npc")
		var loader: Script = CharacterLoader
		var path: String = loader.callv("save_npc", [c]) if has_save else ""
		feedback.text = "Guardado en el editor de personajes." if not path.is_empty() else "No se pudo guardar.")
	buttons.add_child(save_btn)
	var close := Button.new()
	close.text = "Cerrar"
	close.theme_type_variation = &"PrimaryButton"
	close.pressed.connect(queue_free)
	buttons.add_child(close)
	UiAnim.fade_in(panel, 0.15)
	close.grab_focus.call_deferred()

func _relation_text() -> String:
	var r := relation
	var parts: Array[String] = []
	if r.kind == Relationship.Kind.SENOR:
		parts.append("Señor de su casa · Afinidad %+d (%s)" % [r.affinity, r.status_text()])
	else:
		parts.append("Intimidad %d — %s" % [r.affection, RelationsData.intimacy_label(r)])
	if r.kind == Relationship.Kind.RIVAL_DUELO or r.duels_won_against + r.duels_lost_against > 0:
		parts.append("Duelos: le ganaste %d, te ganó %d · %s (rencor %d)" % [r.duels_won_against, r.duels_lost_against, r.rivalry_text(), r.grudge])
	if r.romance and not r.romance_text().is_empty():
		parts.append("♥ " + r.romance_text())
	if r.person_name in RelationsData.retinue:
		parts.append("Forma parte de tu séquito.")
	return "\n".join(parts)

func _section(parent: Node, title: String, text: String) -> void:
	_label(parent, title, "SubheaderLabel")
	var body := _label(parent, text if not text.is_empty() else "—", "")
	body.add_theme_font_size_override("font_size", 16)

func _names(items: Array, field: String) -> String:
	var names: Array[String] = []
	for item in items:
		if item != null:
			names.append(str(item.get(field)))
	return ", ".join(names)

func _enum_name(enum_dict: Dictionary, value: int) -> String:
	for key in enum_dict:
		if enum_dict[key] == value:
			return str(key).capitalize()
	return "?"

func _label(parent: Node, text: String, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not variation.is_empty():
		l.theme_type_variation = variation
	parent.add_child(l)
	return l

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
