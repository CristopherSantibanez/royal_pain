extends Control
# Ventana de encargos activos (MissionData): plazo, progreso, recompensa y la acción que los cumple.
# Uso: const MissionsPanel = preload("res://scripts/ui/missions_panel.gd"); MissionsPanel.open(nodo)

const MAP_SCENE := "res://scenes/map/map.tscn"

var _list: VBoxContainer
var _feedback: Label

static func open(host: Node) -> Control:
	var panel: Control = load("res://scripts/ui/missions_panel.gd").new()
	host.add_child(panel)
	return panel

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(660, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Encargos"
	title.theme_type_variation = &"HeaderLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var stats := Label.new()
	stats.theme_type_variation = &"MutedLabel"
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.text = "Cumplidos: %d · Fallidos: %d · Activos: %d de %d" % [
		MissionData.completed_count, MissionData.failed_count, MissionData.active.size(), MissionData.MAX_ACTIVE]
	box.add_child(stats)
	# Historias encadenadas (StoryData): la que está en marcha, o la última terminada.
	var story := get_node_or_null("/root/StoryData")
	var story_line: String = story.summary_line() if story != null else ""
	if not story_line.is_empty():
		var story_label := Label.new()
		story_label.text = "📜 " + story_line
		story_label.theme_type_variation = &"BodyBoldLabel"
		story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		story_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		story_label.tooltip_text = story_line
		box.add_child(story_label)
	box.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	_feedback = Label.new()
	_feedback.theme_type_variation = &"BodyBoldLabel"
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.visible = false
	box.add_child(_feedback)

	var close := Button.new()
	close.text = "Cerrar"
	close.theme_type_variation = &"PrimaryButton"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(180, 0)
	close.pressed.connect(queue_free)
	box.add_child(close)

	MissionData.missions_changed.connect(_rebuild)
	_rebuild()
	UiAnim.fade_in(panel, 0.15)

func _rebuild() -> void:
	if not is_instance_valid(_list):
		return
	for child in _list.get_children():
		child.queue_free()
	if MissionData.active.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"MutedLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.text = "No tienes encargos. Tu señor te los ofrecerá a comienzos de mes: cuanta más fama tengas, más a menudo."
		_list.add_child(empty)
	for m: Dictionary in MissionData.active:
		_list.add_child(_row(m))

func _row(m: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var head := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.theme_type_variation = &"SubheaderLabel"
	name_lbl.text = m.title
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_lbl)
	var left := MissionData.months_left(m)
	var deadline := Label.new()
	deadline.text = "Plazo: %s" % ("este mes" if left == 0 else "%d %s" % [left, "mes" if left == 1 else "meses"])
	deadline.add_theme_color_override("font_color", Color("e07a5f") if left <= 1 else Color("efe3c8"))
	head.add_child(deadline)
	box.add_child(head)

	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 16)
	desc.text = "%s\nEncarga: %s · Recompensa: %s" % [MissionData.describe_text(m), m.get("giver", "?"), MissionData.reward_text(m)]
	box.add_child(desc)
	var progress := MissionData.progress_text(m)
	if not progress.is_empty():
		var p := Label.new()
		p.theme_type_variation = &"MutedLabel"
		p.text = progress
		box.add_child(p)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	var label := MissionData.action_label(m)
	if not label.is_empty():
		var act := Button.new()
		act.text = label
		var blocker := MissionData.action_blocker(m)
		act.disabled = not blocker.is_empty()
		act.tooltip_text = blocker
		act.pressed.connect(_on_act.bind(m.uid, m.type))
		buttons.add_child(act)
	var quit := Button.new()
	quit.text = "Renunciar"
	quit.theme_type_variation = &"FlatButton"
	quit.tooltip_text = "Renunciar cuenta como fallo: se aplica la penalización."
	quit.pressed.connect(func():
		MissionData.abandon(m.uid)
		_show("Renuncias a «%s»." % m.title))
	buttons.add_child(quit)
	box.add_child(buttons)
	return card

func _on_act(uid: String, type: String) -> void:
	if type == "fight":
		var fight_scene := MissionData.start_fight(uid)
		if not fight_scene.is_empty():
			get_tree().change_scene_to_file(fight_scene)
		return
	if type == "exhibition":
		var rival := MissionData.start_exhibition(uid)
		if rival != null:
			var player: Character = GameManager.player_character
			CombatSetup.start_campaign_duel(player, rival)
			var scene := get_tree().current_scene
			CombatSetup.return_scene = scene.scene_file_path if scene != null and not scene.scene_file_path.is_empty() else MAP_SCENE
			get_tree().change_scene_to_file("res://scenes/combat/combat.tscn")
		return
	_show(MissionData.act(uid))

func _show(text: String) -> void:
	_feedback.text = text
	_feedback.visible = not text.is_empty()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
