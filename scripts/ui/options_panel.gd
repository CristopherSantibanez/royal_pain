class_name OptionsPanel
extends Control
# Ventana de opciones (volumen por bus y pantalla completa). Se abre encima de cualquier pantalla:
#   OptionsPanel.open(self)

const SLIDER_WIDTH := 240

var _first_slider: HSlider

static func open(host: Node) -> OptionsPanel:
	var panel := OptionsPanel.new()
	host.add_child(panel)
	return panel

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Opciones"
	title.theme_type_variation = "HeaderLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(HSeparator.new())

	var sub := Label.new()
	sub.text = "Sonido"
	sub.theme_type_variation = "SubheaderLabel"
	box.add_child(sub)
	for bus in Settings.BUSES:
		box.add_child(_volume_row(bus))

	box.add_child(HSeparator.new())
	var fs := CheckBox.new()
	fs.text = "Pantalla completa"
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(Settings.set_fullscreen)
	box.add_child(fs)

	var close := Button.new()
	close.text = "Cerrar"
	close.theme_type_variation = "PrimaryButton"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.custom_minimum_size = Vector2(180, 0)
	close.pressed.connect(close_panel)
	box.add_child(close)

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	_first_slider.grab_focus.call_deferred()

func _volume_row(bus: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.text = Settings.BUS_LABELS[bus]
	name_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Settings.volumes[bus]
	slider.custom_minimum_size = Vector2(SLIDER_WIDTH, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	if _first_slider == null:
		_first_slider = slider

	var pct := Label.new()
	pct.theme_type_variation = "MutedLabel"
	pct.custom_minimum_size = Vector2(48, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.text = "%d%%" % roundi(slider.value * 100)
	row.add_child(pct)

	slider.value_changed.connect(func(v: float) -> void:
		Settings.set_volume(bus, v)
		pct.text = "%d%%" % roundi(v * 100))
	# Al soltar el deslizador de efectos se oye un golpe de muestra.
	if bus == "SFX" or bus == "Master":
		slider.drag_ended.connect(func(_changed: bool) -> void: Sfx.play("clash", -4.0))
	return row

func close_panel() -> void:
	Settings.save()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
