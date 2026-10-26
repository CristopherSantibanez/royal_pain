extends Control

const ShopPanel = preload("res://scripts/ui/shop_panel.gd")

const MissionsPanel = preload("res://scripts/ui/missions_panel.gd")

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
	portrait.texture = character.get_portrait()
	role_label.text = "%s\n%s · %s" % [character.full_name(), character.role_name(), character.health_text()]
	honor_label.text = "Honor %d" % character.honor
	honor_bar.value = character.honor
	if not honor_bar.has_theme_stylebox_override("fill"):
		var gold_fill := StyleBoxFlat.new()
		gold_fill.bg_color = Color("c9a24a")
		gold_fill.set_corner_radius_all(3)
		honor_bar.add_theme_stylebox_override("fill", gold_fill)
	gold_label.text = "Oro: %d · Fama: %d" % [character.gold, character.fame]
	duels_label.text = "Duelos: %d ganados / %d perdidos" % [character.duels_won, character.duels_lost]
	actions_label.text = "Acciones: %d / %d" % [GameManager.actions_remaining, GameManager.actions_per_turn]

	if castle != null:
		castle_info_label.text = "%s · Señor: %s" % [KingdomEnums.kingdom_name(castle.kingdom), castle.owner_name]
		castle_banner.color = KingdomEnums.kingdom_color(castle.kingdom)
		castle_stats_label.text = "Tesoro del castillo: %d\nComida: %d\nGuarnición: %d soldados" % [castle.gold, castle.food, castle.garrison_size]
	else:
		castle_info_label.text = "No se pudo determinar el castillo actual."
		castle_stats_label.text = ""

	var check := RoleProgression.check_ascension(character, RelationsData.succession_context())

	if check.next_role == -1:
		progression_label.text = "No hay ascenso disponible desde este rol todavía."
		btn_ascend.disabled = true
	elif check.can_ascend:
		progression_label.text = "¡Cumples los requisitos para ascender a %s!" % Character.role_name_for(check.next_role)
		btn_ascend.disabled = false
	else:
		progression_label.text = "Para ascender a %s: %s" % [Character.role_name_for(check.next_role), check.reason]
		btn_ascend.disabled = true

func _on_ascend_pressed() -> void:
	var succession := RelationsData.succession_context()
	var check := RoleProgression.check_ascension(character, succession)
	if RoleProgression.ascend(character, succession):
		if character.role == Character.Role.REGENTE:
			_show_feedback(RelationsData.become_regent(check.get("by_marriage", false)))
		else:
			_show_feedback("Asciendes a %s." % character.role_name())
		GameManager.refresh_actions_for_role_change()
		_refresh_ui()
		_build_role_actions()

func _on_volver_mapa_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")

# --- Acciones específicas por rol ---
# Cada entrada: {label, tooltip, locked (bool), callback (Callable, solo si no está locked)}

func _build_role_actions() -> void:
	for child in role_actions_list.get_children():
		child.queue_free()

	var actions: Array[Dictionary] = _get_actions_for_role(character.role)
	actions.append_array(_common_actions())
	var out_of_actions := not GameManager.has_actions_remaining()

	for action in actions:
		var btn := Button.new()
		btn.text = action.label if not action.locked else "%s (Próximamente)" % action.label
		btn.tooltip_text = action.tooltip
		btn.custom_minimum_size = Vector2(230, 38)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

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
			btn.disabled = out_of_actions
			if out_of_actions:
				btn.tooltip_text += "\n(Sin acciones disponibles este turno — avanza el turno desde el mapa)"
			btn.pressed.connect(_make_action_handler(action.callback))

		# Cada acción va en una fila con su descripción a la vista (antes solo estaba en el tooltip).
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.add_child(btn)
		var desc := Label.new()
		desc.theme_type_variation = &"MutedLabel"
		desc.text = btn.tooltip_text
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		desc.add_theme_font_size_override("font_size", 15)
		row.add_child(desc)
		role_actions_list.add_child(row)

func _make_action_handler(callback: Callable) -> Callable:
	return func() -> void:
		if not GameManager.consume_action():
			_show_feedback("No te quedan acciones disponibles este turno.")
			return
		callback.call()
		_build_role_actions()   # refresca qué botones quedan habilitados tras gastar la acción

func _get_actions_for_role(role: int) -> Array[Dictionary]:
	match role:
		Character.Role.CAMPESINO:
			return [
				{"label": "Trabajar la Tierra", "tooltip": "Ganas %d de oro trabajando en tus tierras." % TIERRA_GOLD_GAIN,
					"locked": false, "callback": _action_trabajar_tierra},
				{"label": "Cazar Furtivo", "tooltip": "%d%% de cazar en el bosque del señor y vender la pieza por %d de oro; si te pillan, pierdes %d de honor." % [
					roundi(_caza_chance() * 100), CAZA_GOLD, CAZA_HONOR_PENALTY],
					"locked": false, "callback": _action_cazar},
				{"label": "Migrar a Otro Reino", "tooltip": "Te mudas a otro reino en busca de mejor fortuna. Requiere el sistema de viaje entre reinos.",
					"locked": true, "callback": Callable()},
			]
		Character.Role.SOLDADO:
			return [
				{"label": "Retar a Duelo", "tooltip": DUEL_TOOLTIP, "unavailable": _duel_unavailable_reason(),
					"locked": false, "callback": _action_retar_duelo},
				_entrenar_action(),
				{"label": "Desertar", "tooltip": "Abandonas tu puesto y vuelves a ser Campesino.",
					"unavailable": _desertar_unavailable_reason(),
					"locked": false, "callback": _action_desertar},
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
	return []

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

func _entrenar_unavailable_reason() -> String:
	if character.combat >= 20:
		return "Ya alcanzaste el máximo de Combate posible."
	if character.last_training_month == GameManager.months_elapsed():
		return "Ya entrenaste este mes: el cuerpo necesita descanso."
	if character.gold < ENTRENAR_COST:
		return "Necesitas %d de oro para pagar al maestro de armas." % ENTRENAR_COST
	return ""

func _entrenar_action() -> Dictionary:
	return {"label": "Entrenar Combate (%d oro)" % ENTRENAR_COST,
		"tooltip": "Pagas a un maestro de armas: %d%% de ganar +%d de Combate (más difícil cuanto mejor eres). Una vez al mes." % [
			roundi(_entrenar_chance() * 100), ENTRENAR_COMBAT_GAIN],
		"unavailable": _entrenar_unavailable_reason(),
		"locked": false, "callback": _action_entrenar}

func _action_entrenar() -> void:
	var reason := _entrenar_unavailable_reason()
	if reason != "":
		_show_feedback(reason)
		return
	character.gold -= ENTRENAR_COST
	character.last_training_month = GameManager.months_elapsed()
	if randf() < _entrenar_chance():
		character.combat = mini(20, character.combat + ENTRENAR_COMBAT_GAIN)
		_show_feedback("Entrenaste duro. Combate ahora: %d." % character.combat)
	else:
		_show_feedback("Sudaste toda la jornada, pero hoy no lograste mejorar (Combate %d)." % character.combat)
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
	return roundi(base * SkillEffects.recruit_cost_multiplier(character))

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
	return maxi(1, roundi(MERCENARY_COST * SkillEffects.recruit_cost_multiplier(character)))

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
			"unavailable": reason, "locked": false, "callback": _action_medico})
	return result

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
