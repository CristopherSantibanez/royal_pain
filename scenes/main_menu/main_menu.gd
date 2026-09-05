extends Control

@onready var btn_combate: Button = $ScreenMargin/CenterBox/MenuVBox/BtnCombatePrueba
@onready var btn_crear_personaje: Button = $ScreenMargin/CenterBox/MenuVBox/BtnCrearPersonaje
@onready var btn_mapa: Button = $ScreenMargin/CenterBox/MenuVBox/BtnMapa
@onready var btn_salir: Button = $ScreenMargin/CenterBox/MenuVBox/BtnSalir

func _ready() -> void:
	btn_combate.pressed.connect(_on_combate_pressed)
	btn_crear_personaje.pressed.connect(_on_crear_personaje_pressed)
	btn_mapa.pressed.connect(_on_mapa_pressed)
	btn_salir.pressed.connect(_on_salir_pressed)

func _on_combate_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/fighter_select/fighter_select.tscn")

func _on_crear_personaje_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_creation/character_creation.tscn")

func _on_mapa_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")

func _on_salir_pressed() -> void:
	get_tree().quit()
