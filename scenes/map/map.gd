extends Node2D

const CastleMarkerScene := preload("res://scenes/map/castle_marker.tscn")
const ArmyMarkerScene := preload("res://scenes/map/army_marker.tscn")

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
@onready var btn_main_menu: Button = %BtnMainMenu
@onready var btn_save_game: Button = %BtnSaveGame
@onready var btn_relations: Button = %BtnRelations
@onready var objective_label: Label = %ObjectiveLabel
@onready var events_label: Label = %EventsLabel

@onready var event_overlay: Control = %EventOverlay
@onready var event_title: Label = %EventTitle
@onready var event_text: Label = %EventText
@onready var event_options: VBoxContainer = %EventOptions
@onready var event_result: Label = %EventResult
@onready var btn_event_close: Button = %BtnEventClose

@onready var army_panel: PanelContainer = %ArmyPanel
@onready var army_title_label: Label = %ArmyTitleLabel
@onready var army_status_label: Label = %ArmyStatusLabel
@onready var army_destination_option: OptionButton = %ArmyDestinationOption
@onready var btn_march_army: Button = %BtnMarchArmy
@onready var btn_start_battle: Button = %BtnStartBattle
@onready var btn_close_army_panel: Button = %BtnCloseArmyPanel

var castle_markers: Dictionary = {}
var selected_castle: Castle
var selected_army: Army
var visible_castle_ids: Array[String] = []

func _ready() -> void:
	camera.setup_bounds(MapData.MAP_WIDTH, MapData.MAP_HEIGHT)
	_style_selected_label()

	visible_castle_ids = _compute_visible_castle_ids()

	_spawn_castles()
	_apply_vision()
	_draw_routes()

	castle_details_panel.visible = false
	btn_enter_castle.pressed.connect(_on_enter_castle_pressed)
	btn_close_panel.pressed.connect(_on_close_panel_pressed)

	btn_advance_turn.pressed.connect(_on_advance_turn_pressed)
	btn_save_game.pressed.connect(_on_save_game_pressed)
	btn_relations.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/relations/relations.tscn"))
	btn_main_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	GameManager.turn_advanced.connect(_on_turn_advanced)
	GameManager.actions_changed.connect(_on_actions_changed)
	_refresh_turn_ui()

	army_panel.visible = false
	btn_march_army.pressed.connect(_on_march_army_pressed)
	btn_start_battle.pressed.connect(_on_start_battle_pressed)
	btn_close_army_panel.pressed.connect(_on_close_army_panel_pressed)
	ArmyData.armies_changed.connect(_on_armies_changed)
	ArmyData.events_changed.connect(_refresh_events)
	_spawn_armies()
	_refresh_events()

	btn_event_close.pressed.connect(_on_event_close_pressed)
	_show_pending_event()
	_check_end_conditions()

func _compute_visible_castle_ids() -> Array[String]:
	# Sin partida activa (p. ej. "Ver Mapa" desde el menú) se muestra todo como vista previa.
	if not GameManager.is_game_active or GameManager.player_character == null:
		return MapVision._all_castle_ids()
	return MapVision.get_visible_castle_ids(GameManager.player_character.role, GameManager.home_castle_id)

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

	if not GameManager.is_game_active:
		btn_enter_castle.disabled = true
		btn_enter_castle.tooltip_text = "Inicia una partida desde el menú principal para entrar a un castillo."
	else:
		btn_enter_castle.disabled = (castle.castle_id != GameManager.home_castle_id)
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
	# Autoguardado mensual (si la partida terminó, se conserva el último guardado previo).
	if GameManager.is_game_active:
		SaveSystem.save_game()

func _on_save_game_pressed() -> void:
	SaveSystem.slots_mode = "save"
	SaveSystem.slots_return_scene = "res://scenes/map/map.tscn"
	get_tree().change_scene_to_file("res://scenes/save_slots/save_slots.tscn")

func _on_turn_advanced(_month: int, _year: int) -> void:
	# Las conquistas (propias o ajenas) pueden cambiar lo que el jugador ve.
	visible_castle_ids = _compute_visible_castle_ids()
	_apply_vision()
	_refresh_turn_ui()
	_spawn_armies()
	_refresh_events()
	_show_pending_event()
	_check_end_conditions()

func _on_actions_changed(_remaining: int, _total: int) -> void:
	_refresh_turn_ui()

func _refresh_turn_ui() -> void:
	if not GameManager.is_game_active:
		date_label.text = "Partida terminada" if not GameManager.game_over_reason.is_empty() else "Sin partida activa"
		objective_label.text = ""
		turn_actions_label.text = ""
		btn_advance_turn.disabled = true
		btn_save_game.disabled = true
		btn_relations.disabled = true
		return

	date_label.text = GameManager.get_date_string()
	if SkillEffects.is_winter(GameManager.current_month):
		date_label.text += " — Invierno"
	turn_actions_label.text = "Acciones: %d / %d" % [GameManager.actions_remaining, GameManager.actions_per_turn]
	# Hay que decidir el evento del mes antes de pasar al siguiente.
	btn_advance_turn.disabled = GameManager.has_pending_event()
	btn_advance_turn.tooltip_text = "Resuelve primero el evento de este mes." if GameManager.has_pending_event() else ""
	btn_save_game.disabled = false
	btn_relations.disabled = false
	var goal := GameManager.evaluate_goal()
	objective_label.text = "Objetivo — %s: %s\n%s" % [
		VictoryRules.goal_title(GameManager.starting_role),
		VictoryRules.goal_description(GameManager.starting_role), goal.progress]
	if GameManager.victory_achieved:
		objective_label.text += "\n¡Objetivo cumplido!"

# --- Ejércitos ---

func _spawn_armies() -> void:
	for child in armies_container.get_children():
		child.queue_free()

	# Agrupa ejércitos por castillo actual para poder separarlos visualmente si hay varios.
	var by_castle: Dictionary = {}
	for a: Army in ArmyData.armies:
		if not _is_army_visible(a):
			continue
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
			marker.setup(a, castle.position_on_map + offset, ArmyData.is_player_army(a))
			marker.army_clicked.connect(_on_army_clicked)

			if a.is_marching():
				var destination := MapData.get_castle_by_id(a.destination_castle_id)
				if destination != null:
					var line := Line2D.new()
					line.points = [castle.position_on_map + offset, destination.position_on_map]
					line.width = 2.0
					line.default_color = Color(0.9, 0.75, 0.15, 0.8) if ArmyData.is_player_army(a) else Color(0.55, 0.2, 0.65, 0.8)
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

	var own := ArmyData.is_player_army(selected_army)
	army_title_label.text = "Ejército de %s (%d soldados)%s" % [
		selected_army.owner_name, selected_army.size, "" if own else " — enemigo"]
	army_status_label.text = selected_army.status_text()

	var can_give_orders := own and selected_army.is_idle()
	army_destination_option.disabled = not can_give_orders
	btn_march_army.disabled = not can_give_orders

	# Atacar con un ejército propio, o defender un castillo propio asediado por la IA.
	var besieged := MapData.get_castle_by_id(selected_army.current_castle_id)
	var can_fight := selected_army.pending_battle and GameManager.is_game_active \
		and (own or ArmyData.is_player_defended(besieged))
	btn_start_battle.visible = can_fight
	btn_start_battle.text = "Iniciar Batalla" if own else "Defender Castillo"

	army_destination_option.clear()
	btn_march_army.tooltip_text = ""
	if can_give_orders:
		var origin := MapData.get_castle_by_id(selected_army.current_castle_id)
		if origin != null:
			var player: Character = GameManager.player_character
			var hops := SkillEffects.max_march_hops(player)
			for dest_id in SkillEffects.march_destinations(origin.castle_id, MapData.castles, hops):
				var dest := MapData.get_castle_by_id(dest_id)
				if dest == null:
					continue
				var far := not origin.connected_castle_ids.has(dest_id)
				army_destination_option.add_item(dest.castle_name + (" (2 saltos, Viajero)" if far else ""))
				army_destination_option.set_item_metadata(army_destination_option.item_count - 1, dest_id)
			if SkillEffects.march_turns(GameManager.current_month, player) > 1:
				btn_march_army.tooltip_text = "Es invierno: la marcha tardará %d turnos (la habilidad Paso Invernal lo evita)." % SkillEffects.WINTER_MARCH_TURNS
			elif SkillEffects.is_winter(GameManager.current_month):
				btn_march_army.tooltip_text = "Es invierno, pero tu Paso Invernal mantiene la marcha en 1 turno."

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

func _on_start_battle_pressed() -> void:
	if selected_army == null or not selected_army.pending_battle:
		return
	ArmyData.active_battle_army = selected_army
	GameManager.change_state(GameStateEnums.State.BATTLE)
	get_tree().change_scene_to_file("res://scenes/battle/battle.tscn")

func _on_close_army_panel_pressed() -> void:
	army_panel.visible = false
	selected_army = null

func _on_armies_changed() -> void:
	_spawn_armies()

func _is_army_visible(a: Army) -> bool:
	if ArmyData.is_player_army(a):
		return true
	return a.current_castle_id in visible_castle_ids or a.destination_castle_id in visible_castle_ids

# --- Noticias del reino ---

func _refresh_events() -> void:
	if not GameManager.game_over_reason.is_empty():
		events_label.text = "FIN DE LA PARTIDA\n%s\nVuelve al menú principal para empezar de nuevo." % GameManager.game_over_reason
		return
	var lines: Array[String] = []
	if not GameManager.last_annual_event.is_empty():
		lines.append("• Año nuevo: " + GameManager.last_annual_event)
	for e: Dictionary in ArmyData.turn_events:
		if e.castle_id in visible_castle_ids:
			lines.append("• " + e.text)
	if lines.is_empty():
		events_label.text = "Noticias del reino: sin novedades a la vista este mes."
	else:
		events_label.text = "Noticias del reino:\n" + "\n".join(lines)

# --- Evento del mes ---

func _show_pending_event() -> void:
	if not GameManager.is_game_active or not GameManager.has_pending_event():
		event_overlay.visible = false
		return
	var e: Dictionary = GameManager.pending_event
	var player: Character = GameManager.player_character
	var castle := MapData.get_castle_by_id(GameManager.home_castle_id)
	event_title.text = e.title
	event_text.text = e.text
	event_result.visible = false
	btn_event_close.visible = false

	for child in event_options.get_children():
		child.queue_free()
	var options: Array = e.options
	for i in range(options.size()):
		var option: Dictionary = options[i]
		var btn := Button.new()
		btn.text = option.label
		if option.has("chance"):
			btn.text += " (%d%% de éxito)" % roundi(EventCatalog.success_chance(option, player) * 100)
		if not EventCatalog.can_choose(option, player, castle):
			btn.disabled = true
			btn.tooltip_text = EventCatalog.requirement_text(option)
		btn.pressed.connect(_on_event_option_pressed.bind(i))
		event_options.add_child(btn)
	event_overlay.visible = true

func _on_event_option_pressed(index: int) -> void:
	var result := GameManager.resolve_pending_event(index)
	for child in event_options.get_children():
		child.queue_free()
	event_result.text = result
	event_result.visible = true
	btn_event_close.visible = true
	_refresh_turn_ui()

func _on_event_close_pressed() -> void:
	event_overlay.visible = false
	for child in event_options.get_children():
		child.queue_free()
	if _check_end_conditions():
		return
	# Un descenso por deshonra cambia lo que el jugador ve.
	visible_castle_ids = _compute_visible_castle_ids()
	_apply_vision()
	_spawn_armies()
	_refresh_events()

# --- Victoria y derrota ---
# Devuelve true si se mostró un anuncio (victoria) o terminó la partida (derrota).

func _check_end_conditions() -> bool:
	if not GameManager.is_game_active or event_overlay.visible:
		return false   # si hay un evento abierto, se revisa al cerrarlo

	if GameManager.check_defeat():
		_refresh_turn_ui()
		_refresh_events()
		return true

	if not GameManager.victory_achieved and GameManager.evaluate_goal().done:
		GameManager.victory_achieved = true
		_show_victory()
		_refresh_turn_ui()
		return true
	return false

func _show_victory() -> void:
	var role := GameManager.starting_role
	event_title.text = "¡Victoria! — %s" % VictoryRules.goal_title(role)
	event_text.text = "%s\n\nHas cumplido tu destino en %s. Tu nombre quedará en las crónicas del reino." % [
		VictoryRules.goal_description(role), GameManager.get_date_string()]
	event_result.visible = false
	btn_event_close.visible = false
	for child in event_options.get_children():
		child.queue_free()

	var btn_continue := Button.new()
	btn_continue.text = "Seguir jugando"
	btn_continue.pressed.connect(func(): event_overlay.visible = false)
	event_options.add_child(btn_continue)

	var btn_menu := Button.new()
	btn_menu.text = "Volver al Menú Principal"
	btn_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	event_options.add_child(btn_menu)
	event_overlay.visible = true
