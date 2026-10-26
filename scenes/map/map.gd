extends Node2D

const CastleMarkerScene := preload("res://scenes/map/castle_marker.tscn")
const ArmyMarkerScene := preload("res://scenes/map/army_marker.tscn")
const MissionsPanel = preload("res://scripts/ui/missions_panel.gd")
const GLOSSARY_SCENE := "res://scenes/glossary/glossary.tscn"

# Opciones del menú desplegable de la barra superior.
enum MenuItem { GUARDAR, OPCIONES, GLOSARIO, MENU_PRINCIPAL, CRONICA }
const ChroniclePanel = preload("res://scripts/ui/chronicle_panel.gd")

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
@onready var player_summary_label: Label = %PlayerSummaryLabel
@onready var btn_options: Button = %BtnOptions
@onready var btn_missions: Button = %BtnMissions
@onready var btn_menu: MenuButton = %BtnMenu
@onready var details_banner: ColorRect = %DetailsBanner
@onready var event_panel: PanelContainer = %EventPanel
@onready var event_speaker: HBoxContainer = %EventSpeaker
@onready var event_speaker_portrait: TextureRect = %EventSpeakerPortrait
@onready var event_speaker_name: Label = %EventSpeakerName
@onready var event_speaker_line: Label = %EventSpeakerLine

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
var _advance_pulse: Tween
var _pending_duel_rival: Character   # rival de un reto aceptado en un evento
var _showing_notification := false   # el panel de eventos muestra ahora una noticia importante

func _ready() -> void:
	_add_player_face()
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
	btn_options.pressed.connect(func(): OptionsPanel.open($UILayer))
	btn_missions.pressed.connect(func(): MissionsPanel.open($UILayer))
	_setup_menu()
	MissionData.missions_changed.connect(_refresh_missions_button)
	WorldEvents.notification_added.connect(_show_next_notification)
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
	# De vuelta de un duelo aceptado en un evento: se muestra cómo terminó.
	if not CombatSetup.last_result_text.is_empty() and not event_overlay.visible:
		_show_message("Resultado del duelo", CombatSetup.last_result_text)
		CombatSetup.last_result_text = ""
	_show_next_notification()
	for panel: Control in [event_overlay, castle_details_panel, army_panel]:
		panel.visibility_changed.connect(_focus_default, CONNECT_DEFERRED)
	_focus_default.call_deferred()

# --- Teclado y mando ---
# Siempre hay algo con el foco: la decisión abierta, el panel abierto o «Avanzar Turno».

func _focus_default() -> void:
	var target: Control = null
	if event_overlay.visible:
		for child in event_options.get_children():
			if child is Button and not child.disabled and not child.is_queued_for_deletion():
				target = child
				break
		if target == null and btn_event_close.visible:
			target = btn_event_close
	elif castle_details_panel.visible:
		target = btn_enter_castle if not btn_enter_castle.disabled else btn_close_panel
	elif army_panel.visible:
		target = btn_march_army if not btn_march_army.disabled else btn_close_army_panel
	elif not btn_advance_turn.disabled:
		target = btn_advance_turn
	if target != null and target.is_visible_in_tree():
		target.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event_overlay.visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("map_menu"):
		if castle_details_panel.visible:
			_on_close_panel_pressed()
		elif army_panel.visible:
			_on_close_army_panel_pressed()
		else:
			btn_menu.show_popup()
	elif event.is_action_pressed("end_turn") and not btn_advance_turn.disabled:
		btn_advance_turn.pressed.emit()
	elif event.is_action_pressed("map_relations"):
		btn_relations.pressed.emit()
	elif event.is_action_pressed("map_missions"):
		btn_missions.pressed.emit()
	elif event.is_action_pressed("map_chronicle"):
		ChroniclePanel.open($UILayer, visible_castle_ids)
	elif event.is_action_pressed("map_next_castle"):
		_select_next_castle(-1 if Input.is_key_pressed(KEY_SHIFT) else 1)
	else:
		return
	get_viewport().set_input_as_handled()

# Recorre los castillos que ves (Tab / clic del stick derecho): centra la cámara y abre su ficha.
func _select_next_castle(step: int) -> void:
	var ids: Array[String] = visible_castle_ids.duplicate()
	ids.sort()
	if ids.is_empty():
		return
	var current := ids.find(selected_castle.castle_id) if selected_castle != null else -1
	var next_castle := MapData.get_castle_by_id(ids[(current + step + ids.size()) % ids.size()])
	if next_castle == null:
		return
	camera.position = next_castle.position_on_map
	_on_castle_clicked(next_castle)

func _setup_menu() -> void:
	var popup := btn_menu.get_popup()
	popup.add_item("Crónica completa  [C]", MenuItem.CRONICA)
	popup.add_item("Relaciones  [R] · Encargos [E] · Avanzar turno [T] · Castillos [Tab]", -1)
	popup.set_item_disabled(popup.item_count - 1, true)
	popup.add_item("Guardar partida", MenuItem.GUARDAR)
	popup.add_item("Opciones", MenuItem.OPCIONES)
	popup.add_item("Glosario", MenuItem.GLOSARIO)
	popup.add_separator()
	popup.add_item("Menú principal", MenuItem.MENU_PRINCIPAL)
	popup.id_pressed.connect(_on_menu_item)
	_refresh_missions_button()

func _on_menu_item(id: int) -> void:
	match id:
		MenuItem.CRONICA:
			ChroniclePanel.open($UILayer, visible_castle_ids)
		MenuItem.GUARDAR:
			_on_save_game_pressed()
		MenuItem.OPCIONES:
			OptionsPanel.open($UILayer)
		MenuItem.GLOSARIO:
			if ResourceLoader.exists(GLOSSARY_SCENE):
				get_tree().change_scene_to_file(GLOSSARY_SCENE)
		MenuItem.MENU_PRINCIPAL:
			get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

func _refresh_missions_button() -> void:
	var n: int = MissionData.active.size()
	btn_missions.text = "Encargos (%d)" % n if n > 0 else "Encargos"

# --- Noticias importantes (WorldEvents): una a una, cuando no hay otra ventana abierta ---

func _show_next_notification() -> void:
	# Primero se decide el evento del mes; las noticias esperan a que se cierre.
	if event_overlay.visible or GameManager.has_pending_event() or not WorldEvents.has_notifications():
		return
	var n: Dictionary = WorldEvents.pop_notification()
	_showing_notification = true
	_show_message(n.title, n.text)
	var remaining: int = WorldEvents.notifications.size()
	btn_event_close.text = "Entendido" if remaining == 0 else "Siguiente noticia (%d más)" % remaining

func _show_message(title: String, text: String) -> void:
	event_title.text = title
	event_text.text = text
	event_speaker.visible = false
	event_result.visible = false
	for child in event_options.get_children():
		child.queue_free()
	btn_event_close.visible = true
	event_overlay.visible = true
	UiAnim.fade_in(event_panel, 0.25)

# Tu cara arriba a la izquierda; al pulsarla se ve el retrato completo.
func _add_player_face() -> void:
	var player: Character = GameManager.player_character
	if player == null:
		return
	var face := FaceIcon.make(player, 52, Color("d4af5a"))
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bar: HBoxContainer = $UILayer/TopBar/TopHBox
	bar.add_child(face)
	bar.move_child(face, 0)

func _compute_visible_castle_ids() -> Array[String]:
	# Sin partida activa (p. ej. "Ver Mapa" desde el menú) se muestra todo como vista previa.
	if not GameManager.is_game_active or GameManager.player_character == null:
		return MapVision._all_castle_ids()
	var player: Character = GameManager.player_character
	return MapVision.get_visible_castle_ids(player.role, GameManager.home_castle_id, SkillEffects.vision_bonus(player))

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
	details_banner.color = KingdomEnums.kingdom_color(castle.kingdom) if is_visible else Color(0.3, 0.3, 0.3)

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
	UiAnim.fade_in(castle_details_panel, 0.15)

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
	_refresh_missions_button()
	_show_next_notification()

func _on_actions_changed(_remaining: int, _total: int) -> void:
	_refresh_turn_ui()

func _refresh_turn_ui() -> void:
	if not GameManager.is_game_active:
		date_label.text = "Partida terminada" if not GameManager.game_over_reason.is_empty() else "Sin partida activa"
		objective_label.text = ""
		turn_actions_label.text = ""
		player_summary_label.text = ""
		btn_advance_turn.disabled = true
		btn_save_game.disabled = true
		btn_relations.disabled = true
		btn_missions.disabled = true
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
	objective_label.text = "%s — %s\n%s" % [
		VictoryRules.goal_title(GameManager.starting_role),
		VictoryRules.goal_description(GameManager.starting_role), goal.progress]
	if GameManager.victory_achieved:
		objective_label.text += "\n¡Objetivo cumplido!"
	var p: Character = GameManager.player_character
	player_summary_label.text = "%s · %s   |   Oro %d  ·  Honor %d  ·  Fama %d" % [p.full_name(), p.role_name(), p.gold, p.honor, p.fame]
	player_summary_label.tooltip_text = "Vida %d/%d · Duelos %d ganados / %d perdidos" % [
		p.current_health, p.max_health, p.duels_won, p.duels_lost]
	_update_advance_pulse()

# Sin acciones por gastar, el botón de avanzar turno late para indicar el siguiente paso.
func _update_advance_pulse() -> void:
	var should_pulse := GameManager.is_game_active and GameManager.actions_remaining <= 0 and not GameManager.has_pending_event()
	if should_pulse and _advance_pulse == null:
		_advance_pulse = UiAnim.pulse(btn_advance_turn)
	elif not should_pulse and _advance_pulse != null:
		_advance_pulse.kill()
		_advance_pulse = null
		btn_advance_turn.modulate = Color.WHITE

# --- Ejércitos ---

# Botones extra del panel de ejército (se crean al abrirlo por primera vez).
var _btn_merge_armies: Button
var _btn_garrison_army: Button

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
	if own and selected_army.pending_battle and besieged != null:
		army_status_label.text += "\nAsedio: cada mes la guarnición cae un %d%% (pagas %d de oro). Para asaltar conviene ≈1,5× sus %d defensores." % [
			roundi(ArmyData.SIEGE_ATTRITION * 100), ceili(selected_army.size / float(ArmyData.SIEGE_UPKEEP_PER_SOLDIERS)), besieged.garrison_size]
	_refresh_army_extra_buttons(own)

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

# Reunir ejércitos propios parados en el mismo castillo, o devolverlos a la guarnición.
func _refresh_army_extra_buttons(own: bool) -> void:
	if _btn_merge_armies == null:
		_btn_merge_armies = Button.new()
		_btn_merge_armies.text = "Reunir ejércitos"
		_btn_merge_armies.tooltip_text = "Junta en uno solo todos tus ejércitos parados en este castillo."
		_btn_merge_armies.pressed.connect(_on_merge_armies_pressed)
		_btn_garrison_army = Button.new()
		_btn_garrison_army.text = "Volver a la guarnición"
		_btn_garrison_army.theme_type_variation = &"FlatButton"
		_btn_garrison_army.tooltip_text = "Las tropas vuelven a defender las murallas de este castillo."
		_btn_garrison_army.pressed.connect(_on_garrison_army_pressed)
		var box := btn_close_army_panel.get_parent()
		box.add_child(_btn_merge_armies)
		box.add_child(_btn_garrison_army)
		box.move_child(_btn_merge_armies, btn_close_army_panel.get_index())
		box.move_child(_btn_garrison_army, btn_close_army_panel.get_index())
	var idle_own := own and selected_army.is_idle()
	_btn_merge_armies.visible = idle_own and ArmyData.idle_player_armies_at(selected_army.current_castle_id).size() > 1
	var here := MapData.get_castle_by_id(selected_army.current_castle_id)
	_btn_garrison_army.visible = idle_own and here != null and here.kingdom == selected_army.kingdom

func _on_merge_armies_pressed() -> void:
	if selected_army == null:
		return
	selected_army = ArmyData.merge_armies(selected_army.current_castle_id)
	_refresh_army_panel()

func _on_garrison_army_pressed() -> void:
	if selected_army != null and ArmyData.garrison_army(selected_army):
		_on_close_army_panel_pressed()

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
		events_label.text = "Sin novedades a la vista este mes."
	else:
		events_label.text = "\n".join(lines)

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
	# Eventos con protagonista: su retrato y lo que dice, según su personalidad.
	var speaker: Relationship = RelationsData.get_relation(e.get("speaker", ""))
	event_speaker.visible = speaker != null and speaker.character != null
	if event_speaker.visible:
		event_speaker_portrait.texture = speaker.character.get_face()
		event_speaker_name.text = "%s · %s" % [speaker.person_name, DialogueCatalog.personality_name(speaker.character.personality)]
		event_speaker_line.text = "«%s»" % e.get("quote", "") if not str(e.get("quote", "")).is_empty() else ""

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
	UiAnim.fade_in(event_panel, 0.25)
	_focus_default.call_deferred()

func _on_event_option_pressed(index: int) -> void:
	var e: Dictionary = GameManager.pending_event
	var target: Relationship = RelationsData.get_relation(e.get("target", e.get("speaker", "")))
	var duel_rival: Relationship = RelationsData.get_relation(e.get("duel_with", e.get("speaker", "")))
	var starts_duel: bool = e.options[index].get("start_duel", false)
	var chosen_label: String = e.options[index].get("label", "")
	var result := GameManager.resolve_pending_event(index, target)
	# Tus decisiones también quedan en la crónica.
	WorldEvents.record("%s: %s. %s" % [e.get("title", "Suceso"), chosen_label, result.get_slice("\n", 0)], "", true)
	for child in event_options.get_children():
		child.queue_free()
	event_result.text = result
	event_result.visible = true
	btn_event_close.visible = true
	_refresh_turn_ui()
	_focus_default.call_deferred()
	# Aceptar un reto lleva directamente al duelo; al terminar se vuelve al mapa.
	_pending_duel_rival = duel_rival.character if starts_duel and duel_rival != null else null
	if _pending_duel_rival != null:
		btn_event_close.text = "¡Al duelo!"

func _on_event_close_pressed() -> void:
	event_overlay.visible = false
	btn_event_close.text = "Continuar"
	if _showing_notification:
		_showing_notification = false
		_show_next_notification()
		return
	if _pending_duel_rival != null:
		var rival := _pending_duel_rival
		_pending_duel_rival = null
		rival.current_health = rival.max_health
		rival.current_stamina = rival.max_stamina
		rival.current_morale = rival.max_morale
		CombatSetup.start_campaign_duel(GameManager.player_character, rival)
		CombatSetup.return_scene = "res://scenes/map/map.tscn"
		get_tree().change_scene_to_file("res://scenes/combat/combat.tscn")
		return
	for child in event_options.get_children():
		child.queue_free()
	if _check_end_conditions():
		return
	# Un descenso por deshonra cambia lo que el jugador ve.
	visible_castle_ids = _compute_visible_castle_ids()
	_apply_vision()
	_spawn_armies()
	_refresh_events()
	_refresh_turn_ui()
	_show_next_notification()

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
	btn_continue.theme_type_variation = &"PrimaryButton"
	btn_continue.pressed.connect(func(): event_overlay.visible = false)
	event_options.add_child(btn_continue)

	var btn_menu := Button.new()
	btn_menu.text = "Volver al Menú Principal"
	btn_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	event_options.add_child(btn_menu)
	event_overlay.visible = true
