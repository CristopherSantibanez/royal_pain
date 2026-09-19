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
		progression_label.text = "Inicia una partida desde el menú principal para ver tu progresión."
		castle_info_label.text = ""
		btn_ascend.disabled = true
		return

	btn_ascend.pressed.connect(_on_ascend_pressed)
	_refresh_ui()
	_build_role_actions()

func _refresh_ui() -> void:
	title_label.text = "Interior del Castillo — %s" % character.full_name()
	role_label.text = "Rol actual: %s" % character.role_name()
	honor_label.text = "Honor: %d / 100" % character.honor
	gold_label.text = "Oro: %d" % character.gold
	duels_label.text = "Duelos: %d ganados / %d perdidos" % [character.duels_won, character.duels_lost]

	if castle != null:
		castle_info_label.text = "%s (%s) — Oro del castillo: %d | Comida: %d | Guarnición: %d" % [
			castle.castle_name, KingdomEnums.kingdom_name(castle.kingdom), castle.gold, castle.food, castle.garrison_size
		]
	else:
		castle_info_label.text = "No se pudo determinar el castillo actual."

	var check := RoleProgression.check_ascension(character)

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
	if RoleProgression.ascend(character):
		_refresh_ui()

func _on_volver_mapa_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")

# --- Acciones específicas por rol ---
# Cada entrada: {label, tooltip, locked (bool), callback (Callable, solo si no está locked)}

func _build_role_actions() -> void:
	for child in role_actions_list.get_children():
		child.queue_free()

	var actions: Array[Dictionary] = _get_actions_for_role(character.role)

	for action in actions:
		var btn := Button.new()
		btn.text = action.label if not action.locked else "%s (Próximamente)" % action.label
		btn.tooltip_text = action.tooltip
		btn.disabled = action.locked
		if not action.locked:
			btn.pressed.connect(action.callback)
		role_actions_list.add_child(btn)

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
				{"label": "Entrenar Combate", "tooltip": "Mejora tu habilidad de combate en +%d (máximo 20)." % ENTRENAR_COMBAT_GAIN,
					"locked": false, "callback": _action_entrenar},
				{"label": "Desertar", "tooltip": "Abandonas tu puesto y vuelves a ser Campesino.",
					"locked": false, "callback": _action_desertar},
			]
		Character.Role.CABALLERO:
			return [
				{"label": "Mejorar las Tierras", "tooltip": "Inviertes %d de tu oro en el castillo, a cambio de oro y comida para él." % MEJORAR_TIERRAS_COST,
					"locked": false, "callback": _action_mejorar_tierras},
				{"label": "Prepararse para Torneo", "tooltip": "Te entrenas para el próximo torneo de caballeros. Requiere el sistema de torneos.",
					"locked": true, "callback": Callable()},
			]
		Character.Role.NOBLEZA_BAJA:
			return [
				{"label": "Recaudar Impuestos", "tooltip": "Recolectas impuestos de tu condado, proporcional a tu Liderazgo.",
					"locked": false, "callback": _action_recaudar},
				{"label": "Reclutar Milicia", "tooltip": "Gastas %d de oro del castillo para sumar %d soldados a la guarnición." % [MILICIA_COST, MILICIA_GARRISON_GAIN],
					"locked": false, "callback": _action_reclutar_milicia},
			]
		Character.Role.NOBLEZA_ALTA:
			return [
				{"label": "Gobernar Territorio", "tooltip": "Administras tu región a mayor escala, recaudando más que un noble menor.",
					"locked": false, "callback": _action_gobernar_territorio},
				{"label": "Negociar Alianza Regional", "tooltip": "Buscas aliados entre los reinos vecinos. Requiere el sistema de relaciones y diplomacia.",
					"locked": true, "callback": Callable()},
			]
		Character.Role.REGENTE:
			return [
				{"label": "Imponer Impuestos Reales", "tooltip": "Recaudas oro de todos los castillos del reino, para ti y para tus arcas.",
					"locked": false, "callback": _action_impuestos_reales},
				{"label": "Reclutar Ejército Completo", "tooltip": "Levantas un nuevo ejército real. Requiere el sistema de ejércitos.",
					"locked": true, "callback": Callable()},
			]
	return []

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
	var amount: int = RECAUDAR_BASE + character.leadership * 2
	character.gold += amount
	if castle != null:
		castle.gold += amount
	_show_feedback("Recaudaste %d de oro de tu condado." % amount)
	_refresh_ui()

func _action_reclutar_milicia() -> void:
	if castle == null or castle.gold < MILICIA_COST:
		_show_feedback("El castillo no tiene suficiente oro (necesita %d)." % MILICIA_COST)
		return
	castle.gold -= MILICIA_COST
	castle.garrison_size += MILICIA_GARRISON_GAIN
	_show_feedback("Reclutaste %d soldados nuevos para la guarnición." % MILICIA_GARRISON_GAIN)
	_refresh_ui()

# --- Nobleza Alta ---

func _action_gobernar_territorio() -> void:
	var amount: int = RECAUDAR_BASE * 2 + character.leadership * 3
	character.gold += amount
	if castle != null:
		castle.gold += amount
	_show_feedback("Gobernaste tu territorio y recaudaste %d de oro." % amount)
	_refresh_ui()

# --- Regente ---

func _action_impuestos_reales() -> void:
	var total_collected := 0
	for c: Castle in MapData.castles:
		c.gold += REGENTE_TAX_PER_CASTLE
		total_collected += REGENTE_TAX_PER_CASTLE
	character.gold += total_collected
	_show_feedback("Impusiste impuestos reales: %d de oro recaudado de %d castillos." % [total_collected, MapData.castles.size()])
	_refresh_ui()
