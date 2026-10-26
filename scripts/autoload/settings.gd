extends Node
# Autoload — registrar como "Settings"
# Preferencias del jugador (volumen por bus, pantalla completa). Se guardan en user://settings.cfg.

signal changed

const SETTINGS_PATH := "user://settings.cfg"
const BUSES := ["Master", "Music", "Ambience", "SFX"]
const BUS_LABELS := {"Master": "General", "Music": "Música", "Ambience": "Ambiente", "SFX": "Efectos"}
const DEFAULT_VOLUMES := {"Master": 0.85, "Music": 0.7, "Ambience": 0.6, "SFX": 0.85}

var volumes := DEFAULT_VOLUMES.duplicate()
var fullscreen := false

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for bus in BUSES:
			volumes[bus] = clampf(float(cfg.get_value("audio", bus, DEFAULT_VOLUMES[bus])), 0.0, 1.0)
		fullscreen = bool(cfg.get_value("video", "fullscreen", false))
	for bus in BUSES:
		_apply_volume(bus)
	_apply_fullscreen()

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
	cfg.save(SETTINGS_PATH)

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
