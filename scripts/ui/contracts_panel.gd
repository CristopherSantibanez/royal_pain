extends Control
# Ventana de contratos mercenarios que ofrece el señor de un castillo (ver MissionData.make_contract).
# Uso: const ContractsPanel = preload("res://scripts/ui/contracts_panel.gd"); ContractsPanel.open(nodo, señor)
# Mirar es gratis; firmar un contrato gasta 1 acción y lo añade a «Encargos».

const OFFERS := 2

var lord: Relationship
var _offers: Array[Dictionary] = []
var _list: VBoxContainer
var _feedback: Label
var _close: Button

static func open(host: Node, employer: Relationship) -> Control:
	var panel: Control = load("res://scripts/ui/contracts_panel.gd").new()
	panel.lord = employer
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

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	if lord != null and lord.character != null:
		var face := TextureRect.new()
		face.texture = lord.character.get_face()
		face.custom_minimum_size = Vector2(56, 56)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.add_child(face)
	var title := Label.new()
	title.text = "Contratos de %s" % (lord.person_name if lord != null else "nadie")
	title.theme_type_variation = &"HeaderLabel"
	head.add_child(title)
	box.add_child(head)

	var stats := Label.new()
	stats.theme_type_variation = &"MutedLabel"
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.text = "Contratos %d · Infamia %d/%d · Compañía %d" % [
		MissionData.contracts_done, MissionData.infamy, MissionData.INFAMY_REFUSE, MissionData.company_size()]
	box.add_child(stats)
	box.add_child(HSeparator.new())

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	box.add_child(_list)

	_feedback = Label.new()
	_feedback.theme_type_variation = &"BodyBoldLabel"
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.visible = false
	box.add_child(_feedback)

	_close = Button.new()
	_close.text = "Cerrar"
	_close.theme_type_variation = &"PrimaryButton"
	_close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close.custom_minimum_size = Vector2(180, 0)
	_close.pressed.connect(queue_free)
	box.add_child(_close)

	_make_offers()
	_rebuild()
	UiAnim.fade_in(panel, 0.15)
	(func(): if UiAnim.focus_first(_list) == null: _close.grab_focus()).call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()

func _make_offers() -> void:
	var player: Character = GameManager.player_character
	var seen: Array = []
	for i in OFFERS:
		var m := MissionData.make_contract(player, lord)
		if m.is_empty() or m.id in seen:
			continue
		seen.append(m.id)
		_offers.append(m)

func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	if _offers.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"MutedLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var refusal := MissionData.hire_refusal(lord)
		empty.text = refusal if not refusal.is_empty() else "%s no tiene trabajo para ti ahora mismo." % (lord.person_name if lord != null else "Nadie")
		_list.add_child(empty)
	for m: Dictionary in _offers:
		_list.add_child(_card(m))

func _card(m: Dictionary) -> Control:
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
	var months := Label.new()
	months.text = "Plazo: %d meses" % int(m.months)
	head.add_child(months)
	box.add_child(head)

	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 16)
	desc.text = "%s\nPaga: %s" % [MissionData.describe_text(m), MissionData.reward_text(m)]
	box.add_child(desc)

	var warn := MissionData.treachery_warning(m)
	if not warn.is_empty():
		var w := Label.new()
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.add_theme_color_override("font_color", Color("e07a5f"))
		w.text = warn
		box.add_child(w)

	var sign := Button.new()
	sign.text = "Firmar (1 acción)"
	sign.size_flags_horizontal = Control.SIZE_SHRINK_END
	var blocker := ""
	if not GameManager.has_actions_remaining():
		blocker = "No te quedan acciones este turno."
	elif MissionData.active.size() >= MissionData.MAX_ACTIVE:
		blocker = "Ya tienes %d contratos o encargos." % MissionData.MAX_ACTIVE
	sign.disabled = not blocker.is_empty()
	sign.tooltip_text = blocker
	sign.pressed.connect(_on_sign.bind(m))
	box.add_child(sign)
	return card

func _on_sign(m: Dictionary) -> void:
	if not GameManager.consume_action():
		_show("No te quedan acciones este turno.")
		return
	MissionData.accept(m)
	_offers.erase(m)
	_rebuild()
	_show("Firmas «%s» con %s. Lo encontrarás en «Encargos»." % [m.title, m.giver])
	_close.grab_focus()

func _show(text: String) -> void:
	_feedback.text = text
	_feedback.visible = true
