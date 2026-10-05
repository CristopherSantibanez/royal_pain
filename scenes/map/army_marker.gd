extends Area2D

signal army_clicked(army: Army)

const RADIUS := 16.0
const COLOR_IDLE := Color(0.2, 0.5, 0.9)
const COLOR_MARCHING := Color(0.9, 0.75, 0.15)
const COLOR_BATTLE := Color(0.85, 0.15, 0.15)
const COLOR_ENEMY := Color(0.55, 0.2, 0.65)   # ejércitos de otros reinos (en marcha o estacionados)

@onready var size_label: Label = $SizeLabel

var army_data: Army
var is_player_army: bool = true

func setup(a: Army, world_position: Vector2, player_owned: bool = true) -> void:
	army_data = a
	is_player_army = player_owned
	position = world_position
	input_pickable = true
	size_label.text = str(a.size)
	queue_redraw()

func _ready() -> void:
	input_event.connect(_on_input_event)

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, _get_color())
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 32, Color.BLACK, 2.0)

func _get_color() -> Color:
	if army_data == null:
		return COLOR_IDLE
	if army_data.pending_battle:
		return COLOR_BATTLE
	if not is_player_army:
		return COLOR_ENEMY
	if army_data.is_marching():
		return COLOR_MARCHING
	return COLOR_IDLE

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		army_clicked.emit(army_data)
