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
	# Tu castillo de origen se marca con una estrella.
	var is_home: bool = GameManager.is_game_active and data.castle_id == GameManager.home_castle_id
	name_label.text = ("★ " if is_home else "") + data.castle_name
	input_pickable = true
	_fit_icon_scale()
	_style_label()

# Rótulo tipo placa: fondo oscuro con una franja del color del reino, centrado bajo el icono.
func _style_label() -> void:
	name_label.theme_type_variation = &"SubheaderLabel"
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", LABEL_GOLD_COLOR.lightened(0.25))
	name_label.add_theme_color_override("font_outline_color", LABEL_OUTLINE_COLOR)
	name_label.add_theme_constant_override("outline_size", LABEL_OUTLINE_SIZE)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.06, 0.04, 0.03, 0.8)
	plate.border_color = KingdomEnums.kingdom_color(castle_data.kingdom)
	plate.border_width_bottom = 3
	plate.set_corner_radius_all(3)
	plate.content_margin_left = 7
	plate.content_margin_right = 7
	plate.content_margin_top = 1
	plate.content_margin_bottom = 2
	name_label.add_theme_stylebox_override("normal", plate)
	name_label.reset_size()
	name_label.position = Vector2(-name_label.size.x / 2.0, ICON_DISPLAY_SIZE * 0.5)

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
