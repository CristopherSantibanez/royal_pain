extends Control
# Pantalla de ranuras de guardado. Modo "save" (desde el mapa) o "load" (desde el menú),
# según SaveSystem.slots_mode.

@onready var title_label: Label = %TitleLabel
@onready var rows: VBoxContainer = %Rows
@onready var feedback_label: Label = %FeedbackLabel
@onready var btn_back: Button = %BtnBack

var saving: bool = false
var _confirm_slot: String = ""   # ranura pendiente de confirmar (sobrescribir o borrar)
var _confirm_action: String = ""

func _ready() -> void:
	saving = SaveSystem.slots_mode == "save" and GameManager.is_game_active
	title_label.text = "Guardar Partida" if saving else "Cargar Partida"
	btn_back.text = "Volver al Mapa" if saving else "Volver al Menú"
	btn_back.pressed.connect(func(): get_tree().change_scene_to_file(SaveSystem.slots_return_scene))
	_rebuild()

func _rebuild() -> void:
	for child in rows.get_children():
		child.queue_free()
	for slot in SaveSystem.all_slots():
		rows.add_child(_make_row(slot))

func _make_row(slot: String) -> Control:
	var info := SaveSystem.slot_info(slot)
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.text = SaveSystem.slot_title(slot)
	name_lbl.add_theme_color_override("font_color", Color(0.831, 0.686, 0.216))
	var detail_lbl := Label.new()
	detail_lbl.text = "%s\nGuardada el %s" % [info.summary, info.saved_at] if info.exists else "— Vacía —"
	text_box.add_child(name_lbl)
	text_box.add_child(detail_lbl)
	hbox.add_child(text_box)

	if saving:
		if slot == SaveSystem.AUTO_SLOT:
			var note := Label.new()
			note.text = "Se guarda sola al comenzar cada mes"
			note.add_theme_font_size_override("font_size", 12)
			hbox.add_child(note)
		else:
			var confirming := _confirm_slot == slot and _confirm_action == "save"
			var btn_save := Button.new()
			btn_save.text = "¿Sobrescribir?" if confirming else "Guardar aquí"
			btn_save.pressed.connect(_on_save_pressed.bind(slot, info.exists))
			hbox.add_child(btn_save)
	else:
		var btn_load := Button.new()
		btn_load.text = "Cargar"
		btn_load.disabled = not info.exists
		btn_load.pressed.connect(_on_load_pressed.bind(slot))
		hbox.add_child(btn_load)

	if slot != SaveSystem.AUTO_SLOT and info.exists:
		var confirming_delete := _confirm_slot == slot and _confirm_action == "delete"
		var btn_delete := Button.new()
		btn_delete.text = "¿Borrar de verdad?" if confirming_delete else "Borrar"
		btn_delete.pressed.connect(_on_delete_pressed.bind(slot))
		hbox.add_child(btn_delete)
	return panel

func _on_save_pressed(slot: String, occupied: bool) -> void:
	# Sobrescribir una ranura ocupada pide un segundo clic.
	if occupied and not (_confirm_slot == slot and _confirm_action == "save"):
		_confirm_slot = slot
		_confirm_action = "save"
		feedback_label.text = "La %s ya tiene una partida. Pulsa de nuevo para sobrescribirla." % SaveSystem.slot_title(slot)
		_rebuild()
		return
	_clear_confirm()
	var err := SaveSystem.save_game(slot)
	feedback_label.text = "Partida guardada en la %s." % SaveSystem.slot_title(slot) if err == OK else "Error al guardar (%d)." % err
	_rebuild()

func _on_load_pressed(slot: String) -> void:
	if SaveSystem.load_game(slot):
		get_tree().change_scene_to_file("res://scenes/map/map.tscn")
	else:
		feedback_label.text = "No se pudo cargar la %s." % SaveSystem.slot_title(slot)

func _on_delete_pressed(slot: String) -> void:
	if not (_confirm_slot == slot and _confirm_action == "delete"):
		_confirm_slot = slot
		_confirm_action = "delete"
		feedback_label.text = "Pulsa de nuevo para borrar la %s." % SaveSystem.slot_title(slot)
		_rebuild()
		return
	_clear_confirm()
	SaveSystem.delete_save(slot)
	feedback_label.text = "%s borrada." % SaveSystem.slot_title(slot)
	_rebuild()

func _clear_confirm() -> void:
	_confirm_slot = ""
	_confirm_action = ""
