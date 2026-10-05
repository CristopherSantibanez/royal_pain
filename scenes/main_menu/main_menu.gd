extends Control

@onready var btn_nueva_partida: Button = $ScreenMargin/CenterBox/MenuVBox/BtnNuevaPartida
@onready var btn_cargar_partida: Button = $ScreenMargin/CenterBox/MenuVBox/BtnCargarPartida
@onready var btn_combate: Button = $ScreenMargin/CenterBox/MenuVBox/BtnCombatePrueba
@onready var btn_crear_personaje: Button = $ScreenMargin/CenterBox/MenuVBox/BtnCrearPersonaje
@onready var btn_mapa: Button = $ScreenMargin/CenterBox/MenuVBox/BtnMapa
@onready var btn_salir: Button = $ScreenMargin/CenterBox/MenuVBox/BtnSalir

func _ready() -> void:
	btn_nueva_partida.pressed.connect(_on_nueva_partida_pressed)
	btn_cargar_partida.pressed.connect(_on_cargar_partida_pressed)
	if SaveSystem.has_save():
		btn_cargar_partida.tooltip_text = SaveSystem.read_summary()
	else:
		btn_cargar_partida.disabled = true
		btn_cargar_partida.tooltip_text = "No hay ninguna partida guardada."
	btn_combate.pressed.connect(_on_combate_pressed)
	btn_crear_personaje.pressed.connect(_on_crear_personaje_pressed)
	btn_mapa.pressed.connect(_on_mapa_pressed)
	btn_salir.pressed.connect(_on_salir_pressed)
	# Con una partida en curso, el botón de mapa sirve para retomarla; si no, es solo una vista previa.
	btn_mapa.text = "Continuar Partida" if GameManager.is_game_active else "Ver Mapa"

func _on_nueva_partida_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/new_game/new_game.tscn")

func _on_cargar_partida_pressed() -> void:
	if SaveSystem.load_game():
		get_tree().change_scene_to_file("res://scenes/map/map.tscn")
	else:
		btn_cargar_partida.text = "No se pudo cargar la partida"
		btn_cargar_partida.disabled = true

func _on_combate_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/fighter_select/fighter_select.tscn")

func _on_crear_personaje_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_creation/character_creation.tscn")

func _on_mapa_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")

func _on_salir_pressed() -> void:
	get_tree().quit()
