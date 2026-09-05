extends Area2D

signal castle_clicked(castle: Castle)

@onready var name_label: Label = $NameLabel
@onready var icon: Sprite2D = $Icon

const ICON_DISPLAY_SIZE: float = 48.0   # tamaño deseado en píxeles de mundo, ajustable a gusto

var castle_data: Castle

const LABEL_GOLD_COLOR := Color("#D4AF37")
const LABEL_OUTLINE_COLOR := Color.BLACK
const LABEL_OUTLINE_SIZE := 4

func setup(data: Castle) -> void:
	castle_data = data
	position = data.position_on_map
	name_label.text = data.castle_name
	input_pickable = true
	_fit_icon_scale()
	_style_label()

func _style_label() -> void:
	name_label.add_theme_color_override("font_color", LABEL_GOLD_COLOR)
	name_label.add_theme_color_override("font_outline_color", LABEL_OUTLINE_COLOR)
	name_label.add_theme_constant_override("outline_size", LABEL_OUTLINE_SIZE)

func _fit_icon_scale() -> void:
	if icon.texture == null:
		return
	var tex_size: Vector2 = icon.texture.get_size()
	var largest_side: float = max(tex_size.x, tex_size.y)
	if largest_side > 0:
		var scale_factor: float = ICON_DISPLAY_SIZE / largest_side
		icon.scale = Vector2(scale_factor, scale_factor)

func _ready() -> void:
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		castle_clicked.emit(castle_data)

func _on_mouse_entered() -> void:
	scale = Vector2(1.15, 1.15)

func _on_mouse_exited() -> void:
	scale = Vector2(1.0, 1.0)
	
var is_visible_to_player: bool = true

func set_visibility_state(visible_state: bool) -> void:
	is_visible_to_player = visible_state
	if visible_state:
		modulate = Color(1, 1, 1, 1)
	else:
		modulate = Color(0.55, 0.55, 0.55, 0.65)
