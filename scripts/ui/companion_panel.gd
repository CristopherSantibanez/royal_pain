extends Control
# Ficha de gestión de tu cónyuge o de un miembro del séquito: ocupación del mes, campeón designado,
# duelo de práctica y su equipo (intercambio de piezas por ranura contigo). Se abre encima de cualquier pantalla:
#   const CompanionPanel = preload("res://scripts/ui/companion_panel.gd")
#   CompanionPanel.open(self, relacion)

signal finished(text: String)   # al cerrar; text = último resultado ("" si nada)

const OccupationRules = preload("res://scripts/resources/occupation_rules.gd")
const ContentCatalog = preload("res://scripts/resources/content_catalog.gd")
const UNIQUE_COLOR := Color("f0c060")
const COMBAT_SCENE := "res://scenes/combat/combat.tscn"
const FACE_SIZE := 96

var relation: Relationship
var return_scene := "res://scenes/relations/relations.tscn"
var _body: VBoxContainer
var _feedback: Label
var _last_text := ""

static func open(host: Node, r: Relationship) -> Control:
	var panel: Control = load("res://scripts/ui/companion_panel.gd").new()
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
	panel.custom_minimum_size = Vector2(880, 520)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 440)
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)
	_feedback = _label(bottom, "", "MutedLabel")
	_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "Cerrar"
	close.theme_type_variation = &"PrimaryButton"
	close.pressed.connect(_close)
	bottom.add_child(close)
	_rebuild()
	UiAnim.fade_in(panel, 0.15)

func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	var c := relation.character
	var player: Character = GameManager.player_character

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_body.add_child(head)
	head.add_child(FaceIcon.make(c, FACE_SIZE, Color("d4af5a") if RelationsData.is_designated_champion(c) else FaceIcon.FRAME_COLOR))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	_label(info, c.full_name(), "HeaderLabel")
	_label(info, "%s · %s · Nivel %d (%d/%d exp.) · %s" % [c.role_title(), RelationsData.intimacy_label(relation), c.level, c.xp, c.xp_to_next(), c.health_text()], "MutedLabel")
	_label(info, "Combate %d · Defensa %d · Liderazgo %d · Carisma %d · Estrategia %d" % [c.combat, c.defense, c.leadership, c.charisma, c.strategy], "BodyBoldLabel")

	# Ocupación del mes.
	_label(_body, "Ocupación este mes", "SubheaderLabel")
	var current := RelationsData.occupation_of(relation)
	var occ_row := HFlowContainer.new()
	occ_row.add_theme_constant_override("h_separation", 8)
	_body.add_child(occ_row)
	var first_btn: Button = null
	for id: String in OccupationRules.ALL:
		var btn := Button.new()
		btn.text = ("● " if id == current else "") + OccupationRules.name_of(id)
		btn.theme_type_variation = &"PrimaryButton" if id == current else &""
		btn.tooltip_text = "%s\n%s" % [OccupationRules.DESCRIPTIONS[id], OccupationRules.preview(c, id)]
		btn.pressed.connect(func(): _act(RelationsData.set_occupation(relation, id)))
		occ_row.add_child(btn)
		if first_btn == null:
			first_btn = btn
	var occ_note := _label(_body, "%s — %s" % [OccupationRules.DESCRIPTIONS[current], OccupationRules.preview(c, current)], "MutedLabel")
	if c.is_wounded() and current != OccupationRules.DESCANSAR:
		occ_note.text += "  (herido: descansa)"
	_label(_body, "Soldada: %d oro/mes" % RelationsData.RETINUE_UPKEEP if relation.person_name in RelationsData.retinue else "Sin soldada", "MutedLabel")

	# Campeón y práctica.
	_body.add_child(HSeparator.new())
	var duel_row := HFlowContainer.new()
	duel_row.add_theme_constant_override("h_separation", 8)
	_body.add_child(duel_row)
	if relation.person_name in RelationsData.retinue:
		var is_champ := RelationsData.is_designated_champion(c)
		var champ := _button(duel_row, "Retirar como campeón" if is_champ else "Designar campeón",
			"" if is_champ else RelationsData.can_designate_champion(relation),
			func(): _act(RelationsData.toggle_champion(relation)))
		champ.tooltip_text = champ.tooltip_text if champ.disabled else "Tu campeón se ofrece primero para batirse por ti cuando cabe un campeón (retos, juicios, duelos de evento). Lo controlas tú en el duelo."
	_button(duel_row, "Duelo de práctica (1 acción)", RelationsData.can_practice(relation), _practice).tooltip_text = \
		RelationsData.can_practice(relation) if not RelationsData.can_practice(relation).is_empty() else \
		"Sin heridas ni honor en juego: los dos ganáis experiencia y algo de confianza. Una vez al mes."

	# Equipo: intercambio por ranuras.
	_body.add_child(HSeparator.new())
	_label(_body, "Equipo (máximo %d piezas cada uno)" % Character.MAX_EQUIPMENT, "SubheaderLabel")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	_body.add_child(grid)
	for h in ["Ranura", c.first_name, "Tú", ""]:
		_cell(grid, h, "BodyBoldLabel")
	for slot: String in ContentCatalog.SLOTS:
		var theirs := _item(c, slot)
		var mine := _item(player, slot)
		_cell(grid, slot, "MutedLabel")
		_item_label(grid, theirs)
		_item_label(grid, mine)
		var text := "Intercambiar" if theirs != null and mine != null else ("Dárselo" if mine != null else ("Tomarlo" if theirs != null else "—"))
		var reason := RelationsData.can_swap_equipment(relation, slot)
		var btn := Button.new()
		btn.text = text
		btn.disabled = not reason.is_empty()
		btn.tooltip_text = reason if btn.disabled else "No gasta acciones."
		btn.pressed.connect(func(): _act(RelationsData.swap_equipment(relation, slot)))
		grid.add_child(btn)
	if first_btn != null:
		first_btn.grab_focus.call_deferred()

func _item(c: Character, slot: String) -> Equipment:
	for e: Equipment in c.equipment:
		if e.slot == slot:
			return e
	return null

func _item_label(parent: Node, e: Equipment) -> void:
	if e == null:
		_cell(parent, "—", "MutedLabel")
		return
	var unique := SkillEffects.is_unique_item(e)
	var lbl := _cell(parent, ("★★★★ " if unique else "★".repeat(clampi(e.tier, 1, 3)) + " ") + e.equipment_name, "")
	lbl.tooltip_text = e.description
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	if unique:
		lbl.add_theme_color_override("font_color", UNIQUE_COLOR)

func _practice() -> void:
	var reason := RelationsData.start_practice(relation)
	if not reason.is_empty():
		_act(reason)
		return
	CombatSetup.start_campaign_duel(GameManager.player_character, relation.character)
	CombatSetup.return_scene = return_scene
	CombatSetup.last_result_text = ""
	RelationsData.requested_tab = "sequito"
	get_tree().change_scene_to_file(COMBAT_SCENE)

func _act(text: String) -> void:
	_last_text = text
	_feedback.text = text
	_rebuild()

func _close() -> void:
	finished.emit(_last_text)
	queue_free()

func _button(parent: Node, text: String, reason: String, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.disabled = not reason.is_empty()
	btn.tooltip_text = reason
	btn.pressed.connect(on_press)
	parent.add_child(btn)
	return btn

# Celda de la tabla de equipo: sin ajuste de línea (en una rejilla se encogería a nada).
func _cell(parent: Node, text: String, variation: String) -> Label:
	var l := _label(parent, text, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

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
		_close()
