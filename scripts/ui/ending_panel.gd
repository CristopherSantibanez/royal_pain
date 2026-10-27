extends Control
# Pantalla de final con victoria (dominar el mundo, unificar los reinos): resumen de la partida
# y la opción de seguir jugando o volver al menú.
# Uso: const EndingPanel = preload("res://scripts/ui/ending_panel.gd"); EndingPanel.open(nodo, final)

const MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"

var ending: Dictionary = {}

static func open(host: Node, the_ending: Dictionary) -> Control:
	var panel: Control = load("res://scripts/ui/ending_panel.gd").new()
	panel.ending = the_ending
	host.add_child(panel)
	return panel

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 0)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = ending.get("title", "Fin")
	root.add_child(title)
	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(640, 0)
	text.text = ending.get("text", "")
	root.add_child(text)

	var s: Dictionary = AchievementData.summary()
	var lines: Array[String] = []
	lines.append("%s, %s de la casa %s" % [s.player, s.title, s.house])
	lines.append("Duración: %d %s y %d %s" % [s.years, "año" if s.years == 1 else "años", s.months, "mes" if s.months == 1 else "meses"])
	lines.append("Hazañas cumplidas: %d de %d" % [s.achieved, s.total])
	lines.append("Generación de la casa: %d · Hijos: %d" % [s.generation, s.children])
	var summary := Label.new()
	summary.theme_type_variation = &"MutedLabel"
	summary.text = "\n".join(lines)
	root.add_child(summary)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	root.add_child(buttons)
	var keep := Button.new()
	keep.text = "Seguir jugando"
	keep.theme_type_variation = &"PrimaryButton"
	keep.visible = ending.get("victory", false)
	keep.pressed.connect(queue_free)
	buttons.add_child(keep)
	var menu := Button.new()
	menu.text = "Volver al menú"
	menu.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	buttons.add_child(menu)
	Sfx.play("victory", 0.0, 0.0)
	UiAnim.fade_in(panel, 0.3)
	(keep if keep.visible else menu).grab_focus.call_deferred()
