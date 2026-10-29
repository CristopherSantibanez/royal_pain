extends Control
# Mis personajes: los personajes guardados (CharacterLoader) con su retrato, rol y atributos.
# Se pueden ver, editar (en la creación de personaje), duplicar, renombrar, borrar,
# exportar a un archivo JSON e importar desde uno (DataCodec).

const CharacterProfile = preload("res://scripts/ui/character_profile.gd")
const ROW_FACE := 44
const DETAIL_FACE := 120
const LIST_WIDTH := 520
const BG_COLOR := Color(0.07, 0.05, 0.04)
const JSON_FILTER := "*.json ; Personaje (JSON)"

var _list: VBoxContainer
var _detail: VBoxContainer
var _status: Label
var _selected := ""
var _rename_box: HBoxContainer
var _first_edit: LineEdit
var _last_edit: LineEdit
var _btn_back: Button

# --- Operaciones (estáticas: también las usan las pruebas) ---

static func list_paths() -> Array[String]:
	return CharacterLoader.get_saved_character_paths()

static func stats_text(c: Character) -> String:
	return "Lid %d · Car %d · Est %d · Com %d · Def %d" % [c.leadership, c.charisma, c.strategy, c.combat, c.defense]

## Copia con nombre de archivo nuevo. Devuelve la ruta nueva o "".
static func duplicate_character(path: String) -> String:
	var c := CharacterLoader.load_character(path)
	return CharacterLoader.save_character(c) if c != null else ""

static func rename_character(path: String, first: String, last: String) -> bool:
	var c := CharacterLoader.load_character(path)
	if c == null or first.strip_edges().is_empty():
		return false
	c.first_name = first.strip_edges()
	c.last_name = last.strip_edges()
	return DataCodec.write_file(path, c) == OK

static func delete_character(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	for extra in [".bak", ".tmp"]:
		if FileAccess.file_exists(path + extra):
			DirAccess.remove_absolute(path + extra)
	return DirAccess.remove_absolute(path) == OK

static func export_character(path: String, dest: String) -> bool:
	var c := CharacterLoader.load_character(path)
	return c != null and DataCodec.write_file(dest, c) == OK

## Importa un personaje de un JSON (mismo formato que los guardados). Devuelve la ruta nueva o "".
static func import_character(src: String) -> String:
	var c := DataCodec.read_file(src) as Character
	return CharacterLoader.save_character(c) if c != null else ""

# --- Interfaz ---

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	var title := Label.new()
	title.text = "Mis personajes"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var btn_import := Button.new()
	btn_import.text = "Importar…"
	btn_import.tooltip_text = "Añade un personaje desde un archivo JSON."
	btn_import.pressed.connect(_ask_file.bind(FileDialog.FILE_MODE_OPEN_FILE))
	header.add_child(btn_import)
	_btn_back = Button.new()
	_btn_back.text = "Volver"
	_btn_back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	header.add_child(_btn_back)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	panel.add_child(_detail)

	_status = Label.new()
	_status.theme_type_variation = &"MutedLabel"
	root.add_child(_status)
	_refresh()

func _refresh(select: String = "") -> void:
	for child in _list.get_children():
		child.queue_free()
	var paths := list_paths()
	if select.is_empty() and _selected in paths:
		select = _selected
	if select.is_empty() and not paths.is_empty():
		select = paths[0]
	var first_btn: Button = null
	for path in paths:
		var c := CharacterLoader.load_character(path)
		if c == null:
			continue
		var row := Button.new()
		row.toggle_mode = true
		row.button_pressed = path == select
		row.custom_minimum_size = Vector2(0, ROW_FACE + 10)
		row.theme_type_variation = &"FlatButton"
		row.pressed.connect(_select.bind(path))
		row.set_meta("path", path)
		var hb := HBoxContainer.new()
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 6
		hb.add_theme_constant_override("separation", 10)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hb)
		var face := FaceIcon.make(c, ROW_FACE, FaceIcon.FRAME_COLOR, false)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(face)
		var label := Label.new()
		label.text = "%s · %s\n%s" % [c.full_name(), c.role_name(), stats_text(c)]
		label.add_theme_font_size_override("font_size", 14)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(label)
		_list.add_child(row)
		if first_btn == null or path == select:
			first_btn = row
	if paths.is_empty():
		var empty := Label.new()
		empty.text = "No hay personajes guardados."
		_list.add_child(empty)
	_select(select)
	(func(): (first_btn if first_btn != null else _btn_back).grab_focus()).call_deferred()

func _select(path: String) -> void:
	_selected = path
	for row in _list.get_children():
		if row is Button:
			row.set_pressed_no_signal(row.get_meta("path", "") == path)
	for child in _detail.get_children():
		child.queue_free()
	var c := CharacterLoader.load_character(path) if not path.is_empty() else null
	if c == null:
		return
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_detail.add_child(top)
	top.add_child(FaceIcon.make(c, DETAIL_FACE, FaceIcon.FRAME_COLOR, false))
	var info := Label.new()
	info.text = "%s\n%s · Nivel %d\n%s\n%s" % [c.full_name(), c.role_name(), c.level, stats_text(c), path.get_file()]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	_detail.add_child(grid)
	for pair in [["Ver ficha", _on_profile], ["Editar", _on_edit], ["Duplicar", _on_duplicate],
			["Renombrar", _on_rename], ["Exportar…", _ask_file.bind(FileDialog.FILE_MODE_SAVE_FILE)], ["Borrar", _on_delete]]:
		var b := Button.new()
		b.text = pair[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(pair[1])
		grid.add_child(b)
	_rename_box = HBoxContainer.new()
	_rename_box.visible = false
	_detail.add_child(_rename_box)
	_first_edit = LineEdit.new()
	_first_edit.placeholder_text = "Nombre"
	_first_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_last_edit = LineEdit.new()
	_last_edit.placeholder_text = "Apellido"
	_last_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ok := Button.new()
	ok.text = "Aceptar"
	ok.pressed.connect(_on_rename_confirm)
	for n in [_first_edit, _last_edit, ok]:
		_rename_box.add_child(n)
	_first_edit.text = c.first_name
	_last_edit.text = c.last_name
	_first_edit.text_submitted.connect(func(_t): _on_rename_confirm())
	_last_edit.text_submitted.connect(func(_t): _on_rename_confirm())

func _on_profile() -> void:
	var c := CharacterLoader.load_character(_selected)
	if c == null:
		return
	var r := Relationship.new()
	r.person_name = c.full_name()
	r.kind = Relationship.Kind.CORTESANO
	r.character = c
	CharacterProfile.open(self, r)

func _on_edit() -> void:
	var c := CharacterLoader.load_character(_selected)
	if c == null:
		return
	CreationState.edit_character = c
	CreationState.edit_path = _selected
	get_tree().change_scene_to_file("res://scenes/character_creation/character_creation.tscn")

func _on_duplicate() -> void:
	var path := duplicate_character(_selected)
	_status.text = "Copia creada." if not path.is_empty() else "No se pudo copiar."
	_refresh(path)

func _on_rename() -> void:
	_rename_box.visible = not _rename_box.visible
	if _rename_box.visible:
		_first_edit.grab_focus()

func _on_rename_confirm() -> void:
	var ok := rename_character(_selected, _first_edit.text, _last_edit.text)
	_status.text = "Renombrado." if ok else "Pon al menos un nombre."
	if ok:
		_refresh(_selected)

func _on_delete() -> void:
	var c := CharacterLoader.load_character(_selected)
	var dialog := ConfirmationDialog.new()
	dialog.title = "Borrar personaje"
	dialog.dialog_text = "¿Borrar a %s? No se puede deshacer." % (c.full_name() if c != null else _selected.get_file())
	dialog.ok_button_text = "Borrar"
	dialog.cancel_button_text = "Cancelar"
	dialog.confirmed.connect(func():
		_status.text = "Borrado." if delete_character(_selected) else "No se pudo borrar."
		_selected = ""
		_refresh())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	dialog.get_cancel_button().grab_focus()

## Elegir archivo para exportar (guardar) o importar (abrir).
func _ask_file(mode: int) -> void:
	if mode == FileDialog.FILE_MODE_SAVE_FILE and _selected.is_empty():
		return
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray([JSON_FILTER])
	dialog.title = "Exportar personaje" if mode == FileDialog.FILE_MODE_SAVE_FILE else "Importar personaje"
	dialog.size = Vector2i(760, 480)
	if mode == FileDialog.FILE_MODE_SAVE_FILE:
		dialog.current_file = _selected.get_file()
	dialog.file_selected.connect(func(file: String):
		if mode == FileDialog.FILE_MODE_SAVE_FILE:
			_status.text = "Exportado a %s" % file if export_character(_selected, file) else "No se pudo exportar."
		else:
			var path := import_character(file)
			_status.text = "Importado." if not path.is_empty() else "Ese archivo no es un personaje válido."
			if not path.is_empty():
				_refresh(path)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
