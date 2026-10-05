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
	var latest := SaveSystem.latest_slot()
	if latest == "":
		btn_cargar_partida.disabled = true
		btn_cargar_partida.tooltip_text = "No hay ninguna partida guardada."
	btn_combate.pressed.connect(_on_combate_pressed)
	btn_crear_personaje.pressed.connect(_on_crear_personaje_pressed)
	btn_mapa.pressed.connect(_on_mapa_pressed)
	btn_salir.pressed.connect(_on_salir_pressed)
	# El botón del mapa retoma la partida en curso; si no hay, carga el guardado más reciente;
	# y si tampoco hay guardados, es solo una vista previa del mapa.
	if GameManager.is_game_active:
		btn_mapa.text = "Continuar Partida"
	elif latest != "":
		btn_mapa.text = "Continuar"
		btn_mapa.tooltip_text = "%s: %s" % [SaveSystem.slot_title(latest), SaveSystem.read_summary(latest)]
	else:
		btn_mapa.text = "Ver Mapa"

func _on_nueva_partida_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/new_game/new_game.tscn")

func _on_cargar_partida_pressed() -> void:
	SaveSystem.slots_mode = "load"
	SaveSystem.slots_return_scene = "res://scenes/main_menu/main_menu.tscn"
	get_tree().change_scene_to_file("res://scenes/save_slots/save_slots.tscn")

func _on_combate_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/fighter_select/fighter_select.tscn")

func _on_crear_personaje_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_creation/character_creation.tscn")

func _on_mapa_pressed() -> void:
	if not GameManager.is_game_active:
		var latest := SaveSystem.latest_slot()
		if latest != "" and not SaveSystem.load_game(latest):
			btn_mapa.text = "No se pudo cargar la partida"
			btn_mapa.disabled = true
			return
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")

func _on_salir_pressed() -> void:
	get_tree().quit()
