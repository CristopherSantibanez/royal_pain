extends Control
# Obras del castillo: edificios construidos, la obra en curso y las que se pueden ordenar.
# Solo la nobleza (Nobleza Baja o más) ordena obras en sus castillos, pagando con el tesoro del castillo;
# los caballeros y soldados ven las del castillo de su señor y disfrutan de sus efectos.
# Uso: const WorksPanel = preload("res://scripts/ui/works_panel.gd"); WorksPanel.open(nodo, castillo)

const BuildingCatalog = preload("res://scripts/resources/building_catalog.gd")

signal construction_started

var castle: Castle
var _list: VBoxContainer
var _status: Label
var _feedback: Label
var _first_button: Button

static func open(host: Node, target: Castle) -> Control:
	var panel: Control = load("res://scripts/ui/works_panel.gd").new()
	panel.castle = target
	host.add_child(panel)
	return panel

## Motivo por el que el jugador no puede ordenar la siguiente obra de `id` ("" si puede).
static func build_block_reason(player: Character, target: Castle, id: String) -> String:
	if player == null or target == null:
		return "No hay castillo."
	if player.rank() < Character.rank_of(BuildingCatalog.MIN_ROLE_TO_BUILD):
		return "Solo la nobleza ordena obras (desde Nobleza Baja)."
	if not ArmyData.is_player_defended(target):
		return "No es tu castillo."
	var next := BuildingCatalog.level_data(id, target.building_level(id) + 1)
	if next.is_empty():
		return "Ya está al nivel máximo."
	if target.building_level(id) + 1 >= BuildingCatalog.MAX_LEVEL and player.rank() < Character.rank_of(BuildingCatalog.TOP_LEVEL_MIN_ROLE):
		return "Las grandes obras (nivel %d) solo las ordena la alta nobleza." % BuildingCatalog.MAX_LEVEL
	if target.is_building():
		return "Ya hay una obra en curso: %s." % BuildingCatalog.building_name(target.construction_id)
	if target.gold < int(next.cost):
		return "Al tesoro del castillo le faltan %d de oro." % (int(next.cost) - target.gold)
	if not GameManager.has_actions_remaining():
		return "No te quedan acciones este turno."
	return ""

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
	panel.custom_minimum_size = Vector2(900, 560)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Obras de %s" % castle.castle_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_status = Label.new()
	_status.theme_type_variation = &"StatLabel"
	header.add_child(_status)

	var note := Label.new()
	note.theme_type_variation = &"MutedLabel"
	note.text = "Una obra a la vez · 1 acción · tesoro del castillo  ⓘ"
	note.tooltip_text = "Tarda varios meses. Cada edificio tiene %d niveles. Quien vive en el castillo (también los caballeros y soldados de su señor) disfruta de sus efectos." % BuildingCatalog.MAX_LEVEL
	note.mouse_filter = Control.MOUSE_FILTER_PASS
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(note)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	_feedback = Label.new()
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_feedback)
	var close := Button.new()
	close.text = "Cerrar"
	close.theme_type_variation = &"PrimaryButton"
	close.pressed.connect(queue_free)
	bottom.add_child(close)
	_rebuild()
	UiAnim.fade_in(panel, 0.15)
	if _first_button != null:
		_first_button.grab_focus.call_deferred()
	else:
		close.grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()

func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	_first_button = null
	_status.text = "Tesoro: %d" % castle.gold
	if castle.is_building():
		_status.text += " · En obras: %s (%d %s)" % [BuildingCatalog.building_name(castle.construction_id),
			castle.construction_months_left, "mes" if castle.construction_months_left == 1 else "meses"]
	var player: Character = GameManager.player_character
	for id: String in BuildingCatalog.ORDER:
		_add_row(id, player)

func _add_row(id: String, player: Character) -> void:
	var b: Dictionary = BuildingCatalog.BUILDINGS[id]
	var level := castle.building_level(id)
	var building_now := castle.construction_id == id
	var card := PanelContainer.new()
	card.theme_type_variation = &"HighlightPanel" if building_now else &"CardPanel"
	_list.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name_label := Label.new()
	name_label.theme_type_variation = &"BodyBoldLabel"
	name_label.text = "%s  %s%s" % [b.name, "■".repeat(level), "□".repeat(BuildingCatalog.MAX_LEVEL - level)]
	if building_now:
		name_label.text += "   — en obras, faltan %d %s" % [castle.construction_months_left, "mes" if castle.construction_months_left == 1 else "meses"]
	text.add_child(name_label)
	var detail := Label.new()
	detail.theme_type_variation = &"MutedLabel"
	detail.add_theme_font_size_override("font_size", 14)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var lines: Array[String] = [b.description]
	if level > 0:
		lines.append("Ahora: " + BuildingCatalog.level_data(id, level).text)
	var next := BuildingCatalog.level_data(id, level + 1)
	if not next.is_empty():
		lines.append("Nivel %d: %s · %d de oro · %d meses" % [level + 1, next.text, next.cost, next.months])
	detail.text = "\n".join(lines)
	text.add_child(detail)
	if next.is_empty():
		return
	var reason := build_block_reason(player, castle, id)
	var btn := Button.new()
	btn.text = "Construir" if level == 0 else "Mejorar"
	btn.add_theme_font_size_override("font_size", 13)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.disabled = not reason.is_empty()
	btn.tooltip_text = reason
	btn.pressed.connect(_build.bind(id))
	row.add_child(btn)
	if _first_button == null and not btn.disabled:
		_first_button = btn

func _build(id: String) -> void:
	if not build_block_reason(GameManager.player_character, castle, id).is_empty():
		return
	if not GameManager.consume_action():
		return
	var next := BuildingCatalog.level_data(id, castle.building_level(id) + 1)
	castle.start_construction(id)
	_feedback.text = "Ordenas las obras: %s (nivel %d). Estarán listas en %d meses." % [BuildingCatalog.building_name(id), castle.building_level(id) + 1, next.months]
	WorldEvents.record("Comienzan las obras de %s en %s." % [BuildingCatalog.building_name(id), castle.castle_name], castle.castle_id)
	Sfx.play("clash", -12.0)
	construction_started.emit()
	_rebuild()
