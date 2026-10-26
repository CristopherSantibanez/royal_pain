class_name PortraitViewer
extends Control
# Retrato completo de un personaje, encima de la pantalla. Se cierra con un clic o Esc.
#   PortraitViewer.open(get_tree().current_scene, personaje)

var character: Character

static func open(host: Node, c: Character) -> PortraitViewer:
	var viewer := PortraitViewer.new()
	viewer.character = c
	# En escenas con CanvasLayer (el mapa) se añade a una capa propia para quedar por encima de la interfaz.
	var layer := CanvasLayer.new()
	layer.layer = 50
	host.add_child(layer)
	layer.add_child(viewer)
	viewer.tree_exited.connect(layer.queue_free)
	return viewer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	center.add_child(box)
	var portrait := TextureRect.new()
	portrait.texture = character.get_portrait()
	portrait.custom_minimum_size = Vector2(380, 520)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(portrait)
	var name_label := Label.new()
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.text = character.full_name()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	var info := Label.new()
	info.theme_type_variation = &"MutedLabel"
	info.text = "%s · %s · Combate %d · Defensa %d · Liderazgo %d" % [
		character.role_name(), DialogueCatalog.personality_name(character.personality),
		character.combat, character.defense, character.leadership]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(info)
	UiAnim.fade_in(self, 0.15)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
