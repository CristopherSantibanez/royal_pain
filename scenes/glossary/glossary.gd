extends Control
# Glosario: categorías a la izquierda, entradas a la derecha y búsqueda en todo el glosario.

const GlossaryData = preload("res://scripts/resources/glossary_data.gd")

@onready var categories_box: VBoxContainer = %CategoriesBox
@onready var entries_box: VBoxContainer = %EntriesBox
@onready var category_title: Label = %CategoryTitle
@onready var search_edit: LineEdit = %SearchEdit
@onready var btn_back: Button = %BtnBack
@onready var entries_scroll: ScrollContainer = %EntriesScroll

var _buttons := {}
var _current := ""

func _ready() -> void:
	var group := ButtonGroup.new()
	for category: String in GlossaryData.CATEGORIES:
		var b := Button.new()
		b.text = category
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = &"FlatButton"
		b.pressed.connect(_show_category.bind(category))
		categories_box.add_child(b)
		_buttons[category] = b
	search_edit.text_changed.connect(_on_search)
	btn_back.pressed.connect(_on_back)
	var first: String = GlossaryData.start_category if GlossaryData.start_category in GlossaryData.CATEGORIES else GlossaryData.CATEGORIES[0]
	_show_category(first)
	UiAnim.stagger_in(%RootVBox, 0.06)

func _show_category(category: String) -> void:
	_current = category
	for key in _buttons:
		_buttons[key].set_pressed_no_signal(key == category)
	search_edit.text = ""
	category_title.text = category
	_fill(GlossaryData.entries(category))

func _on_search(text: String) -> void:
	var query := text.strip_edges().to_lower()
	if query.is_empty():
		_show_category(_current)
		return
	var found: Array = []
	for category: String in GlossaryData.CATEGORIES:
		for entry in GlossaryData.entries(category):
			if query in entry[0].to_lower() or query in entry[1].to_lower():
				found.append(["%s · %s" % [entry[0], category], entry[1]])
	category_title.text = "Resultados para «%s» (%d)" % [text.strip_edges(), found.size()]
	_fill(found)

func _fill(entries: Array) -> void:
	for child in entries_box.get_children():
		child.queue_free()
	if entries.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"MutedLabel"
		empty.text = "No hay entradas."
		entries_box.add_child(empty)
	for entry in entries:
		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanel"
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		card.add_child(box)
		var title := Label.new()
		title.theme_type_variation = &"SubheaderLabel"
		title.text = entry[0]
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(title)
		var body := Label.new()
		body.text = entry[1]
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_font_size_override("font_size", 17)
		box.add_child(body)
		entries_box.add_child(card)
	entries_scroll.scroll_vertical = 0

func _on_back() -> void:
	var scene: String = GlossaryData.return_scene if not GlossaryData.return_scene.is_empty() else GlossaryData.MENU_SCENE
	GlossaryData.return_scene = ""
	GlossaryData.start_category = ""
	get_tree().change_scene_to_file(scene)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()
