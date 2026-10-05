extends Control

@onready var player_option: OptionButton = %PlayerOption
@onready var enemy_option: OptionButton = %EnemyOption
@onready var btn_volver_menu: Button = %BtnVolverMenu
@onready var btn_iniciar: Button = %BtnIniciar

const TEST_ID := -1

var available_paths: Array[String] = []

func _ready() -> void:
	available_paths = CharacterLoader.get_saved_character_paths()
	_populate_option(player_option)
	_populate_option(enemy_option)

	btn_volver_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	btn_iniciar.pressed.connect(_on_iniciar_pressed)

func _populate_option(opt: OptionButton) -> void:
	opt.clear()
	opt.add_item("Personaje de Prueba (generado)", TEST_ID)
	for i in range(available_paths.size()):
		var c := CharacterLoader.load_character(available_paths[i])
		var label := c.full_name() if c != null else available_paths[i].get_file()
		opt.add_item(label, i)

func _get_selected_character(opt: OptionButton, test_name: String, test_role: int) -> Character:
	var id := opt.get_selected_id()
	if id == TEST_ID:
		return CharacterLoader.make_test_character(test_name, test_role)
	return CharacterLoader.load_character(available_paths[id])

func _on_iniciar_pressed() -> void:
	CombatSetup.clear()   # el modo prueba nunca hereda un duelo de campaña
	CombatSetup.player_character = _get_selected_character(player_option, "Sir Alaric", Character.Role.CABALLERO)
	CombatSetup.enemy_character = _get_selected_character(enemy_option, "Bandido Renco", Character.Role.SOLDADO)
	get_tree().change_scene_to_file("res://scenes/combat/combat.tscn")
