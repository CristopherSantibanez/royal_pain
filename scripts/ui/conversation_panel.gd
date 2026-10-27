extends Control
# Conversación con una persona: retrato, saludo según la confianza y actitudes a elegir
# (Amable, Halagador, Franco, Amenazante y, si cabe romance, Charla íntima). Se abre encima de cualquier pantalla:
#   const ConversationPanel = preload("res://scripts/ui/conversation_panel.gd")
#   ConversationPanel.open(self, relacion).finished.connect(func(text): ...)

signal finished(text: String)   # al cerrar; text = resultado de la charla ("" si no se habló)

const PORTRAIT_SIZE := Vector2(150, 210)

var relation: Relationship
var _result_text := ""
var _choices: VBoxContainer
var _reply_label: Label
var _close: Button

static func open(host: Node, r: Relationship) -> Control:
	var panel: Control = load("res://scripts/ui/conversation_panel.gd").new()
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
	panel.custom_minimum_size = Vector2(820, 440)
	center.add_child(panel)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	panel.add_child(body)

	var c := relation.character
	# Izquierda: retrato, nombre y carácter.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(PORTRAIT_SIZE.x, 0)
	body.add_child(left)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = PORTRAIT_SIZE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = c.get_portrait()
	left.add_child(portrait)
	_label(left, c.role_name(), "MutedLabel").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Derecha: saludo, actitudes y respuesta.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	_label(right, c.full_name(), "HeaderLabel")
	_label(right, "%s · %s (intimidad %d)" % [DialogueCatalog.personality_name(c.personality),
		RelationsData.intimacy_label(relation), relation.affection], "MutedLabel")
	var greeting := RelationsData.greeting_line(relation)
	if not greeting.is_empty():
		_label(right, "«%s»" % greeting, "BodyBoldLabel")
	_label(right, "¿Con qué actitud le hablas?", "SubheaderLabel")
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 4)
	right.add_child(_choices)
	for option: Dictionary in RelationsData.conversation_options(relation):
		_choices.add_child(_choice_button(option))
	_reply_label = _label(right, "", "")
	_reply_label.visible = false
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	_close = Button.new()
	_close.text = "Cerrar"
	_close.size_flags_horizontal = Control.SIZE_SHRINK_END
	_close.pressed.connect(_finish)
	right.add_child(_close)
	UiAnim.fade_in(panel, 0.2)
	_focus_first.call_deferred()

func _choice_button(option: Dictionary) -> Button:
	var button := Button.new()
	var reason: String = option.reason
	button.text = "%s — %d%%" % [option.label, roundi(option.chance * 100)] if reason.is_empty() else "%s — %s" % [option.label, reason]
	button.tooltip_text = option.hint
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = not reason.is_empty()
	if option.id == "intima":
		button.theme_type_variation = &"PrimaryButton"
	button.pressed.connect(func(): _speak(option.id))
	return button

func _speak(attitude: String) -> void:
	var result: Dictionary = RelationsData.converse(relation, attitude)
	_result_text = result.text
	for child in _choices.get_children():
		child.queue_free()
	_reply_label.text = result.text
	_reply_label.visible = true
	UiAnim.fade_in(_reply_label, 0.25)
	_close.grab_focus.call_deferred()

func _focus_first() -> void:
	for child in _choices.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			return
	_close.grab_focus()

func _finish() -> void:
	finished.emit(_result_text)
	queue_free()

func _label(parent: Node, text: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not variation.is_empty():
		label.theme_type_variation = StringName(variation)
	parent.add_child(label)
	return label

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish()
