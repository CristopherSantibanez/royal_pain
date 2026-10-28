extends Control
# Crónica completa de la partida: todas las noticias y tus decisiones, de la más reciente a la más antigua.
# Uso: const ChroniclePanel = preload("res://scripts/ui/chronicle_panel.gd"); ChroniclePanel.open(nodo, castillos_visibles)

const FILTERS := ["Todo", "Noticias del reino", "Tus decisiones"]
const MONTHS := ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
	"Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]

var visible_castle_ids: Array[String] = []
var _list: VBoxContainer
var _filter: OptionButton

static func open(host: Node, visible_ids: Array[String]) -> Control:
	var panel: Control = load("res://scripts/ui/chronicle_panel.gd").new()
	panel.visible_castle_ids = visible_ids
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
	panel.custom_minimum_size = Vector2(760, 520)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Crónica del reino"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_filter = OptionButton.new()
	for f in FILTERS:
		_filter.add_item(f)
	_filter.item_selected.connect(func(_i): _rebuild())
	header.add_child(_filter)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	var close := Button.new()
	close.text = "Cerrar"
	close.theme_type_variation = &"PrimaryButton"
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(queue_free)
	root.add_child(close)
	_rebuild()
	UiAnim.fade_in(panel, 0.15)
	_filter.grab_focus.call_deferred()

func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	var shown := 0
	var last_date := ""
	var entries: Array = WorldEvents.chronicle.duplicate()
	entries.reverse()
	for e: Dictionary in entries:
		var personal: bool = e.get("personal", false)
		if _filter.selected == 1 and personal or _filter.selected == 2 and not personal:
			continue
		# Lo que pasa en castillos que no ves no llega a tus oídos.
		var castle_id: String = e.get("castle_id", "")
		if not castle_id.is_empty() and not visible_castle_ids.is_empty() and not castle_id in visible_castle_ids:
			continue
		var date := "%s, año %d" % [MONTHS[clampi(int(e.m), 1, 12) - 1], int(e.y)]
		if date != last_date:
			var date_label := Label.new()
			date_label.theme_type_variation = &"SubheaderLabel"
			date_label.text = date
			_list.add_child(date_label)
			last_date = date
		var line := Label.new()
		line.text = ("✦ " if personal else "• ") + str(e.text)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", 16)
		if personal:
			line.add_theme_color_override("font_color", Color("f0d48a"))
		_list.add_child(line)
		shown += 1
	if shown == 0:
		var empty := Label.new()
		empty.theme_type_variation = &"MutedLabel"
		empty.text = "Aún no hay nada que contar."
		_list.add_child(empty)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
