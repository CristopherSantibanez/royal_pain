extends Control
# Audiencia con el señor de un castillo (ver TravelData). Ya está pagada (1 acción): se elige una
# sola gestión — presentar respetos, pedir noticias del reino, pedir un encargo o jurarle lealtad.
#   const AudiencePanel = preload("res://scripts/ui/audience_panel.gd")
#   AudiencePanel.open(self, castillo)   # al cerrarse deja el resultado en get_meta("result")

const PORTRAIT_SIZE := Vector2(150, 210)

var castle: Castle
var _choices: VBoxContainer
var _reply_label: Label
var _close: Button
var _fealty_armed := false   # el primer clic en «Jurar lealtad» muestra lo que cuesta; el segundo jura

static func open(host: Node, c: Castle) -> Control:
	var panel: Control = load("res://scripts/ui/audience_panel.gd").new()
	panel.castle = c
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
	panel.custom_minimum_size = Vector2(820, 420)
	center.add_child(panel)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	panel.add_child(body)

	var lord := TravelData.lord_relation(castle)
	var c: Character = lord.character if lord != null else null
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(PORTRAIT_SIZE.x, 0)
	body.add_child(left)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = PORTRAIT_SIZE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = c.get_portrait() if c != null else null
	left.add_child(portrait)
	_label(left, c.role_name() if c != null else "", "MutedLabel").horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	_label(right, "Audiencia en %s" % castle.castle_name, "HeaderLabel")
	if lord != null:
		_label(right, "%s · %s · afinidad contigo %d" % [lord.person_name, KingdomEnums.kingdom_name(castle.kingdom), lord.affinity], "MutedLabel")
		var greeting := _greeting(lord)
		_label(right, "«%s»" % greeting, "BodyBoldLabel")
	_label(right, "¿Qué le pides?", "SubheaderLabel")
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 4)
	right.add_child(_choices)
	var player: Character = GameManager.player_character
	_choices.add_child(_choice("Presentar tus respetos", "Afinidad +%d." % (TravelData.AUDIENCE_RESPECT_BASE + player.charisma / 3), "",
		func(): return TravelData.audience_respects(castle)))
	_choices.add_child(_choice("Pedir noticias del reino", "Te cuenta la guarnición y el oro de los castillos de su reino.", "",
		func(): return TravelData.audience_news(castle)))
	var mission_reason := ""
	if player.rank() < Character.rank_of(Character.Role.SOLDADO):
		mission_reason = "No encarga nada a un campesino."
	elif MissionData.active.size() >= MissionData.MAX_ACTIVE:
		mission_reason = "Ya tienes demasiados encargos."
	_choices.add_child(_choice("Pedir un encargo", "Una tarea con plazo y recompensa; quien te la encarga es este señor.", mission_reason,
		func(): return TravelData.audience_mission(castle)))
	var fealty_reason := TravelData.fealty_blocker(castle)
	var fealty := _choice("Jurarle lealtad", TravelData.fealty_preview(castle) if fealty_reason.is_empty() else "", fealty_reason, Callable())
	fealty.pressed.connect(func(): _on_fealty_pressed(fealty))
	_choices.add_child(fealty)
	_reply_label = _label(right, "", "")
	_reply_label.visible = false
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	_close = Button.new()
	_close.text = "Retirarte"
	_close.size_flags_horizontal = Control.SIZE_SHRINK_END
	_close.pressed.connect(queue_free)
	right.add_child(_close)
	UiAnim.fade_in(panel, 0.2)
	_focus_first.call_deferred()

func _greeting(lord: Relationship) -> String:
	var player: Character = GameManager.player_character
	if lord.affinity >= 40:
		return "Bienvenid%s a mi casa, %s. Aquí siempre tendrás un sitio en mi mesa." % ["a" if player.gender == CharacterEnums.Gender.FEMENINO else "o", player.full_name()]
	if lord.affinity >= 0:
		return "%s. Te escucho, pero sé breve: muchos esperan." % player.full_name()
	return "Tienes valor para presentarte aquí, %s. Habla." % player.full_name()

func _choice(text: String, hint: String, reason: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text if reason.is_empty() else "%s — %s" % [text, reason]
	button.tooltip_text = hint
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = not reason.is_empty()
	if action.is_valid():
		button.pressed.connect(func(): _finish_with(str(action.call())))
	return button

func _on_fealty_pressed(button: Button) -> void:
	if not _fealty_armed:
		_fealty_armed = true
		button.text = "Confirmar el juramento"
		button.theme_type_variation = &"PrimaryButton"
		_reply_label.text = TravelData.fealty_preview(castle)
		_reply_label.visible = true
		return
	var r := TravelData.swear_fealty(castle)
	_finish_with(r.text)

func _finish_with(text: String) -> void:
	set_meta("result", text)
	for child in _choices.get_children():
		child.queue_free()
	_reply_label.text = text
	_reply_label.visible = true
	UiAnim.fade_in(_reply_label, 0.25)
	_close.text = "Cerrar"
	_close.grab_focus.call_deferred()

func _focus_first() -> void:
	for child in _choices.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			return
	_close.grab_focus()

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
		queue_free()
