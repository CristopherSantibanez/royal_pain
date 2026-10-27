extends Control

const ShopPanel = preload("res://scripts/ui/shop_panel.gd")

const MissionsPanel = preload("res://scripts/ui/missions_panel.gd")
const WorksPanel = preload("res://scripts/ui/works_panel.gd")
const BuildingCatalog = preload("res://scripts/resources/building_catalog.gd")
const AudiencePanel = preload("res://scripts/ui/audience_panel.gd")
const ContractsPanel = preload("res://scripts/ui/contracts_panel.gd")
const XpRules = preload("res://scripts/resources/xp_rules.gd")

# Viaje (ver TravelData): en tu castillo, todo; desde lejos, solo lo que se gestiona por carta
# (cuesta TravelData.REMOTE_EXTRA_ACTIONS más); en castillos ajenos, las acciones del lugar.
# Una acción de rol puede marcarse "remote_ok": true (se puede por carta) o "anywhere": true (también en castillos ajenos).
const REMOTE_OK_PREFIXES := ["Recaudar", "Gobernar", "Imponer Impuestos", "Promulgar", "✓ Vigente",
	"Diplomacia", "Negociar Alianza", "Movilizar", "Reclutar Ejército Real"]

@onready var title_label: Label = %TitleLabel
@onready var role_label: Label = %RoleLabel
@onready var honor_label: Label = %HonorLabel
@onready var gold_label: Label = %GoldLabel
@onready var duels_label: Label = %DuelsLabel
@onready var progression_label: Label = %ProgressionLabel
@onready var btn_ascend: Button = %BtnAscend
@onready var btn_volver_mapa: Button = %BtnVolverMapa
@onready var castle_info_label: Label = %CastleInfoLabel
@onready var actions_label: Label = %ActionsLabel
@onready var role_actions_list: VBoxContainer = %RoleActionsList
@onready var action_feedback_label: Label = %ActionFeedbackLabel
@onready var feedback_panel: PanelContainer = %FeedbackPanel
@onready var portrait: TextureRect = %Portrait
@onready var honor_bar: ProgressBar = %HonorBar
@onready var castle_banner: ColorRect = %CastleBanner
@onready var castle_stats_label: Label = %CastleStatsLabel

var character: Character
var castle: Castle

# --- Constantes de balance de acciones (ajustables sin tocar la lógica) ---
const TIERRA_GOLD_GAIN := 20
const CAZA_GOLD := 35
const CAZA_BASE_CHANCE := 0.55          # + (Estrategia - 5) * 3%
const CAZA_HONOR_PENALTY := 5
const ENTRENAR_COMBAT_GAIN := 1
const ENTRENAR_COST := 15
const ENTRENAR_CAP := 18                # cuanto más cerca de este Combate, más difícil mejorar
const MANDO_COST := 40
const MANDO_CAP := 20                   # prob. de +1 Liderazgo = (MANDO_CAP - Liderazgo) / MANDO_DIVISOR
const MANDO_DIVISOR := 12.0
const MEJORAR_TIERRAS_COST := 100
const MEJORAR_TIERRAS_RENT := 10        # oro al mes, para siempre
const MEJORAR_TIERRAS_MAX_RENT := 50
const MEJORAR_TIERRAS_CASTLE_FOOD := 20
const RECAUDAR_BASE := 35
const PLAYER_TAX_SHARE := 0.6           # lo recaudado se reparte: 60% para ti, 40% para el castillo
const MERCENARY_COST := 5               # oro por soldado
const MERCENARY_MAX := 40               # soldados por contrato
const MERCENARY_MIN := 10
const DESERT_HONOR_THRESHOLD := 30
const MILICIA_GARRISON_GAIN := 10
const MILICIA_COST := 60
const REGENTE_TAX_PER_CASTLE := 25
const MOBILIZE_MIN_GARRISON := 40
const MOBILIZE_FRACTION := 0.4
const MOBILIZE_FRACTION_REGENTE := 0.6
const MOBILIZE_FRACTION_DUQUE := 0.5
const DUCADO_BASE_PER_CASTLE := 30
const DUCADO_LEADERSHIP_FACTOR := 2
const MOBILIZE_HINT := "Para tomar un castillo amurallado hace falta ≈1,5 veces su guarnición: reúne ejércitos, contrata mercenarios o asédialo antes de asaltar."
const DUEL_TOOLTIP := "Retas a un rival de tu rango. Ganar da honor, oro y cuenta para ascender; perder resta honor."
const MEDICO_COST := 30
const MEDICO_HEAL := 50

func _ready() -> void:
	character = GameManager.player_character
	castle = GameManager.current_castle
	btn_volver_mapa.pressed.connect(_on_volver_mapa_pressed)
	%BtnGente.pressed.connect(func():
		RelationsData.set("requested_tab", "lugar")
		get_tree().change_scene_to_file("res://scenes/relations/relations.tscn"))
	%BtnEncargos.pressed.connect(func(): MissionsPanel.open(self))
	%BtnArmeria.pressed.connect(func():
		var shop: Control = ShopPanel.open(self)
		shop.purchased.connect(_refresh_ui))
	MissionData.missions_changed.connect(_refresh_missions_button)
	_refresh_missions_button()
	if castle != null and not _is_foreign():
		var btn_obras := Button.new()
		btn_obras.name = "BtnObras"
		btn_obras.text = "Obras"
		btn_obras.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn_obras.tooltip_text = "Edificios del castillo: herrería, establos, murallas, mercado, capilla y cuartel. Solo la nobleza ordena obras."
		%BtnEncargos.add_sibling(btn_obras)
		btn_obras.pressed.connect(func():
			var works: Control = WorksPanel.open(self, castle)
			works.construction_started.connect(func():
				_refresh_ui()
				_build_role_actions()))

	if character == null:
		title_label.text = "No hay un personaje de jugador activo."
		role_label.text = ""
		honor_label.text = ""
		gold_label.text = ""
		duels_label.text = ""
		actions_label.text = ""
		progression_label.text = "Inicia una partida desde el menú principal para ver tu progresión."
		castle_info_label.text = ""
		btn_ascend.disabled = true
		return

	GameManager.refresh_actions_for_role_change()
	btn_ascend.pressed.connect(_on_ascend_pressed)
	_refresh_ui()
	_build_role_actions()
	UiAnim.stagger_in(%RootVBox, 0.08)
	# Teclado y mando: el foco empieza en la primera acción disponible.
	(func(): if UiAnim.focus_first(role_actions_list) == null: btn_volver_mapa.grab_focus()).call_deferred()

	# Al volver de un duelo de campaña se muestra su resultado.
	if not CombatSetup.last_result_text.is_empty():
		_show_feedback(CombatSetup.last_result_text)
		CombatSetup.last_result_text = ""

func _refresh_missions_button() -> void:
	var n: int = MissionData.active.size()
	%BtnEncargos.text = "Encargos (%d)" % n if n > 0 else "Encargos"
	_refresh_ui_if_ready()

func _refresh_ui_if_ready() -> void:
	if character != null and is_node_ready():
		_refresh_ui()

func _refresh_ui() -> void:
	title_label.text = castle.castle_name if castle != null else "Interior del Castillo"
	title_label.tooltip_text = title_label.text   # el título se recorta con «…» si no cabe junto a los botones
	portrait.texture = character.get_portrait()
	role_label.text = "%s\n%s · Nivel %d (%d/%d exp.) · %s" % [character.full_name(), character.role_title(),
		character.level, character.xp, character.xp_to_next(), character.health_text()]
	honor_label.text = "Honor %d" % character.honor
	honor_bar.value = character.honor
	if not honor_bar.has_theme_stylebox_override("fill"):
		var gold_fill := StyleBoxFlat.new()
		gold_fill.bg_color = Color("c9a24a")
		gold_fill.set_corner_radius_all(3)
		honor_bar.add_theme_stylebox_override("fill", gold_fill)
	gold_label.text = "Oro: %d · Fama: %d" % [character.gold, character.fame]
	duels_label.text = "Duelos: %d ganados / %d perdidos" % [character.duels_won, character.duels_lost]
	if character.is_mercenary():
		duels_label.text += "\nCompañía: %d (soldada %d/mes)\nContratos: %d · Infamia: %d" % [
			MissionData.company_size(), MissionData.company_pay(), MissionData.contracts_done, MissionData.infamy]
	actions_label.text = "Acciones: %d / %d" % [GameManager.actions_remaining, GameManager.actions_per_turn]

	if castle != null:
		var realm := KingdomEnums.kingdom_name(castle.kingdom)
		castle_info_label.text = "Señor: %s" % castle.owner_name
		if realm != castle.castle_name:   # castillo conquistado: el reino ya no es el del nombre
			castle_info_label.text = "%s · %s" % [realm, castle_info_label.text]
		if _is_remote():
			castle_info_label.text += " · ✉ desde lejos"
		elif _is_foreign():
			castle_info_label.text += " · de visita"
		castle_banner.color = KingdomEnums.kingdom_color(castle.kingdom)
		castle_stats_label.text = "Tesoro del castillo: %d\nComida: %d\nGuarnición: %d soldados" % [castle.gold, castle.food, castle.garrison_size]
		var built: Array[String] = []
		for id: String in BuildingCatalog.ORDER:
			if castle.building_level(id) > 0:
				built.append("%s %d" % [BuildingCatalog.building_name(id), castle.building_level(id)])
		if not built.is_empty():
			castle_stats_label.text += "\nEdificios: " + ", ".join(built)
		if castle.is_building():
			castle_stats_label.text += "\nEn obras: %s (%d m.)" % [BuildingCatalog.building_name(castle.construction_id), castle.construction_months_left]
	else:
		castle_info_label.text = "No se pudo determinar el castillo actual."
		castle_stats_label.text = ""

	var check := RoleProgression.check_ascension(character, MissionData.progression_context())

	if check.next_role == -1 and character.role == Character.Role.CONDOTIERO:
		progression_label.text = "La cima del camino mercenario. Para ennoblecerte, jura lealtad a un señor en audiencia (pasarás a Nobleza Baja) o toma castillos a tu nombre."
		btn_ascend.disabled = true
	elif check.next_role == -1:
		progression_label.text = "No hay ascenso disponible desde este rol todavía."
		btn_ascend.disabled = true
	elif check.can_ascend:
		progression_label.text = "¡Cumples los requisitos para ascender a %s!" % Character.role_name_for(check.next_role)
		btn_ascend.disabled = false
	else:
		progression_label.text = "Para ascender a %s: %s" % [Character.role_name_for(check.next_role), check.reason]
		btn_ascend.disabled = true

func _on_ascend_pressed() -> void:
	var succession := MissionData.progression_context()
	var check := RoleProgression.check_ascension(character, succession)
	if RoleProgression.ascend(character, succession):
		if character.role == Character.Role.REGENTE:
			_show_feedback(RelationsData.become_regent(check.get("by_marriage", false)))
		elif character.role == Character.Role.CAPITAN:
			var company: Army = MissionData.raise_company(castle)
			_show_feedback("Levantas tu propia compañía: ahora eres %s y %d soldados siguen tu estandarte (cobran %d de oro al mes entre todos)." % [
				character.role_title(), company.size if company != null else 0, MissionData.company_pay()])
		else:
			_show_feedback("Asciendes a %s." % character.role_title())
		GameManager.refresh_actions_for_role_change()
		_refresh_ui()
		_build_role_actions()

func _on_volver_mapa_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")

# --- Acciones específicas por rol ---
# Cada entrada: {label, tooltip, locked (bool), callback (Callable, solo si no está locked)}

func _build_role_actions() -> void:
	for child in role_actions_list.get_children():
		role_actions_list.remove_child(child)   # fuera ya: action_buttons() no debe ver la rejilla vieja
		child.queue_free()

	var actions: Array[Dictionary] = _get_actions_for_role(character.role)
	actions.append_array(_common_actions())
	actions = _actions_for_location(actions)
	var out_of_actions := not GameManager.has_actions_remaining()
	var grid := GridContainer.new()
	grid.columns = ACTION_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	role_actions_list.add_child(grid)

	for action in actions:
		var btn := Button.new()
		btn.text = action.label if not action.locked else "%s (Próximamente)" % action.label
		btn.tooltip_text = action.tooltip
		btn.custom_minimum_size = Vector2(230, 38)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var cost: int = 1 + int(action.get("extra_cost", 0))

		if action.locked:
			btn.disabled = true
		elif action.get("unavailable", "") != "":
			# Acción existente pero no disponible ahora (herido, fuera de temporada...).
			btn.disabled = true
			btn.tooltip_text += "\n" + action.unavailable
		elif action.get("no_cost", false):
			# Acciones de navegación: no gastan acción aquí (la gastan las gestiones que se hagan allá).
			btn.pressed.connect(action.callback)
		else:
			btn.disabled = GameManager.actions_remaining < cost
			if out_of_actions:
				btn.tooltip_text += "\n(Sin acciones disponibles este turno — avanza el turno desde el mapa)"
			elif btn.disabled:
				btn.tooltip_text += "\n(Por carta cuesta %d acciones y te quedan %d)" % [cost, GameManager.actions_remaining]
			btn.pressed.connect(_make_action_handler(action.callback, cost))

		# Botones en rejilla; la explicación se ve al pasar el ratón o el foco (y en el glosario).
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.mouse_entered.connect(_show_action_hint.bind(btn))
		btn.focus_entered.connect(_show_action_hint.bind(btn))
		grid.add_child(btn)

	_action_hint = Label.new()
	_action_hint.theme_type_variation = &"MutedLabel"
	_action_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action_hint.add_theme_font_size_override("font_size", 15)
	_action_hint.custom_minimum_size = Vector2(0, ACTION_HINT_HEIGHT)
	role_actions_list.add_child(_action_hint)

const ACTION_COLUMNS := 2
const ACTION_HINT_HEIGHT := 44   # dos líneas: evita que la rejilla salte al cambiar de botón
var _action_hint: Label

## Botones de acción del castillo (en el orden en que se muestran).
func action_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for child in role_actions_list.get_children():
		if child is GridContainer:
			for b in child.get_children():
				out.append(b as Button)
	return out

func _show_action_hint(btn: Button) -> void:
	if is_instance_valid(_action_hint):
		_action_hint.text = btn.tooltip_text

func _make_action_handler(callback: Callable, cost: int = 1) -> Callable:
	return func() -> void:
		if GameManager.actions_remaining < cost or not GameManager.consume_action():
			_show_feedback("No te quedan acciones disponibles este turno.")
			return
		for i in cost - 1:
			GameManager.consume_action()
		callback.call()
		_build_role_actions()   # refresca qué botones quedan habilitados tras gastar la acción

# --- Dónde estás (ver TravelData) ---

## Castillo ajeno: ni es tu castillo de origen ni es tuyo.
func _is_foreign() -> bool:
	var player: Character = GameManager.player_character
	return castle != null and player != null and castle.castle_id != GameManager.home_castle_id \
		and castle.owner_name != player.full_name()

## Tu castillo de origen, gestionado desde otro lugar.
func _is_remote() -> bool:
	return GameManager.player_character != null and TravelData.is_remote(castle)

func _is_remote_ok(action: Dictionary) -> bool:
	if action.get("needs_presence", false):
		return false
	if action.get("remote_ok", false) or action.get("no_cost", false):
		return true
	var label: String = action.get("label", "")
	return REMOTE_OK_PREFIXES.any(func(p: String) -> bool: return label.begins_with(p))

## Filtra las acciones de rol según dónde estés: de visita solo las del lugar; desde lejos, por carta y más caras.
func _actions_for_location(role_actions: Array[Dictionary]) -> Array[Dictionary]:
	# Tus prisioneros y siervos se gestionan desde Relaciones (pestaña Prisioneros).
	var held: int = CaptureData.player_prisoners().size() + CaptureData.serfs.size()
	if held > 0 and not _is_foreign():
		role_actions = role_actions.duplicate()
		role_actions.append({"label": "Prisioneros (%d)" % held, "tooltip": "Tus presos y siervos.", "locked": false,
			"no_cost": true, "callback": func():
				RelationsData.requested_tab = "presos"
				get_tree().change_scene_to_file("res://scenes/relations/relations.tscn")})
	if _is_foreign():
		var result := _foreign_actions()
		for a: Dictionary in role_actions:
			if a.get("anywhere", false):
				result.append(a)
		return result
	if not _is_remote():
		return role_actions
	var result: Array[Dictionary] = []
	for a: Dictionary in role_actions:
		var copy := a.duplicate()
		if a.get("locked", false) or a.get("anywhere", false):
			pass
		elif _is_remote_ok(a):
			if not a.get("no_cost", false):
				copy.extra_cost = TravelData.REMOTE_EXTRA_ACTIONS
				copy.label = "%s ✉" % a.label
				copy.tooltip = "%s\nPor carta: cuesta %d acciones." % [a.tooltip, 1 + TravelData.REMOTE_EXTRA_ACTIONS]
		elif str(a.get("unavailable", "")).is_empty():
			copy.unavailable = "Tienes que estar en %s: viaja de vuelta desde el mapa." % castle.castle_name
		result.append(copy)
	return result

# Acciones en un castillo ajeno: torneo local, audiencia con el señor, jurar lealtad y batirte.
func _foreign_actions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var audience_reason := TravelData.audience_blocker(castle)
	if audience_reason.is_empty() and not GameManager.has_actions_remaining():
		audience_reason = "No te quedan acciones este mes."
	result.append({"label": "Pedir Audiencia", "tooltip": "%s te recibe en su salón: presentar respetos, pedir noticias o un encargo, o jurarle lealtad. Gasta 1 acción." % castle.owner_name,
		"unavailable": audience_reason, "locked": false, "no_cost": true, "callback": _action_audiencia})
	if character.role == Character.Role.CAMPESINO:
		var settle_reason := TravelData.fealty_blocker(castle)
		if settle_reason.is_empty() and not GameManager.has_actions_remaining():
			settle_reason = "No te quedan acciones este mes."
		result.append({"label": "Establecerte Aquí", "tooltip": "Migras a %s: %s será tu nuevo señor y este castillo tu hogar. Gasta 1 acción." % [
			KingdomEnums.kingdom_name(castle.kingdom), castle.owner_name],
			"unavailable": settle_reason, "locked": false, "no_cost": true, "callback": _action_jurar_lealtad})
	if character.can_fight_duels():
		result.append({"label": "Torneo de %s (%d oro)" % [castle.castle_name, CombatSetup.TOURNAMENT_ENTRY_FEE],
			"tooltip": "El torneo local: %d duelos contra los campeones de la zona. Uno por castillo y año, de abril a septiembre." % CombatSetup.TOURNAMENT_ROUNDS,
			"unavailable": TravelData.local_tournament_blocker(castle), "locked": false, "callback": _action_torneo_local})
		result.append({"label": "Retar a Duelo", "tooltip": DUEL_TOOLTIP, "unavailable": _duel_unavailable_reason(),
			"locked": false, "callback": _action_retar_duelo})
	return result

func _action_audiencia() -> void:
	var r := TravelData.request_audience(castle)
	if not r.ok:
		_show_feedback(r.text)
		return
	var panel: Control = AudiencePanel.open(self, castle)
	panel.tree_exited.connect(func():
		if is_inside_tree():
			_show_feedback(str(panel.get_meta("result", r.text)))
			_refresh_ui()
			_build_role_actions())
	_refresh_ui()

func _action_jurar_lealtad() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Jurar lealtad"
	dialog.dialog_text = TravelData.fealty_preview(castle) + "\n\nGasta 1 acción."
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(520, 0)
	dialog.ok_button_text = "Jurar"
	dialog.cancel_button_text = "Pensarlo mejor"
	add_child(dialog)
	dialog.confirmed.connect(func():
		if not GameManager.consume_action():
			_show_feedback("No te quedan acciones este mes.")
			return
		var r := TravelData.swear_fealty(castle)
		_show_feedback(r.text)
		_refresh_ui()
		_build_role_actions())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _action_torneo_local() -> void:
	var reason := TravelData.local_tournament_blocker(castle)
	if reason != "":
		_show_feedback(reason)
		return
	character.gold -= CombatSetup.TOURNAMENT_ENTRY_FEE
	TravelData.mark_local_tournament(castle)
	var opponents := RelationsData.tournament_opponents(character, CombatSetup.TOURNAMENT_ROUNDS, CombatSetup.TOURNAMENT_STAT_STEP)
	CombatSetup.start_tournament(character, opponents)
	get_tree().change_scene_to_file("res://scenes/combat/combat.tscn")

func _get_actions_for_role(role: int) -> Array[Dictionary]:
	match role:
		Character.Role.CAMPESINO:
			return [
				{"label": "Trabajar la Tierra", "tooltip": "Ganas %d de oro trabajando en tus tierras." % TIERRA_GOLD_GAIN,
					"locked": false, "callback": _action_trabajar_tierra},
				{"label": "Cazar Furtivo", "tooltip": "%d%% de cazar en el bosque del señor y vender la pieza por %d de oro; si te pillan, pierdes %d de honor." % [
					roundi(_caza_chance() * 100), CAZA_GOLD, CAZA_HONOR_PENALTY],
					"locked": false, "callback": _action_cazar},
				{"label": "Migrar a Otro Reino", "tooltip": "Te mudas a otro reino en busca de mejor fortuna: viaja desde el mapa a un castillo de otro reino y, allí, elige «Establecerte Aquí».",
					"locked": false, "no_cost": true, "callback": _action_migrar},
			]
		Character.Role.SOLDADO:
			return [
				{"label": "Retar a Duelo", "tooltip": DUEL_TOOLTIP, "unavailable": _duel_unavailable_reason(),
					"locked": false, "callback": _action_retar_duelo},
				_entrenar_action(),
				{"label": "Desertar", "tooltip": "Abandonas tu puesto y vuelves a ser Campesino.",
					"unavailable": _desertar_unavailable_reason(),
					"locked": false, "callback": _action_desertar},
				_abandon_liege_action(),
			]
		Character.Role.CABALLERO:
			return [
				{"label": "Retar a Duelo", "tooltip": DUEL_TOOLTIP, "unavailable": _duel_unavailable_reason(),
					"locked": false, "callback": _action_retar_duelo},
				_tournament_action(),
				_mejorar_tierras_action(),
				_entrenar_action(),
				_mobilize_action(MOBILIZE_FRACTION),
				_mercenarios_action(),
				_abandon_liege_action(),
			]
		Character.Role.NOBLEZA_BAJA:
			return [
				{"label": "Retar a Duelo", "tooltip": DUEL_TOOLTIP, "unavailable": _duel_unavailable_reason(),
					"locked": false, "callback": _action_retar_duelo},
				_tournament_action(),
				{"label": "Recaudar Impuestos", "tooltip": "Recolectas impuestos de tu condado, proporcional a tu Liderazgo (%d%% para ti, el resto para el castillo)." % roundi(PLAYER_TAX_SHARE * 100),
					"locked": false, "callback": _action_recaudar},
				{"label": "Reclutar Milicia", "tooltip": "Gastas %d de oro del castillo para sumar %d soldados a la guarnición." % [_milicia_cost(), _milicia_gain()],
					"locked": false, "callback": _action_reclutar_milicia},
				{"label": "Ejercer el Mando (%d oro)" % MANDO_COST,
					"tooltip": "Diriges maniobras y consejos de guerra: %d%% de ganar +1 de Liderazgo (necesitas %d para la Nobleza Alta)." % [
						roundi(_mando_chance() * 100), RoleProgression.NOBLEZA_ALTA_MIN_LEADERSHIP],
					"unavailable": _mando_unavailable_reason(),
					"locked": false, "callback": _action_ejercer_mando},
				_mobilize_action(MOBILIZE_FRACTION),
				_mercenarios_action(),
			]
		Character.Role.NOBLEZA_ALTA:
			return [
				{"label": "Retar a Duelo", "tooltip": DUEL_TOOLTIP, "unavailable": _duel_unavailable_reason(),
					"locked": false, "callback": _action_retar_duelo},
				_tournament_action(),
				{"label": "Gobernar Territorio", "tooltip": "Administras tu región a mayor escala, recaudando más que un noble menor (%d%% para ti, el resto para el castillo)." % roundi(PLAYER_TAX_SHARE * 100),
					"locked": false, "callback": _action_gobernar_territorio},
				_mobilize_action(MOBILIZE_FRACTION),
				_mercenarios_action(),
				{"label": "Negociar Alianza Regional", "tooltip": "Abre la pantalla de Relaciones: envía presentes y pacta alianzas con los señores vecinos (cada gestión gasta 1 acción allí).",
					"locked": false, "no_cost": true, "callback": _action_abrir_relaciones},
			]
		Character.Role.REGENTE:
			var regent_actions: Array[Dictionary] = [
				{"label": "Imponer Impuestos Reales", "tooltip": "Cobras %d de oro a cada castillo de tu reino para tus arcas." % REGENTE_TAX_PER_CASTLE,
					"locked": false, "callback": _action_impuestos_reales},
				{"label": "Reclutar Ejército Real", "tooltip": "Convierte %d%% de la guarnición en un poderoso ejército real. %s" % [int(MOBILIZE_FRACTION_REGENTE * 100), MOBILIZE_HINT],
					"locked": false, "callback": func(): _action_mobilize(MOBILIZE_FRACTION_REGENTE)},
				_mercenarios_action(),
				{"label": "Diplomacia (Relaciones)", "tooltip": "Declara guerras, firma paces, pacta alianzas y envía presentes.",
					"locked": false, "no_cost": true, "callback": _action_abrir_relaciones},
			]
			regent_actions.append_array(_edict_actions())
			return regent_actions
		Character.Role.DUQUE:
			return [
				{"label": "Retar a Duelo", "tooltip": DUEL_TOOLTIP, "unavailable": _duel_unavailable_reason(),
					"locked": false, "callback": _action_retar_duelo},
				_tournament_action(),
				{"label": "Gobernar el Ducado", "tooltip": "Recaudas en cada castillo a tu nombre (%d de base + Liderazgo × %d por castillo; %d%% para ti, el resto para sus arcas)." % [
					DUCADO_BASE_PER_CASTLE, DUCADO_LEADERSHIP_FACTOR, roundi(PLAYER_TAX_SHARE * 100)],
					"locked": false, "callback": _action_gobernar_ducado},
				_mobilize_action(MOBILIZE_FRACTION_DUQUE),
				_mercenarios_action(),
				{"label": "Diplomacia (Relaciones)", "tooltip": "Declara guerras, firma paces, pacta alianzas y envía presentes.",
					"locked": false, "no_cost": true, "callback": _action_abrir_relaciones},
			]
		Character.Role.MERCENARIO:
			return [
				_offer_services_action(),
				{"label": "Retar a Duelo", "tooltip": DUEL_TOOLTIP, "unavailable": _duel_unavailable_reason(),
					"locked": false, "callback": _action_retar_duelo},
				_tournament_action(),
				_entrenar_action(),
			]
		Character.Role.CAPITAN, Character.Role.CONDOTIERO:
			var company_actions: Array[Dictionary] = [
				_offer_services_action(),
				{"label": "Retar a Duelo", "tooltip": DUEL_TOOLTIP, "unavailable": _duel_unavailable_reason(),
					"locked": false, "callback": _action_retar_duelo},
				_tournament_action(),
				_mercenarios_action(),
				{"label": "Ejercer el Mando (%d oro)" % MANDO_COST,
					"tooltip": "Instruyes a tu compañía: %d%% de ganar +1 de Liderazgo (un Condotiero necesita %d)." % [
						roundi(_mando_chance() * 100), RoleProgression.CONDOTIERO_MIN_LEADERSHIP],
					"unavailable": _mando_unavailable_reason(),
					"locked": false, "callback": _action_ejercer_mando},
			]
			# Un condotiero que ya tomó este castillo lo gobierna como su señorío.
			if castle != null and castle.owner_name == character.full_name():
				company_actions.append({"label": "Recaudar Impuestos", "tooltip": "Cobras a las tierras de tu señorío, proporcional a tu Liderazgo (%d%% para ti, el resto para el castillo)." % roundi(PLAYER_TAX_SHARE * 100),
					"locked": false, "callback": _action_recaudar})
				company_actions.append(_mobilize_action(MOBILIZE_FRACTION))
			return company_actions
	return []

# --- Camino mercenario y Duque ---

func _abandon_liege_action() -> Dictionary:
	var reason := "" if not RelationsData.liege_name.is_empty() else "No sirves a ningún señor."
	return {"label": "Abandonar a tu Señor",
		"tooltip": "Rompes tu juramento y te haces %s: sin señor, vendes tu espada a quien pague. Tu señor te lo reprochará (afinidad %d, honor %d)." % [
			Character.role_title_for(Character.Role.MERCENARIO, character.gender), MissionData.DESERT_LIEGE_AFFINITY, MissionData.DESERT_LIEGE_HONOR],
		"unavailable": reason, "locked": false, "callback": _action_abandon_liege}

func _action_abandon_liege() -> void:
	_show_feedback(MissionData.desert_liege(character))
	_refresh_ui()

func _offer_services_action() -> Dictionary:
	var lord: Relationship = RelationsData.get_relation(castle.owner_name) if castle != null else null
	var reason := MissionData.hire_refusal(lord)
	if reason.is_empty() and lord != null and lord.person_name == character.full_name():
		reason = "Este castillo es tuyo: aquí no hay a quién servir."
	if reason.is_empty() and MissionData.active.size() >= MissionData.MAX_ACTIVE:
		reason = "Ya tienes %d contratos o encargos: cumple alguno antes." % MissionData.MAX_ACTIVE
	return {"label": "Ofrecer tus Servicios",
		"tooltip": "Te presentas ante %s y escuchas qué contratos ofrece. Firmar uno gasta 1 acción." % (lord.person_name if lord != null else "el señor del castillo"),
		"unavailable": reason, "locked": false, "no_cost": true, "anywhere": true, "callback": _action_offer_services}

func _action_offer_services() -> void:
	var lord: Relationship = RelationsData.get_relation(castle.owner_name) if castle != null else null
	var panel: Control = ContractsPanel.open(self, lord)
	panel.tree_exited.connect(func():
		if is_inside_tree():
			_refresh_ui()
			_build_role_actions())

func _action_gobernar_ducado() -> void:
	var total := 0
	var count := 0
	for c: Castle in MapData.castles:
		if c.owner_name != character.full_name() and c.castle_id != GameManager.home_castle_id:
			continue
		var amount: int = SkillEffects.income(DUCADO_BASE_PER_CASTLE + character.leadership * DUCADO_LEADERSHIP_FACTOR, character)
		var share := roundi(amount * PLAYER_TAX_SHARE)
		character.gold += share
		c.gold += amount - share
		total += share
		count += 1
	_show_feedback("Recorres tu ducado y recaudas en %d castillos: %d de oro para ti y el resto para sus arcas." % [count, total])
	_refresh_ui()

# Un botón por edicto; el vigente aparece marcado. Promulgar uno reemplaza al anterior.
func _edict_actions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in EdictCatalog.EDICTS.keys():
		var active := GameManager.active_edict == id
		result.append({
			"label": ("✓ Vigente: %s" if active else "Promulgar: %s") % EdictCatalog.title(id),
			"tooltip": EdictCatalog.description(id) + ("" if active else "\nReemplaza al edicto vigente."),
			"locked": false, "callback": func(): _action_promulgar_edicto(id)})
	return result

func _action_promulgar_edicto(id: String) -> void:
	GameManager.active_edict = id
	_show_feedback("Promulgas el %s. %s" % [EdictCatalog.title(id), EdictCatalog.description(id)])

func _show_feedback(text: String) -> void:
	action_feedback_label.text = text
	feedback_panel.visible = not text.is_empty()
	UiAnim.fade_in(feedback_panel, 0.25)

# --- Campesino ---

func _action_trabajar_tierra() -> void:
	character.gold += TIERRA_GOLD_GAIN
	_show_feedback("Trabajaste la tierra y ganaste %d de oro." % TIERRA_GOLD_GAIN)
	_refresh_ui()

func _action_migrar() -> void:
	_show_feedback("Para migrar, vuelve al mapa, elige un castillo de otro reino y pulsa «Viajar» (1 acción por tramo, 2 en invierno). Allí podrás establecerte con su señor.")

func _caza_chance() -> float:
	return clampf(CAZA_BASE_CHANCE + (character.strategy - 5) * 0.03, 0.3, 0.85)

func _action_cazar() -> void:
	if randf() < _caza_chance():
		character.gold += CAZA_GOLD
		_show_feedback("Cobras un ciervo en el bosque del señor y vendes la carne por %d de oro." % CAZA_GOLD)
	else:
		character.honor = clampi(character.honor - CAZA_HONOR_PENALTY, 0, 100)
		_show_feedback("Los guardabosques te sorprenden con la pieza: la vergüenza te cuesta %d de honor." % CAZA_HONOR_PENALTY)
	_refresh_ui()

# --- Soldado ---

func _entrenar_chance() -> float:
	return clampf((ENTRENAR_CAP - character.combat) / 10.0, 0.1, 1.0)

func _training_sessions_done() -> int:
	return character.training_sessions_month if character.last_training_month == GameManager.months_elapsed() else 0

func _entrenar_unavailable_reason() -> String:
	if _training_sessions_done() >= XpRules.TRAINING_PER_MONTH:
		return "Ya entrenaste %d veces este mes: el cuerpo necesita descanso." % XpRules.TRAINING_PER_MONTH
	if character.gold < ENTRENAR_COST:
		return "Necesitas %d de oro para pagar al maestro de armas." % ENTRENAR_COST
	return ""

func _entrenar_action() -> Dictionary:
	var first := _training_sessions_done() == 0 and character.combat < 20
	return {"label": "Entrenar (%d oro)" % ENTRENAR_COST,
		"tooltip": "Pagas a un maestro de armas: %d de experiencia (según tu tipo de luchador)%s. Hasta %d veces al mes (%d hechas)." % [
			roundi(XpRules.TRAINING * XpRules.multiplier(character.fighter_type, XpRules.SOURCE_TRAINING)),
			" y %d%% de ganar +%d de Combate (solo la primera sesión del mes)" % [roundi(_entrenar_chance() * 100), ENTRENAR_COMBAT_GAIN] if first else "",
			XpRules.TRAINING_PER_MONTH, _training_sessions_done()],
		"unavailable": _entrenar_unavailable_reason(),
		"locked": false, "callback": _action_entrenar}

func _action_entrenar() -> void:
	var reason := _entrenar_unavailable_reason()
	if reason != "":
		_show_feedback(reason)
		return
	var first := _training_sessions_done() == 0
	character.gold -= ENTRENAR_COST
	character.training_sessions_month = _training_sessions_done() + 1
	character.last_training_month = GameManager.months_elapsed()
	var levels := character.gain_xp(XpRules.TRAINING, XpRules.SOURCE_TRAINING)
	var xp_text := " Experiencia +%d.%s" % [character.last_xp_gained, " ¡Sube a nivel %d!" % character.level if levels > 0 else ""]
	if first and character.combat < 20 and randf() < _entrenar_chance():
		character.combat = mini(20, character.combat + ENTRENAR_COMBAT_GAIN)
		_show_feedback("Entrenaste duro. Combate ahora: %d.%s" % [character.combat, xp_text])
	else:
		_show_feedback("Sudaste toda la jornada con el maestro de armas.%s" % xp_text)
	_refresh_ui()

func _desertar_unavailable_reason() -> String:
	if character.is_wounded() or character.honor < DESERT_HONOR_THRESHOLD:
		return ""
	return "Solo un soldado malherido o caído en desgracia (honor menor que %d) abandona su puesto." % DESERT_HONOR_THRESHOLD

func _action_desertar() -> void:
	character.role = Character.Role.CAMPESINO
	GameManager.refresh_actions_for_role_change()
	_show_feedback("Desertaste y volviste a ser Campesino.")
	_refresh_ui()
	_build_role_actions()

# --- Caballero ---

func _mejorar_tierras_action() -> Dictionary:
	var reason := ""
	if character.rent >= MEJORAR_TIERRAS_MAX_RENT:
		reason = "Tus tierras ya rinden todo lo que pueden (%d de oro al mes)." % character.rent
	elif character.gold < MEJORAR_TIERRAS_COST:
		reason = "Necesitas %d de oro." % MEJORAR_TIERRAS_COST
	return {"label": "Mejorar las Tierras (%d oro)" % MEJORAR_TIERRAS_COST,
		"tooltip": "Inviertes en molinos y cultivos: +%d de oro al mes para siempre (ahora rinden %d) y +%d de comida para el castillo." % [
			MEJORAR_TIERRAS_RENT, character.rent, MEJORAR_TIERRAS_CASTLE_FOOD],
		"unavailable": reason, "locked": false, "callback": _action_mejorar_tierras}

func _action_mejorar_tierras() -> void:
	if character.gold < MEJORAR_TIERRAS_COST:
		_show_feedback("No tienes suficiente oro (necesitas %d)." % MEJORAR_TIERRAS_COST)
		return
	character.gold -= MEJORAR_TIERRAS_COST
	character.rent = mini(MEJORAR_TIERRAS_MAX_RENT, character.rent + MEJORAR_TIERRAS_RENT)
	if castle != null:
		castle.food += MEJORAR_TIERRAS_CASTLE_FOOD
	_show_feedback("Invertiste en tus tierras: ahora te rinden %d de oro cada mes." % character.rent)
	_refresh_ui()

# --- Nobleza Baja ---

func _action_recaudar() -> void:
	var amount: int = SkillEffects.income(RECAUDAR_BASE + character.leadership * 2, character)
	var share := _split_taxes(amount)
	_show_feedback("Recaudaste %d de oro de tu condado: %d para ti y %d para el castillo." % [amount, share, amount - share])
	_refresh_ui()

func _milicia_cost() -> int:
	var base: int = roundi(MILICIA_COST * SkillEffects.RECLUTADOR_COST_FACTOR) if SkillEffects.has(character, SkillEffects.RECLUTADOR_NATO) else MILICIA_COST
	return roundi(base * SkillEffects.recruit_cost_multiplier(character) * _cuartel_factor())

## El Cuartel del castillo abarata reclutar milicia y contratar mercenarios.
func _cuartel_factor() -> float:
	return 1.0 - castle.building_value("cuartel", "recruit_discount") if castle != null else 1.0

func _milicia_gain() -> int:
	return roundi(MILICIA_GARRISON_GAIN * SkillEffects.RECLUTADOR_GAIN_FACTOR) if SkillEffects.has(character, SkillEffects.RECLUTADOR_NATO) else MILICIA_GARRISON_GAIN

func _action_reclutar_milicia() -> void:
	var cost := _milicia_cost()
	var gain := _milicia_gain()
	if castle == null or castle.gold < cost:
		_show_feedback("El castillo no tiene suficiente oro (necesita %d)." % cost)
		return
	castle.gold -= cost
	castle.garrison_size += gain
	_show_feedback("Reclutaste %d soldados nuevos para la guarnición." % gain)
	_refresh_ui()

# Reparte lo recaudado entre tu bolsa y el tesoro del castillo. Devuelve tu parte.
func _split_taxes(amount: int) -> int:
	var share := roundi(amount * PLAYER_TAX_SHARE)
	character.gold += share
	if castle != null:
		castle.gold += amount - share
	return share

func _mando_chance() -> float:
	return clampf((MANDO_CAP - character.leadership) / MANDO_DIVISOR, 0.0, 1.0)

func _mando_unavailable_reason() -> String:
	if character.leadership >= MANDO_CAP:
		return "Tu Liderazgo ya es el máximo posible."
	if character.gold < MANDO_COST:
		return "Necesitas %d de oro." % MANDO_COST
	return ""

func _action_ejercer_mando() -> void:
	var reason := _mando_unavailable_reason()
	if reason != "":
		_show_feedback(reason)
		return
	character.gold -= MANDO_COST
	if randf() < _mando_chance():
		character.leadership += 1
		_show_feedback("Tus capitanes acatan tus órdenes con respeto: Liderazgo %d." % character.leadership)
	else:
		_show_feedback("Las maniobras salen desordenadas; tus hombres aún no te siguen del todo (Liderazgo %d)." % character.leadership)
	_refresh_ui()

# --- Nobleza Alta ---

func _action_gobernar_territorio() -> void:
	var amount: int = SkillEffects.income(RECAUDAR_BASE * 2 + character.leadership * 3, character)
	var share := _split_taxes(amount)
	_show_feedback("Gobernaste tu territorio y recaudaste %d de oro: %d para ti y %d para el castillo." % [amount, share, amount - share])
	_refresh_ui()

# --- Regente ---

func _action_impuestos_reales() -> void:
	# Se cobra a los castillos de tu reino (sin dejarlos en negativo).
	var total_collected := 0
	var taxed := 0
	for c: Castle in MapData.castles:
		if c.kingdom != GameManager.player_kingdom:
			continue
		var tax := mini(REGENTE_TAX_PER_CASTLE, c.gold)
		c.gold -= tax
		total_collected += tax
		taxed += 1
	total_collected = SkillEffects.income(total_collected, character)
	character.gold += total_collected
	_show_feedback("Impusiste impuestos reales: %d de oro recaudado de %d castillos de tu reino." % [total_collected, taxed])
	_refresh_ui()

# --- Movilización de ejércitos (disponible desde Caballero en adelante) ---

func _action_mobilize(fraction: float) -> void:
	if castle == null:
		_show_feedback("No se pudo determinar el castillo actual.")
		return
	if castle.garrison_size < MOBILIZE_MIN_GARRISON:
		_show_feedback("La guarnición es demasiado pequeña para movilizar tropas (necesitas al menos %d)." % MOBILIZE_MIN_GARRISON)
		return

	if SkillEffects.has(character, SkillEffects.RECLUTADOR_NATO):
		fraction += SkillEffects.RECLUTADOR_MOBILIZE_BONUS
	var mobilized: int = int(castle.garrison_size * fraction)
	if mobilized <= 0:
		_show_feedback("No hay suficientes tropas disponibles para movilizar.")
		return

	castle.garrison_size -= mobilized
	var army := ArmyData.add_player_troops(castle.castle_id, castle.kingdom, mobilized)
	_show_feedback("Movilizaste %d soldados desde %s: tu ejército allí suma ahora %d. Ve al mapa para darle órdenes de marcha." % [
		mobilized, castle.castle_name, army.size])
	_refresh_ui()

func _mobilize_action(fraction: float) -> Dictionary:
	return {"label": "Movilizar Ejército",
		"tooltip": "Convierte %d%% de la guarnición en tropas de marcha (se suman a tu ejército si ya tienes uno aquí). %s" % [
			int(fraction * 100), MOBILIZE_HINT],
		"locked": false, "callback": func(): _action_mobilize(fraction)}

func _mercenary_unit_cost() -> int:
	return maxi(1, roundi(MERCENARY_COST * SkillEffects.recruit_cost_multiplier(character) * _cuartel_factor()))

func _mercenaries_affordable() -> int:
	return mini(MERCENARY_MAX, character.gold / _mercenary_unit_cost())

func _mercenarios_action() -> Dictionary:
	var reason := "" if _mercenaries_affordable() >= MERCENARY_MIN else "Necesitas al menos %d de oro." % (MERCENARY_MIN * _mercenary_unit_cost())
	return {"label": "Contratar Mercenarios",
		"tooltip": "%d de oro por soldado, hasta %d por contrato (ahora: %d). Se suman a tu ejército en este castillo." % [
			_mercenary_unit_cost(), MERCENARY_MAX, _mercenaries_affordable()],
		"unavailable": reason, "locked": false, "callback": _action_mercenarios}

func _action_mercenarios() -> void:
	var hired := _mercenaries_affordable()
	if castle == null or hired < MERCENARY_MIN:
		_show_feedback("No te alcanza el oro para un contrato de mercenarios.")
		return
	character.gold -= hired * _mercenary_unit_cost()
	var army := ArmyData.add_player_troops(castle.castle_id, castle.kingdom, hired)
	_show_feedback("Contratas %d mercenarios por %d de oro. Tu ejército en %s suma %d soldados." % [
		hired, hired * _mercenary_unit_cost(), castle.castle_name, army.size])
	_refresh_ui()

# --- Duelo de campaña (Soldado en adelante, excepto Regente) ---

func _action_retar_duelo() -> void:
	if character.is_wounded():
		_show_feedback(_duel_unavailable_reason())
		return
	if not character.can_fight_duels():
		_show_feedback("Tu rango no te permite batirte en duelo.")
		return
	# A veces vuelve un rival conocido buscando revancha; si no, te retas con alguien de la corte.
	var rival := RelationsData.pick_duel_opponent(character)
	CombatSetup.start_campaign_duel(character, rival)
	get_tree().change_scene_to_file("res://scenes/combat/combat.tscn")

func _action_abrir_relaciones() -> void:
	get_tree().change_scene_to_file("res://scenes/relations/relations.tscn")

# --- Heridas, médico y torneos ---

func _duel_unavailable_reason() -> String:
	if character.is_wounded():
		return "Estás gravemente herido: no puedes batirte durante %d mes(es). Visita al médico o descansa." % character.wound_months
	return ""

func _tournament_unavailable_reason() -> String:
	if not GameManager.current_month in CombatSetup.TOURNAMENT_MONTHS:
		return "Los torneos se celebran de abril a septiembre."
	if GameManager.last_tournament_year == GameManager.current_year:
		return "Ya participaste en el torneo de este año."
	if character.is_wounded():
		return "Estás demasiado herido para justar."
	if character.gold < CombatSetup.TOURNAMENT_ENTRY_FEE:
		return "Necesitas %d de oro para la inscripción." % CombatSetup.TOURNAMENT_ENTRY_FEE
	return ""

func _tournament_action() -> Dictionary:
	return {"label": "Participar en Torneo (%d oro)" % CombatSetup.TOURNAMENT_ENTRY_FEE,
		"tooltip": "%d duelos seguidos contra caballeros cada vez más fuertes. El campeón gana %d de oro y %d de honor; cada ronda ganada da +%d de honor." % [
			CombatSetup.TOURNAMENT_ROUNDS, CombatSetup.TOURNAMENT_PRIZE_GOLD, CombatSetup.TOURNAMENT_PRIZE_HONOR, CombatSetup.TOURNAMENT_ROUND_HONOR],
		"unavailable": _tournament_unavailable_reason(),
		"locked": false, "callback": _action_torneo}

func _action_torneo() -> void:
	var reason := _tournament_unavailable_reason()
	if reason != "":
		_show_feedback(reason)
		return
	character.gold -= CombatSetup.TOURNAMENT_ENTRY_FEE
	GameManager.last_tournament_year = GameManager.current_year
	var opponents := RelationsData.tournament_opponents(character, CombatSetup.TOURNAMENT_ROUNDS, CombatSetup.TOURNAMENT_STAT_STEP)
	CombatSetup.start_tournament(character, opponents)
	get_tree().change_scene_to_file("res://scenes/combat/combat.tscn")

# Acciones disponibles para cualquier rol.
func _common_actions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if character.current_health < character.max_health or character.is_wounded():
		var reason := "" if character.gold >= MEDICO_COST else "Necesitas %d de oro." % MEDICO_COST
		result.append({"label": "Visitar al Médico (%d oro)" % MEDICO_COST,
			"tooltip": "Recuperas %d de vida y tu herida grave sana un mes antes. %s" % [MEDICO_HEAL, character.health_text()],
			"unavailable": reason, "locked": false, "anywhere": true, "callback": _action_medico})
	result.append_array(_command_actions())
	return result

# --- Comandancia: entrenar con la tropa, estudiar táctica y Consejo de guerra ---
const WarCouncilPanel = preload("res://scripts/ui/war_council_panel.gd")
const DRILL_COST := 15                  # oro para pagar la soldada del ejercicio
const DRILL_XP := 25                    # experiencia de mando (+ Liderazgo) en la familia elegida
const DRILL_PER_MONTH := 2
const STUDY_COST := 10                  # tratados y mapas
const STUDY_XP_BASE := 10               # experiencia de mando: base + Estrategia × STUDY_XP_PER_STRATEGY
const STUDY_XP_PER_STRATEGY := 2
const STUDY_PER_MONTH := 1
const DRILL_CHAR_XP := 10               # además, experiencia de personaje (fuente: entrenamiento)
const STUDY_CHAR_XP := 15               # (fuente: estudio; según tu tipo de luchador)

func _drills_done(kind: String) -> int:
	var entry: Array = character.troop_drill_log.get(kind, [-1, 0])
	return int(entry[1]) if int(entry[0]) == GameManager.months_elapsed() else 0

func _note_drill(kind: String) -> void:
	character.troop_drill_log[kind] = [GameManager.months_elapsed(), _drills_done(kind) + 1]

func _command_actions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if character.rank() < Character.rank_of(Character.Role.SOLDADO):
		return result
	var drill_reason := ""
	if _drills_done("entrenar") >= DRILL_PER_MONTH:
		drill_reason = "Ya ejercitaste a la tropa %d veces este mes." % DRILL_PER_MONTH
	elif character.gold < DRILL_COST:
		drill_reason = "Necesitas %d de oro para la soldada del ejercicio." % DRILL_COST
	result.append({"label": "Entrenar con la Tropa (%d oro)" % DRILL_COST,
		"tooltip": "Maniobras con una familia de tropa: +%d de experiencia de mando en ella (más tu Liderazgo). Hasta %d veces al mes. Gasta 1 acción.\nTu mando: %s" % [
			DRILL_XP, DRILL_PER_MONTH, WarCouncilPanel.mastery_line(character)],
		"unavailable": drill_reason, "locked": false, "no_cost": true, "anywhere": character.is_mercenary(), "needs_presence": not character.is_mercenary(), "callback": _action_drill})
	var study_reason := ""
	if _drills_done("estudiar") >= STUDY_PER_MONTH:
		study_reason = "Ya estudiaste táctica este mes."
	elif character.gold < STUDY_COST:
		study_reason = "Necesitas %d de oro para tratados y mapas." % STUDY_COST
	result.append({"label": "Estudiar Táctica (%d oro)" % STUDY_COST,
		"tooltip": "Lees a Vegecio y estudias batallas pasadas: +%d de experiencia de mando en la familia que elijas (sube con tu Estrategia). Una vez al mes. Gasta 1 acción." % (
			STUDY_XP_BASE + STUDY_XP_PER_STRATEGY * character.strategy),
		"unavailable": study_reason, "locked": false, "no_cost": true, "anywhere": true, "callback": _action_study})
	if WarCouncilPanel.block_reason(character).is_empty():
		result.append({"label": "Consejo de Guerra",
			"tooltip": "Asigna la tropa de cada personaje de tu facción (séquito, caballeros y señores de tu reino).",
			"unavailable": "", "locked": false, "no_cost": true, "remote_ok": true,
			"callback": func(): WarCouncilPanel.open(self, _refresh_ui)})
	return result

func _action_drill() -> void:
	_choose_family("¿Con qué tropa maniobras?", func(f: int):
		if not GameManager.consume_action():
			_show_feedback("No te quedan acciones este mes.")
			return
		character.gold -= DRILL_COST
		_note_drill("entrenar")
		var levels := character.add_mastery_xp(f, DRILL_XP + character.leadership)
		var char_levels := character.gain_xp(DRILL_CHAR_XP, XpRules.SOURCE_TRAINING)
		_show_feedback("Maniobras con %s. Experiencia +%d%s.%s" % [BattleEnums.family_name(f).to_lower(), character.last_xp_gained,
			" (¡nivel %d!)" % character.level if char_levels > 0 else "",
			" ¡Tu mando sube a nivel %d!" % character.mastery(f) if levels > 0 else " Mando %d (%d/%d)." % ([character.mastery(f)] + character.mastery_progress(f))])
		_refresh_ui())

func _action_study() -> void:
	_choose_family("¿Qué tropa estudias?", func(f: int):
		if not GameManager.consume_action():
			_show_feedback("No te quedan acciones este mes.")
			return
		character.gold -= STUDY_COST
		_note_drill("estudiar")
		var levels := character.add_mastery_xp(f, STUDY_XP_BASE + STUDY_XP_PER_STRATEGY * character.strategy)
		var char_levels := character.gain_xp(STUDY_CHAR_XP, XpRules.SOURCE_STUDY)
		_show_feedback("Estudias el arte de mandar %s. Experiencia +%d%s.%s" % [BattleEnums.family_name(f).to_lower(), character.last_xp_gained,
			" (¡nivel %d!)" % character.level if char_levels > 0 else "",
			" ¡Tu mando sube a nivel %d!" % character.mastery(f) if levels > 0 else " Mando %d (%d/%d)." % ([character.mastery(f)] + character.mastery_progress(f))])
		_refresh_ui())

## Ventana para elegir una familia de tropa (infantería, arquería, caballería o piqueros).
func _choose_family(title: String, picked: Callable) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 50
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := Label.new()
	head.text = title
	head.theme_type_variation = &"HeaderLabel"
	box.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var first: Button = null
	for f in 4:
		var b := Button.new()
		b.text = "%s (mando %d)" % [BattleEnums.family_name(f), character.mastery(f)]
		b.pressed.connect(func():
			overlay.queue_free()
			picked.call(f))
		row.add_child(b)
		if first == null:
			first = b
	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.pressed.connect(overlay.queue_free)
	box.add_child(cancel)
	first.grab_focus.call_deferred()

func _action_medico() -> void:
	if character.gold < MEDICO_COST:
		_show_feedback("No tienes oro suficiente para el médico.")
		return
	character.gold -= MEDICO_COST
	character.current_health = mini(character.max_health, character.current_health + MEDICO_HEAL)
	if character.wound_months > 0:
		character.wound_months -= 1
	_show_feedback("El médico te atiende. %s" % character.health_text())
	_refresh_ui()
