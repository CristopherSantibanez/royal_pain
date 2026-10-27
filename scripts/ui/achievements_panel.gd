extends Control
# Libro de hazañas: todas las hazañas de la partida, por categoría, con su progreso y recompensa.
# Uso: const AchievementsPanel = preload("res://scripts/ui/achievements_panel.gd"); AchievementsPanel.open(nodo)

const AchievementCatalog = preload("res://scripts/resources/achievement_catalog.gd")
const DONE_COLOR := Color("f0d48a")
const PENDING_COLOR := Color(0.75, 0.72, 0.66)

var _list: VBoxContainer
var _close: Button

static func open(host: Node) -> Control:
	var panel: Control = load("res://scripts/ui/achievements_panel.gd").new()
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
	panel.custom_minimum_size = Vector2(800, 540)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Libro de hazañas"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var count := Label.new()
	count.theme_type_variation = &"MutedLabel"
	count.text = "%d de %d cumplidas" % [AchievementData.achieved_count(), AchievementData.visible().size()]
	header.add_child(count)

	var note := Label.new()
	note.theme_type_variation = &"MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Las hazañas dan recompensas pero no terminan la partida. Solo termina al dominar el mundo, al unir los dos últimos reinos por matrimonio o si tu linaje se extingue."
	root.add_child(note)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_close = Button.new()
	_close.text = "Cerrar"
	_close.theme_type_variation = &"PrimaryButton"
	_close.size_flags_horizontal = Control.SIZE_SHRINK_END
	_close.pressed.connect(queue_free)
	root.add_child(_close)
	_build()
	UiAnim.fade_in(panel, 0.15)
	_close.grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()

func _build() -> void:
	var ctx := AchievementData.context()
	var shown := AchievementData.visible()
	for cat in AchievementCatalog.CATEGORIES:
		var entries := shown.filter(func(a: Dictionary) -> bool: return a.cat == cat)
		if entries.is_empty():
			continue
		var header := Label.new()
		header.theme_type_variation = &"SubheaderLabel"
		header.text = cat
		_list.add_child(header)
		for a: Dictionary in entries:
			_list.add_child(_row(a, AchievementData.progress_of(a, ctx)))

func _row(a: Dictionary, progress: Dictionary) -> Control:
	var done: bool = progress.done
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var mark := Label.new()
	mark.text = "✓" if done else "○"
	mark.custom_minimum_size = Vector2(22, 0)
	mark.add_theme_color_override("font_color", DONE_COLOR if done else PENDING_COLOR)
	row.add_child(mark)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 0)
	row.add_child(box)
	var name_label := Label.new()
	name_label.theme_type_variation = &"BodyBoldLabel"
	name_label.text = a.title
	name_label.add_theme_color_override("font_color", DONE_COLOR if done else Color.WHITE)
	box.add_child(name_label)
	var desc := Label.new()
	desc.theme_type_variation = &"MutedLabel"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var reward := AchievementCatalog.reward_text(a.get("reward", {}))
	desc.text = AchievementCatalog.description_of(a) + ("  ·  Recompensa: %s" % reward if not reward.is_empty() else "")
	box.add_child(desc)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(150, 0)
	row.add_child(right)
	var state := Label.new()
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.theme_type_variation = &"MutedLabel"
	state.text = "Cumplida" if done else progress.text
	right.add_child(state)
	if not done and not a.has("goal_role"):
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(150, 8)
		bar.max_value = 1.0
		bar.value = progress.ratio
		right.add_child(bar)
	return row
