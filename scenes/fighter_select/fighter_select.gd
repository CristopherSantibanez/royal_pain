extends Control

@onready var player_option: OptionButton = %PlayerOption
@onready var enemy_option: OptionButton = %EnemyOption
@onready var btn_volver_menu: Button = %BtnVolverMenu
@onready var btn_iniciar: Button = %BtnIniciar
@onready var player_portrait: TextureRect = %PlayerPortrait
@onready var enemy_portrait: TextureRect = %EnemyPortrait
@onready var player_stats: Label = %PlayerStats
@onready var enemy_stats: Label = %EnemyStats

var available_paths: Array[String] = []

func _ready() -> void:
	available_paths = CharacterLoader.get_saved_character_paths()
	_populate_option(player_option)
	_populate_option(enemy_option)

	btn_volver_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	btn_iniciar.pressed.connect(_on_iniciar_pressed)
	player_option.item_selected.connect(func(_i): _preview(player_option, player_portrait, player_stats, Character.Role.CABALLERO))
	enemy_option.item_selected.connect(func(_i): _preview(enemy_option, enemy_portrait, enemy_stats, Character.Role.SOLDADO))
	_preview(player_option, player_portrait, player_stats, Character.Role.CABALLERO)
	_preview(enemy_option, enemy_portrait, enemy_stats, Character.Role.SOLDADO)
	UiAnim.stagger_in(%RootVBox, 0.06)
	btn_iniciar.grab_focus()

func _preview(opt: OptionButton, portrait: TextureRect, stats: Label, test_role: int) -> void:
	var c := _get_selected_character(opt, "Prueba", test_role)
	if c == null:
		return
	portrait.texture = c.get_portrait()
	stats.text = "%s
Combate %d · Defensa %d · Vida %d" % [c.role_name(), c.combat, c.defense, c.max_health]

func _populate_option(opt: OptionButton) -> void:
	opt.clear()
	# La ruta va como metadato: add_item(label, -1) asigna el índice como id y chocaría con el primer guardado.
	opt.add_item("Personaje de Prueba (generado)")
	opt.set_item_metadata(0, "")
	for path in available_paths:
		var c := CharacterLoader.load_character(path)
		opt.add_item(c.full_name() if c != null else path.get_file())
		opt.set_item_metadata(opt.item_count - 1, path)

func _get_selected_character(opt: OptionButton, test_name: String, test_role: int) -> Character:
	var path: String = opt.get_item_metadata(opt.selected)
	if path.is_empty():
		return CharacterLoader.make_test_character(test_name, test_role)
	return CharacterLoader.load_character(path)

func _on_iniciar_pressed() -> void:
	CombatSetup.clear()   # el modo prueba nunca hereda un duelo de campaña
	CombatSetup.player_character = _get_selected_character(player_option, "Sir Alaric", Character.Role.CABALLERO)
	CombatSetup.enemy_character = _get_selected_character(enemy_option, "Bandido Renco", Character.Role.SOLDADO)
	get_tree().change_scene_to_file(CombatSetup.RPG_SCENE)
