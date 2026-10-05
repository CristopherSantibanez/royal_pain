extends Control

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

var character: Character
var castle: Castle

# --- Constantes de balance de acciones (ajustables sin tocar la lógica) ---
const TIERRA_GOLD_GAIN := 15
const ENTRENAR_COMBAT_GAIN := 1
const MEJORAR_TIERRAS_COST := 100
const MEJORAR_TIERRAS_CASTLE_GOLD := 100
const MEJORAR_TIERRAS_CASTLE_FOOD := 20
const RECAUDAR_BASE := 40
const MILICIA_GARRISON_GAIN := 10
const MILICIA_COST := 60
const REGENTE_TAX_PER_CASTLE := 25
const MOBILIZE_MIN_GARRISON := 40
const MOBILIZE_FRACTION := 0.3
const MOBILIZE_FRACTION_REGENTE := 0.5
const DUEL_TOOLTIP := "Retas a un rival de tu rango. Ganar da honor, oro y cuenta para ascender; perder resta honor."
const MEDICO_COST := 30
const MEDICO_HEAL := 50

func _ready() -> void:
	character = GameManager.player_character
	castle = GameManager.current_castle
	btn_volver_mapa.pressed.connect(_on_volver_mapa_pressed)

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

	# Al volver de un duelo de campaña se muestra su resultado.
	if not CombatSetup.last_result_text.is_empty():
		_show_feedback(CombatSetup.last_result_text)
		CombatSetup.last_result_text = ""

func _refresh_ui() -> void:
	title_label.text = "Interior del Castillo — %s" % character.full_name()
	role_label.text = "Rol actual: %s · %s" % [character.role_name(), character.health_text()]
	honor_label.text = "Honor: %d / 100" % character.honor
	gold_label.text = "Oro: %d" % character.gold
	duels_label.text = "Duelos: %d ganados / %d perdidos" % [character.duels_won, character.duels_lost]
	actions_label.text = "Acciones disponibles este turno: %d / %d" % [GameManager.actions_remaining, GameManager.actions_per_turn]

	if castle != null:
		castle_info_label.text = "%s (%s) — Oro del castillo: %d | Comida: %d | Guarnición: %d" % [
			castle.castle_name, KingdomEnums.kingdom_name(castle.kingdom), castle.gold, castle.food, castle.garrison_size
		]
	else:
		castle_info_label.text = "No se pudo determinar el castillo actual."

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

		role_actions_list.add_child(btn)

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
				{"label": "Migrar a Otro Reino", "tooltip": "Te mudas a otro reino en busca de mejor fortuna. Requiere el sistema de viaje entre reinos.",
					"locked": true, "callback": Callable()},
			]
		Character.Role.SOLDADO:
			return [
				{"label": "Retar a Duelo", "tooltip": DUEL_TOOLTIP, "unavailable": _duel_unavailable_reason(),
					"locked": false, "callback": _action_retar_duelo},
				{"label": "Entrenar Combate", "tooltip": "Mejora tu habilidad de combate en +%d (máximo 20)." % ENTRENAR_COMBAT_GAIN,
					"locked": false, "callback": _action_entrenar},
				{"label": "Desertar", "tooltip": "Abandonas tu puesto y vuelves a ser Campesino.",
					"locked": false, "callback": _action_desertar},
			]
		Character.Role.CABALLERO:
			return [
				{"label": "Retar a Duelo", "tooltip": DUEL_TOOLTIP, "unavailable": _duel_unavailable_reason(),
					"locked": false, "callback": _action_retar_duelo},
				_tournament_action(),
				{"label": "Mejorar las Tierras", "tooltip": "Inviertes %d de tu oro en el castillo, a cambio de oro y comida para él." % MEJORAR_TIERRAS_COST,
					"locked": false, "callback": _action_mejorar_tierras},
				{"label": "Movilizar Ejército", "tooltip": "Convierte %d%% de la guarnición en un ejército marchante que podrás mover desde el mapa." % int(MOBILIZE_FRACTION * 100),
					"locked": false, "callback": func(): _action_mobilize(MOBILIZE_FRACTION)},
			]
		Character.Role.NOBLEZA_BAJA:
			return [
				{"label": "Retar a Duelo", "tooltip": DUEL_TOOLTIP, "unavailable": _duel_unavailable_reason(),
					"locked": false, "callback": _action_retar_duelo},
				_tournament_action(),
				{"label": "Recaudar Impuestos", "tooltip": "Recolectas impuestos de tu condado, proporcional a tu Liderazgo.",
					"locked": false, "callback": _action_recaudar},
				{"label": "Reclutar Milicia", "tooltip": "Gastas %d de oro del castillo para sumar %d soldados a la guarnición." % [_milicia_cost(), _milicia_gain()],
					"locked": false, "callback": _action_reclutar_milicia},
				{"label": "Movilizar Ejército", "tooltip": "Convierte %d%% de la guarnición en un ejército marchante que podrás mover desde el mapa." % int(MOBILIZE_FRACTION * 100),
					"locked": false, "callback": func(): _action_mobilize(MOBILIZE_FRACTION)},
			]
		Character.Role.NOBLEZA_ALTA:
			return [
				{"label": "Retar a Duelo", "tooltip": DUEL_TOOLTIP, "unavailable": _duel_unavailable_reason(),
					"locked": false, "callback": _action_retar_duelo},
				_tournament_action(),
				{"label": "Gobernar Territorio", "tooltip": "Administras tu región a mayor escala, recaudando más que un noble menor.",
					"locked": false, "callback": _action_gobernar_territorio},
				{"label": "Movilizar Ejército", "tooltip": "Convierte %d%% de la guarnición en un ejército marchante que podrás mover desde el mapa." % int(MOBILIZE_FRACTION * 100),
					"locked": false, "callback": func(): _action_mobilize(MOBILIZE_FRACTION)},
				{"label": "Negociar Alianza Regional", "tooltip": "Abre la pantalla de Relaciones: envía presentes y pacta alianzas con los señores vecinos (cada gestión gasta 1 acción allí).",
					"locked": false, "no_cost": true, "callback": _action_abrir_relaciones},
			]
		Character.Role.REGENTE:
			var regent_actions: Array[Dictionary] = [
				{"label": "Imponer Impuestos Reales", "tooltip": "Cobras %d de oro a cada castillo de tu reino para tus arcas." % REGENTE_TAX_PER_CASTLE,
					"locked": false, "callback": _action_impuestos_reales},
				{"label": "Reclutar Ejército Real", "tooltip": "Convierte %d%% de la guarnición en un poderoso ejército real." % int(MOBILIZE_FRACTION_REGENTE * 100),
					"locked": false, "callback": func(): _action_mobilize(MOBILIZE_FRACTION_REGENTE)},
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

# --- Campesino ---

func _action_trabajar_tierra() -> void:
	character.gold += TIERRA_GOLD_GAIN
	_show_feedback("Trabajaste la tierra y ganaste %d de oro." % TIERRA_GOLD_GAIN)
	_refresh_ui()

# --- Soldado ---

func _action_entrenar() -> void:
	if character.combat >= 20:
		_show_feedback("Ya alcanzaste el máximo de Combate posible.")
		return
	character.combat = min(20, character.combat + ENTRENAR_COMBAT_GAIN)
	_show_feedback("Entrenaste duro. Combate ahora: %d." % character.combat)
	_refresh_ui()

func _action_desertar() -> void:
	character.role = Character.Role.CAMPESINO
	GameManager.refresh_actions_for_role_change()
	_show_feedback("Desertaste y volviste a ser Campesino.")
	_refresh_ui()
	_build_role_actions()

# --- Caballero ---

func _action_mejorar_tierras() -> void:
	if character.gold < MEJORAR_TIERRAS_COST:
		_show_feedback("No tienes suficiente oro (necesitas %d)." % MEJORAR_TIERRAS_COST)
		return
	character.gold -= MEJORAR_TIERRAS_COST
	if castle != null:
		castle.gold += MEJORAR_TIERRAS_CASTLE_GOLD
		castle.food += MEJORAR_TIERRAS_CASTLE_FOOD
	_show_feedback("Invertiste en tus tierras. El castillo prospera.")
	_refresh_ui()

# --- Nobleza Baja ---

func _action_recaudar() -> void:
	var amount: int = SkillEffects.income(RECAUDAR_BASE + character.leadership * 2, character)
	character.gold += amount
	if castle != null:
		castle.gold += amount
	_show_feedback("Recaudaste %d de oro de tu condado." % amount)
	_refresh_ui()

func _milicia_cost() -> int:
	return roundi(MILICIA_COST * SkillEffects.RECLUTADOR_COST_FACTOR) if SkillEffects.has(character, SkillEffects.RECLUTADOR_NATO) else MILICIA_COST

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

# --- Nobleza Alta ---

func _action_gobernar_territorio() -> void:
	var amount: int = SkillEffects.income(RECAUDAR_BASE * 2 + character.leadership * 3, character)
	character.gold += amount
	if castle != null:
		castle.gold += amount
	_show_feedback("Gobernaste tu territorio y recaudaste %d de oro." % amount)
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
	ArmyData.create_army(character.full_name(), castle.kingdom, mobilized, castle.castle_id)
	_show_feedback("Movilizaste un ejército de %d soldados desde %s. Ve al mapa para darle órdenes de marcha." % [mobilized, castle.castle_name])
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
