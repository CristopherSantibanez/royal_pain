extends Node
# Autoload — registrar como "Settings"
# Preferencias del jugador (volumen por bus, pantalla completa). Se guardan en user://settings.cfg.

signal changed

var settings_path: String = DataPaths.path("settings.cfg")   # en pruebas, carpeta aparte
const BUSES := ["Master", "Music", "Ambience", "SFX"]
const BUS_LABELS := {"Master": "General", "Music": "Música", "Ambience": "Ambiente", "SFX": "Efectos"}
const DEFAULT_VOLUMES := {"Master": 0.85, "Music": 0.7, "Ambience": 0.6, "SFX": 0.85}

# Controles con teclado y mando. Las flechas y la cruceta mueven el foco de la interfaz (ui_*);
# WASD y el stick izquierdo mueven la cámara del mapa.
const KEY_ACTIONS := {
	"cam_left": [KEY_A], "cam_right": [KEY_D], "cam_up": [KEY_W], "cam_down": [KEY_S],
	"cam_zoom_in": [KEY_EQUAL, KEY_KP_ADD, KEY_PLUS], "cam_zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
	"end_turn": [KEY_T], "map_relations": [KEY_R], "map_missions": [KEY_E], "map_chronicle": [KEY_C],
	"map_next_castle": [KEY_TAB], "map_menu": [KEY_M], "map_toggle_panels": [KEY_H],
}
const JOY_BUTTON_ACTIONS := {
	"cam_zoom_in": JOY_BUTTON_RIGHT_SHOULDER, "cam_zoom_out": JOY_BUTTON_LEFT_SHOULDER,
	"end_turn": JOY_BUTTON_Y, "map_relations": JOY_BUTTON_X, "map_next_castle": JOY_BUTTON_RIGHT_STICK,
	"map_missions": JOY_BUTTON_BACK, "map_menu": JOY_BUTTON_START,
}
const JOY_AXIS_ACTIONS := {   # acción -> [eje, dirección]
	"cam_left": [JOY_AXIS_LEFT_X, -1.0], "cam_right": [JOY_AXIS_LEFT_X, 1.0],
	"cam_up": [JOY_AXIS_LEFT_Y, -1.0], "cam_down": [JOY_AXIS_LEFT_Y, 1.0],
}

var volumes := DEFAULT_VOLUMES.duplicate()
var fullscreen := false

func _ready() -> void:
	_register_input_actions()
	RenderingServer.set_default_clear_color(Color("0d0906"))   # fuera del mapa, oscuro en vez de gris
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		for bus in BUSES:
			volumes[bus] = clampf(float(cfg.get_value("audio", bus, DEFAULT_VOLUMES[bus])), 0.0, 1.0)
		fullscreen = bool(cfg.get_value("video", "fullscreen", false))
	for bus in BUSES:
		_apply_volume(bus)
	_apply_fullscreen()

func _register_input_actions() -> void:
	for action in KEY_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.3)
		for key in KEY_ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action in JOY_BUTTON_ACTIONS:
		var jb := InputEventJoypadButton.new()
		jb.button_index = JOY_BUTTON_ACTIONS[action]
		InputMap.action_add_event(action, jb)
	for action in JOY_AXIS_ACTIONS:
		var ja := InputEventJoypadMotion.new()
		ja.axis = JOY_AXIS_ACTIONS[action][0]
		ja.axis_value = JOY_AXIS_ACTIONS[action][1]
		InputMap.action_add_event(action, ja)

func set_volume(bus: String, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)
	changed.emit()

func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_fullscreen()
	changed.emit()

func save() -> void:
	var cfg := ConfigFile.new()
	for bus in BUSES:
		cfg.set_value("audio", bus, volumes[bus])
	cfg.set_value("video", "fullscreen", fullscreen)
	DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir())
	cfg.save(settings_path)

# El deslizador se eleva al cuadrado: así el cambio de volumen se reparte por todo su recorrido
# (el oído es logarítmico; un deslizador lineal haría casi todo el cambio en el último tramo).
func _apply_volume(bus: String) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var v: float = volumes[bus]
	AudioServer.set_bus_mute(idx, v <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v * v, 0.0001)))

func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
