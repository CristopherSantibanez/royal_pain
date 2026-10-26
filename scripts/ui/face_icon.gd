class_name FaceIcon
extends PanelContainer
# Cara de un personaje en un marco. Al pulsarla se ve su retrato completo
# (o se ejecuta on_click, por ejemplo para abrir su ficha).
#   add_child(FaceIcon.make(personaje, 48))

const FRAME_COLOR := Color("7a5c2e")
const FRAME_HOVER := Color("f0d48a")

var character: Character
var on_click: Callable
var _style: StyleBoxFlat

static func make(c: Character, size: int, frame_color: Color = FRAME_COLOR, clickable: bool = true, click: Callable = Callable()) -> FaceIcon:
	var icon := FaceIcon.new()
	icon.character = c
	icon.on_click = click
	icon.custom_minimum_size = Vector2(size, size)
	icon._build(size, frame_color, clickable)
	return icon

func _build(size: int, frame_color: Color, clickable: bool) -> void:
	_style = StyleBoxFlat.new()
	_style.bg_color = Color("0d0906")
	_style.border_color = frame_color
	_style.set_border_width_all(2 if size < 64 else 3)
	_style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", _style)
	var tex := TextureRect.new()
	tex.texture = character.get_face() if character != null else null
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tex)
	if clickable and character != null:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "%s — ver retrato" % character.full_name()
		mouse_entered.connect(func(): _style.border_color = FRAME_HOVER)
		mouse_exited.connect(func(): _style.border_color = frame_color)
		gui_input.connect(_on_input)
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if on_click.is_valid():
			on_click.call()
		else:
			PortraitViewer.open(get_tree().current_scene, character)
