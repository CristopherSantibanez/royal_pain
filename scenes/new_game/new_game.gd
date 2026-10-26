extends Control

@onready var character_option: OptionButton = %CharacterOption
@onready var castle_option: OptionButton = %CastleOption
@onready var role_option: OptionButton = %RoleOption
@onready var info_label: Label = %InfoLabel
@onready var goal_title: Label = %GoalTitle
@onready var character_info: Label = %CharacterInfo
@onready var portrait: TextureRect = %Portrait
@onready var castle_info: Label = %CastleInfo
@onready var kingdom_banner: ColorRect = %KingdomBanner
@onready var btn_volver_menu: Button = %BtnVolverMenu
@onready var btn_crear_personaje: Button = %BtnCrearPersonaje
@onready var btn_comenzar: Button = %BtnComenzar

# Regente queda fuera: según el diseño se alcanza por sucesión/rebelión, no se elige.
const STARTING_ROLES: Array[int] = [
	Character.Role.CAMPESINO, Character.Role.SOLDADO, Character.Role.CABALLERO,
	Character.Role.NOBLEZA_BAJA, Character.Role.NOBLEZA_ALTA,
]

var available_paths: Array[String] = []
var preview_characters: Array[Character] = []

func _ready() -> void:
	available_paths = CharacterLoader.get_saved_character_paths()
	# Cada partida nueva se juega en un mundo nuevo (no se toca el de una partida en curso).
	if not GameManager.is_game_active:
		MapData.new_world()
	%BtnOtroMundo.disabled = GameManager.is_game_active
	%BtnOtroMundo.pressed.connect(_on_new_world_pressed)
	_refresh_world_label()
	_populate_characters()
	_populate_castles()
	_populate_roles()

	character_option.item_selected.connect(func(_i): _on_character_selected())
	role_option.item_selected.connect(func(_i): _refresh_info())
	castle_option.item_selected.connect(func(_i): _refresh_info())
	btn_volver_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	btn_crear_personaje.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/character_creation/character_creation.tscn"))
	btn_comenzar.pressed.connect(_on_comenzar_pressed)

	_refresh_info()
	UiAnim.stagger_in(%RootVBox, 0.06)
	(btn_comenzar if not btn_comenzar.disabled else btn_crear_personaje).grab_focus.call_deferred()

func _refresh_world_label() -> void:
	%WorldLabel.text = MapData.world_summary() if not GameManager.is_game_active else "Hay una partida en curso: al comenzar se generará un mundo nuevo."

func _on_new_world_pressed() -> void:
	var selected := castle_option.selected
	MapData.new_world()
	_refresh_world_label()
	_populate_castles()
	if selected >= 0 and selected < castle_option.item_count:
		castle_option.select(selected)
	_refresh_info()

func _populate_characters() -> void:
	character_option.clear()
	preview_characters.clear()
	for i in range(available_paths.size()):
		var c := CharacterLoader.load_character(available_paths[i])
		preview_characters.append(c)
		var label := "%s (%s)" % [c.full_name(), c.role_name()] if c != null else available_paths[i].get_file()
		character_option.add_item(label, i)

	# Si se viene de guardar un personaje recién creado, se preselecciona.
	var last_saved := available_paths.find(CreationState.last_saved_path)
	if last_saved != -1:
		character_option.select(last_saved)

	character_option.disabled = available_paths.is_empty()

func _populate_roles() -> void:
	role_option.clear()
	for r in STARTING_ROLES:
		role_option.add_item(Character.role_name_for(r), r)
	_on_character_selected()

func _on_character_selected() -> void:
	# Por defecto se propone el rol con el que se guardó el personaje.
	var c := _selected_preview()
	if c != null:
		var idx := role_option.get_item_index(c.role)
		if idx != -1:
			role_option.select(idx)
	_refresh_info()

func _selected_preview() -> Character:
	var idx := character_option.selected
	if idx < 0 or idx >= preview_characters.size():
		return null
	return preview_characters[idx]

func _populate_castles() -> void:
	castle_option.clear()
	for c: Castle in MapData.castles:
		castle_option.add_item("%s — %s" % [c.castle_name, c.owner_name])
		castle_option.set_item_metadata(castle_option.item_count - 1, c.castle_id)

func _selected_castle() -> Castle:
	if castle_option.selected < 0:
		return null
	return MapData.get_castle_by_id(castle_option.get_item_metadata(castle_option.selected))

func _refresh_info() -> void:
	var castle := _selected_castle()
	if castle != null:
		kingdom_banner.color = KingdomEnums.kingdom_color(castle.kingdom)
		castle_info.text = "%s
Señor: %s

Guarnición: %d soldados
Oro del castillo: %d
Comida: %d" % [
			KingdomEnums.kingdom_name(castle.kingdom), castle.owner_name, castle.garrison_size, castle.gold, castle.food]

	var role := role_option.get_selected_id()
	goal_title.text = VictoryRules.goal_title(role)
	info_label.text = "%s\nDuración orientativa: %s.\n\nDerrota: perder tu último castillo o quedarte sin honor." % [
		VictoryRules.goal_description(role), VictoryRules.goal_estimate(role)]

	if available_paths.is_empty():
		portrait.texture = preload("res://assets/portraits/placeholder_default.png")
		character_info.text = "No hay personajes guardados.

Crea uno y guárdalo para poder comenzar una partida."
		btn_comenzar.disabled = true
		btn_crear_personaje.theme_type_variation = &"PrimaryButton"
		return

	var c := _selected_preview()
	if c == null:
		character_info.text = "No se pudo leer este personaje."
		btn_comenzar.disabled = true
		return
	portrait.texture = c.get_portrait()
	character_info.text = "%s
Comienza como %s

Liderazgo %d
Carisma %d
Estrategia %d
Combate %d
Defensa %d

Honor %d · Oro %d" % [
		c.full_name(), Character.role_name_for(role), c.leadership, c.charisma, c.strategy, c.combat, c.defense, c.honor, c.gold]
	btn_comenzar.disabled = castle == null

func _on_comenzar_pressed() -> void:
	var idx := character_option.selected
	var castle := _selected_castle()
	if idx < 0 or castle == null:
		return

	# Se carga una copia fresca (sin caché) para que los duelos de prueba no contaminen la partida.
	var character := CharacterLoader.load_character(available_paths[idx])
	if character == null:
		info_label.text = "Error al cargar el personaje."
		return
	character.role = role_option.get_selected_id()
	character.current_health = character.max_health
	character.current_stamina = character.max_stamina
	character.current_morale = character.max_morale

	GameManager.start_new_game(character, castle.castle_id)
	GameManager.change_state(GameStateEnums.State.MAP)
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")
