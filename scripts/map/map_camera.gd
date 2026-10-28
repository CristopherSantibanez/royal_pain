extends Camera2D
# Cámara del mapa: arrastre (botón derecho), rueda (zoom hacia el cursor), WASD/stick y +/− o L1/R1.
# Los límites tienen en cuenta la interfaz: los bordes del mapa pueden quedar a la vista entre la
# barra superior y los paneles inferiores (hud_top / hud_bottom, en píxeles de pantalla).

@export var zoom_speed: float = 0.1
@export var max_zoom: float = 2.5
@export var pan_speed: float = 1.0

const KEY_PAN_SPEED := 700.0   # píxeles de pantalla por segundo con WASD o el stick
const EXTRA_MARGIN := 24.0     # un poco de aire alrededor del mapa

var min_zoom: float = 0.3
var hud_top: float = 72.0      # la barra superior tapa esto
var hud_bottom: float = 140.0  # los paneles inferiores tapan esto (menos si se ocultan)
var map_size := Vector2.ZERO

var dragging: bool = false
var drag_start_mouse: Vector2
var drag_start_camera: Vector2

func setup_bounds(map_width: float, map_height: float) -> void:
	map_size = Vector2(map_width, map_height)
	# Los límites del motor se sustituyen por los propios (_clamp_position), que cuentan la interfaz.
	limit_left = -100000
	limit_top = -100000
	limit_right = 100000
	limit_bottom = 100000
	position_smoothing_enabled = true
	position_smoothing_speed = 12.0
	var viewport_size := get_viewport_rect().size
	# Zoom inicial: el mapa cubre la ventana. Alejándose, se puede llegar a verlo entero.
	var cover: float = maxf(viewport_size.x / map_width, viewport_size.y / map_height)
	min_zoom = clampf(_contain_zoom(), 0.1, cover)
	zoom = Vector2.ONE * clampf(cover, min_zoom, max_zoom)
	position = map_size / 2.0
	_clamp_position()
	reset_smoothing()

## Centra la cámara en un punto del mapa (sin animación si instant).
func focus_on(world_pos: Vector2, instant: bool = false) -> void:
	position = world_pos
	_clamp_position()
	if instant:
		reset_smoothing()

## Cambia cuánto tapan los paneles (al ocultarlos o mostrarlos) y recoloca la cámara.
func set_hud_margins(top: float, bottom: float) -> void:
	hud_top = top
	hud_bottom = bottom
	min_zoom = minf(min_zoom, _contain_zoom())
	_clamp_position()

func _contain_zoom() -> float:
	var viewport_size := get_viewport_rect().size
	var usable := Vector2(viewport_size.x, viewport_size.y - hud_top - hud_bottom) - Vector2.ONE * EXTRA_MARGIN * 2.0
	return minf(usable.x / map_size.x, usable.y / map_size.y)

func _process(delta: float) -> void:
	var dir := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if dir != Vector2.ZERO:
		position += dir * KEY_PAN_SPEED * delta / zoom.x
		_clamp_position()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cam_zoom_in"):
		_zoom_at(1.0 + zoom_speed, get_viewport_rect().size / 2.0)
	elif event.is_action_pressed("cam_zoom_out"):
		_zoom_at(1.0 - zoom_speed, get_viewport_rect().size / 2.0)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(1.0 + zoom_speed, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(1.0 - zoom_speed, event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			if dragging:
				drag_start_mouse = event.position
				drag_start_camera = position
	elif event is InputEventMouseMotion and dragging:
		var delta: Vector2 = (event.position - drag_start_mouse) / zoom.x
		position = drag_start_camera - delta * pan_speed
		_clamp_position()
		reset_smoothing()   # el arrastre sigue al ratón sin retraso

# Zoom manteniendo fijo el punto del mapa que hay bajo el cursor.
func _zoom_at(factor: float, screen_point: Vector2) -> void:
	var viewport_size := get_viewport_rect().size
	var before := position + (screen_point - viewport_size / 2.0) / zoom.x
	var new_zoom: float = clampf(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
	position = before - (screen_point - viewport_size / 2.0) / new_zoom
	_clamp_position()

# El centro de la cámara puede ir tan lejos como haga falta para que cada borde del mapa quede
# justo dentro de la zona libre de interfaz. Si el mapa cabe entero, se queda centrado.
func _clamp_position() -> void:
	if map_size == Vector2.ZERO:
		return
	var view := get_viewport_rect().size / zoom.x
	var top := (hud_top + EXTRA_MARGIN) / zoom.x
	var bottom := (hud_bottom + EXTRA_MARGIN) / zoom.x
	var margin_x := EXTRA_MARGIN / zoom.x
	var min_x := view.x / 2.0 - margin_x
	var max_x := map_size.x - view.x / 2.0 + margin_x
	var min_y := view.y / 2.0 - top
	var max_y := map_size.y - view.y / 2.0 + bottom
	position.x = map_size.x / 2.0 if min_x > max_x else clampf(position.x, min_x, max_x)
	position.y = (min_y + max_y) / 2.0 if min_y > max_y else clampf(position.y, min_y, max_y)
