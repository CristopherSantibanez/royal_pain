extends Camera2D

@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.3
@export var max_zoom: float = 2.5
@export var pan_speed: float = 1.0

var dragging: bool = false
var drag_start_mouse: Vector2
var drag_start_camera: Vector2

func setup_bounds(map_width: float, map_height: float) -> void:
	# Límites: no dejar que la cámara se desplace fuera de la imagen
	limit_left = 0
	limit_top = 0
	limit_right = int(map_width)
	limit_bottom = int(map_height)

	# Zoom inicial: que quepa el mapa completo en la ventana actual
	var viewport_size := get_viewport_rect().size
	var fit_zoom: float = min(viewport_size.x / map_width, viewport_size.y / map_height)
	fit_zoom = clamp(fit_zoom, min_zoom, max_zoom)
	zoom = Vector2(fit_zoom, fit_zoom)
	min_zoom = fit_zoom   # no dejar hacer zoom OUT más allá de ver el mapa completo

	# Centrar la cámara en medio del mapa
	position = Vector2(map_width / 2.0, map_height / 2.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(1.0 - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(1.0 + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			if dragging:
				drag_start_mouse = event.position
				drag_start_camera = position

	elif event is InputEventMouseMotion and dragging:
		var delta: Vector2 = (event.position - drag_start_mouse) / zoom.x
		position = drag_start_camera - delta * pan_speed

func _zoom_at(factor: float) -> void:
	var new_zoom: float = clamp(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
