extends Node2D

const CastleMarkerScene := preload("res://scenes/map/castle_marker.tscn")
const ArmyMarkerScene := preload("res://scenes/map/army_marker.tscn")

# --- Datos de prueba temporales, hasta tener sistema real de asignación de nobleza ---
const TEST_PLAYER_ROLE: int = Character.Role.CABALLERO
const TEST_PLAYER_HOME_CASTLE_ID: String = "carmesi"
# ---------------------------------------------------------------------------------

@onready var camera: Camera2D = $Camera2D
@onready var castles_container: Node2D = $CastlesContainer
@onready var routes_container: Node2D = $RoutesContainer
@onready var armies_container: Node2D = $ArmiesContainer
@onready var selected_castle_label: Label = $UILayer/SelectedCastleLabel

@onready var castle_details_panel: PanelContainer = %CastleDetailsPanel
@onready var details_castle_name: Label = %DetailsCastleName
@onready var details_kingdom: Label = %DetailsKingdom
@onready var details_owner: Label = %DetailsOwner
@onready var details_garrison: Label = %DetailsGarrison
@onready var details_gold: Label = %DetailsGold
@onready var details_food: Label = %DetailsFood
@onready var btn_enter_castle: Button = %BtnEnterCastle
@onready var btn_close_panel: Button = %BtnClosePanel

@onready var date_label: Label = %DateLabel
@onready var turn_actions_label: Label = %TurnActionsLabel
@onready var btn_advance_turn: Button = %BtnAdvanceTurn

@onready var army_panel: PanelContainer = %ArmyPanel
@onready var army_title_label: Label = %ArmyTitleLabel
@onready var army_status_label: Label = %ArmyStatusLabel
@onready var army_destination_option: OptionButton = %ArmyDestinationOption
@onready var btn_march_army: Button = %BtnMarchArmy
@onready var btn_close_army_panel: Button = %BtnCloseArmyPanel

var castle_markers: Dictionary = {}
var selected_castle: Castle
var selected_army: Army
var visible_castle_ids: Array[String] = []

func _ready() -> void:
	camera.setup_bounds(MapData.MAP_WIDTH, MapData.MAP_HEIGHT)
	_style_selected_label()

	visible_castle_ids = MapVision.get_visible_castle_ids(TEST_PLAYER_ROLE, TEST_PLAYER_HOME_CASTLE_ID)

	_spawn_castles()
	_apply_vision()
	_draw_routes()

	castle_details_panel.visible = false
	btn_enter_castle.pressed.connect(_on_enter_castle_pressed)
	btn_close_panel.pressed.connect(_on_close_panel_pressed)

	btn_advance_turn.pressed.connect(_on_advance_turn_pressed)
	GameManager.turn_advanced.connect(_on_turn_advanced)
	GameManager.actions_changed.connect(_on_actions_changed)
	_refresh_turn_ui()

	army_panel.visible = false
	btn_march_army.pressed.connect(_on_march_army_pressed)
	btn_close_army_panel.pressed.connect(_on_close_army_panel_pressed)
	ArmyData.armies_changed.connect(_on_armies_changed)
	_spawn_armies()

func _spawn_castles() -> void:
	for data: Castle in MapData.castles:
		var marker := CastleMarkerScene.instantiate()
		castles_container.add_child(marker)
		marker.setup(data)
		marker.castle_clicked.connect(_on_castle_clicked)
		castle_markers[data.castle_id] = marker

func _apply_vision() -> void:
	for id in castle_markers.keys():
		var marker = castle_markers[id]
		marker.set_visibility_state(id in visible_castle_ids)

func _draw_routes() -> void:
	var drawn_pairs: Dictionary = {}
	for data: Castle in MapData.castles:
		for neighbor_id in data.connected_castle_ids:
			var pair_key := _make_pair_key(data.castle_id, neighbor_id)
			if drawn_pairs.has(pair_key):
				continue
			drawn_pairs[pair_key] = true

			var neighbor := MapData.get_castle_by_id(neighbor_id)
			if neighbor == null:
				continue

			var line := Line2D.new()
			line.points = [data.position_on_map, neighbor.position_on_map]
			line.width = 3.0
			line.default_color = Color(0.6, 0.5, 0.3, 0.8)
			routes_container.add_child(line)

func _make_pair_key(a: String, b: String) -> String:
	var ids := [a, b]
	ids.sort()
	return "%s|%s" % [ids[0], ids[1]]

func _on_castle_clicked(castle: Castle) -> void:
	selected_castle = castle
	var is_visible: bool = castle.castle_id in visible_castle_ids
	_show_castle_details(castle, is_visible)

func _show_castle_details(castle: Castle, is_visible: bool) -> void:
	details_castle_name.text = castle.castle_name

	if is_visible:
		details_kingdom.text = "Reino: %s" % KingdomEnums.kingdom_name(castle.kingdom)
		details_owner.text = "Gobernante: %s" % castle.owner_name
		details_garrison.text = "Guarnición: %d soldados" % castle.garrison_size
		details_gold.text = "Oro: %d" % castle.gold
		details_food.text = "Comida: %d" % castle.food
	else:
		details_kingdom.text = "Reino: Desconocido"
		details_owner.text = "Gobernante: ???"
		details_garrison.text = "Guarnición: ???"
		details_gold.text = "Oro: ???"
		details_food.text = "Comida: ???"

	btn_enter_castle.disabled = (castle.castle_id != TEST_PLAYER_HOME_CASTLE_ID)
	btn_enter_castle.tooltip_text = "" if not btn_enter_castle.disabled else "Solo puedes entrar a tu propio castillo por ahora."

	castle_details_panel.visible = true

func _on_enter_castle_pressed() -> void:
	if selected_castle == null:
		return
	GameManager.current_castle = selected_castle
	# Placeholder: la interfaz específica por rol (ciudad, barracas, etc.) se construye más adelante.
	get_tree().change_scene_to_file("res://scenes/castle_interior/castle_interior.tscn")

func _on_close_panel_pressed() -> void:
	castle_details_panel.visible = false
	selected_castle = null

func _style_selected_label() -> void:
	selected_castle_label.add_theme_color_override("font_color", Color("#D4AF37"))
	selected_castle_label.add_theme_color_override("font_outline_color", Color.BLACK)
	selected_castle_label.add_theme_constant_override("outline_size", 4)

# --- Turno mensual ---

func _on_advance_turn_pressed() -> void:
	GameManager.advance_turn()

func _on_turn_advanced(_month: int, _year: int) -> void:
	_refresh_turn_ui()

func _on_actions_changed(_remaining: int, _total: int) -> void:
	_refresh_turn_ui()

func _refresh_turn_ui() -> void:
	if not GameManager.is_game_active:
		date_label.text = "Sin partida activa"
		turn_actions_label.text = ""
		btn_advance_turn.disabled = true
		return

	date_label.text = GameManager.get_date_string()
	turn_actions_label.text = "Acciones: %d / %d" % [GameManager.actions_remaining, GameManager.actions_per_turn]
	btn_advance_turn.disabled = false

# --- Ejércitos ---

func _spawn_armies() -> void:
	for child in armies_container.get_children():
		child.queue_free()

	# Agrupa ejércitos por castillo actual para poder separarlos visualmente si hay varios.
	var by_castle: Dictionary = {}
	for a: Army in ArmyData.armies:
		if not by_castle.has(a.current_castle_id):
			by_castle[a.current_castle_id] = []
		by_castle[a.current_castle_id].append(a)

	for castle_id in by_castle.keys():
		var castle := MapData.get_castle_by_id(castle_id)
		if castle == null:
			continue
		var group: Array = by_castle[castle_id]
		for i in range(group.size()):
			var a: Army = group[i]
			var offset := Vector2((i - (group.size() - 1) / 2.0) * 40.0, -55.0)
			var marker := ArmyMarkerScene.instantiate()
			armies_container.add_child(marker)
			marker.setup(a, castle.position_on_map + offset)
			marker.army_clicked.connect(_on_army_clicked)

			if a.is_marching():
				var destination := MapData.get_castle_by_id(a.destination_castle_id)
				if destination != null:
					var line := Line2D.new()
					line.points = [castle.position_on_map + offset, destination.position_on_map]
					line.width = 2.0
					line.default_color = Color(0.9, 0.75, 0.15, 0.8)
					armies_container.add_child(line)

	if selected_army != null and army_panel.visible:
		_refresh_army_panel()

func _on_army_clicked(army: Army) -> void:
	selected_army = army
	_refresh_army_panel()

func _refresh_army_panel() -> void:
	if selected_army == null:
		army_panel.visible = false
		return

	army_title_label.text = "Ejército de %s (%d soldados)" % [selected_army.owner_name, selected_army.size]
	army_status_label.text = selected_army.status_text()

	var can_give_orders := selected_army.is_idle()
	army_destination_option.disabled = not can_give_orders
	btn_march_army.disabled = not can_give_orders

	army_destination_option.clear()
	if can_give_orders:
		var origin := MapData.get_castle_by_id(selected_army.current_castle_id)
		if origin != null:
			for neighbor_id in origin.connected_castle_ids:
				var neighbor := MapData.get_castle_by_id(neighbor_id)
				if neighbor != null:
					army_destination_option.add_item(neighbor.castle_name)
					army_destination_option.set_item_metadata(army_destination_option.item_count - 1, neighbor_id)

	army_panel.visible = true

func _on_march_army_pressed() -> void:
	if selected_army == null or army_destination_option.item_count == 0:
		return
	var idx := army_destination_option.selected
	if idx < 0:
		return
	var destination_id: String = army_destination_option.get_item_metadata(idx)
	if ArmyData.set_destination(selected_army, destination_id):
		_refresh_army_panel()

func _on_close_army_panel_pressed() -> void:
	army_panel.visible = false
	selected_army = null

func _on_armies_changed() -> void:
	_spawn_armies()
