extends Node2D

const CastleMarkerScene := preload("res://scenes/map/castle_marker.tscn")

# --- Datos de prueba temporales, hasta tener sistema real de asignación de nobleza ---
const TEST_PLAYER_ROLE: int = Character.Role.CABALLERO
const TEST_PLAYER_HOME_CASTLE_ID: String = "carmesi"
# ---------------------------------------------------------------------------------

@onready var camera: Camera2D = $Camera2D
@onready var castles_container: Node2D = $CastlesContainer
@onready var routes_container: Node2D = $RoutesContainer
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

var castle_markers: Dictionary = {}
var selected_castle: Castle
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
	# Placeholder: la interfaz específica por rol (ciudad, barracas, etc.) se construye más adelante.
	get_tree().change_scene_to_file("res://scenes/castle_interior/castle_interior.tscn")

func _on_close_panel_pressed() -> void:
	castle_details_panel.visible = false
	selected_castle = null

func _style_selected_label() -> void:
	selected_castle_label.add_theme_color_override("font_color", Color("#D4AF37"))
	selected_castle_label.add_theme_color_override("font_outline_color", Color.BLACK)
	selected_castle_label.add_theme_constant_override("outline_size", 4)
