extends Control

@onready var board: BattleBoard = %Board
@onready var title_label: Label = %TitleLabel
@onready var turn_label: Label = %TurnLabel
@onready var forces_label: Label = %ForcesLabel
@onready var unit_info_label: Label = %UnitInfoLabel
@onready var log_label: Label = %LogLabel
@onready var legend_label: Label = %LegendLabel
@onready var btn_end_turn: Button = %BtnEndTurn
@onready var btn_retreat: Button = %BtnRetreat
@onready var result_overlay: Control = %ResultOverlay
@onready var result_title: Label = %ResultTitle
@onready var result_label: Label = %ResultLabel
@onready var btn_back_to_map: Button = %BtnBackToMap

const MAX_LOG_LINES := 12

var battle: BattleManager
var army: Army
var castle: Castle
var selected: BattleUnit
var log_lines: Array[String] = []
var player_defending := false   # true si el jugador defiende su castillo de un ejército de la IA

func _ready() -> void:
	army = ArmyData.active_battle_army
	castle = MapData.get_castle_by_id(army.current_castle_id) if army != null else null
	if army == null or not army.pending_battle or castle == null:
		# Nadie llegó aquí desde una batalla pendiente del mapa; evita un crash.
		var fallback := "res://scenes/map/map.tscn" if GameManager.is_game_active else "res://scenes/main_menu/main_menu.tscn"
		get_tree().change_scene_to_file(fallback)
		return

	result_overlay.visible = false
	btn_end_turn.pressed.connect(_on_end_turn_pressed)
	btn_retreat.pressed.connect(_on_retreat_pressed)
	btn_back_to_map.pressed.connect(_on_back_to_map_pressed)

	player_defending = not ArmyData.is_player_army(army)
	if player_defending:
		title_label.text = "Defensa de %s\n%s asedia tu castillo" % [castle.castle_name, army.owner_name]
		btn_retreat.text = "Abandonar Castillo"
		btn_retreat.tooltip_text = "Entregas el castillo al atacante sin seguir luchando."
	else:
		title_label.text = "Batalla por %s\n%s contra %s" % [castle.castle_name, army.owner_name, castle.owner_name]
	legend_label.text = "Llano · Bosque (defensa +25%) · Colina (defensa +20%, arqueros +1 alcance) · Muralla (defensa +50%)\nI = Infantería · A = Arqueros · C = Caballería · barra amarilla = moral"

	battle = BattleManager.new()
	battle.log_message.connect(_on_log_message)
	battle.state_updated.connect(_refresh)
	battle.battle_ended.connect(_on_battle_ended)
	board.setup(battle)
	board.cell_clicked.connect(_on_cell_clicked)

	var player: Character = GameManager.player_character
	var attacker_cmd: Character = null if player_defending else player
	var defender_cmd: Character = player if player_defending else null
	battle.player_side = BattleEnums.Side.DEFENSOR if player_defending else BattleEnums.Side.ATACANTE
	battle.start_battle(army.size, castle.garrison_size, true, attacker_cmd, defender_cmd, castle.castle_name)
	_refresh()

# --- Interacción con el tablero ---

func _on_cell_clicked(cell: Vector2i) -> void:
	if battle.is_over:
		return
	var clicked := battle.unit_at(cell)

	# Atacar a un enemigo en alcance con el pelotón seleccionado
	if selected != null and clicked != null and not battle.is_player_unit(clicked):
		if battle.can_attack(selected) and clicked in battle.targets_in_range(selected):
			battle.attack(selected, clicked)
			if not selected.is_active():
				selected = null
			_refresh()
			return

	# Seleccionar uno de tus pelotones
	if clicked != null and battle.is_player_unit(clicked):
		selected = clicked
		_refresh()
		return

	# Mover el pelotón seleccionado a una casilla resaltada
	if selected != null and clicked == null and cell in battle.reachable_cells(selected):
		battle.move_unit(selected, cell)
		_refresh()
		return

	if clicked != null:
		# Enemigo fuera de alcance: solo se muestra su información.
		unit_info_label.text = "Enemigo: %s\nTerreno: %s" % [clicked.describe(), BattleEnums.terrain_name(battle.terrain_at(clicked.cell))]
		return

	selected = null
	_refresh()

func _on_end_turn_pressed() -> void:
	selected = null
	battle.end_player_turn()
	_refresh()

func _on_retreat_pressed() -> void:
	battle.retreat()

# --- UI ---

func _refresh() -> void:
	if battle == null:
		return
	turn_label.text = "Turno %d / %d" % [mini(battle.turn, BattleManager.MAX_TURNS), BattleManager.MAX_TURNS]
	forces_label.text = "Tus tropas: %d · Enemigos: %d" % [
		_active_soldiers(battle.player_side), _active_soldiers(battle._other_side(battle.player_side))]

	var moves: Array[Vector2i] = []
	var targets: Array[BattleUnit] = []
	if selected != null and selected.is_active() and not battle.is_over:
		moves = battle.reachable_cells(selected)
		if battle.can_attack(selected):
			targets = battle.targets_in_range(selected)
		var status := "Puede moverse y atacar."
		if selected.has_acted:
			status = "Ya actuó este turno."
		elif selected.has_moved:
			status = "Ya se movió; aún puede atacar."
		unit_info_label.text = "%s\nTerreno: %s\n%s" % [
			selected.describe(), BattleEnums.terrain_name(battle.terrain_at(selected.cell)), status]
	elif not battle.is_over:
		unit_info_label.text = "Selecciona uno de tus pelotones (azul). Casillas claras: movimiento. Rojas: objetivos."
	board.set_selection(selected, moves, targets)

	btn_end_turn.disabled = battle.is_over
	btn_retreat.disabled = battle.is_over

func _active_soldiers(side: int) -> int:
	var sum := 0
	for u: BattleUnit in battle.active_units(side):
		sum += u.soldiers
	return sum

func _on_log_message(text: String) -> void:
	log_lines.append(text)
	while log_lines.size() > MAX_LOG_LINES:
		log_lines.remove_at(0)
	log_label.text = "\n".join(log_lines)

func _on_battle_ended(winner_side: int, report: Dictionary) -> void:
	var attacker_won: bool = winner_side == BattleEnums.Side.ATACANTE
	var player_won: bool = winner_side == battle.player_side
	# El resultado se aplica al mundo de inmediato, para que la batalla nunca quede a medias.
	var consequences := ArmyData.resolve_battle(army, attacker_won, report.attacker_survivors, report.defender_survivors, player_defending)
	if not GameManager.is_game_active:
		btn_back_to_map.text = "Volver al Menú"

	result_title.text = "¡Victoria!" if player_won else "Derrota"
	result_label.text = "%s\n\nAtacantes: %d → %d\nDefensores: %d → %d\nTurnos: %d\n\n%s" % [
		report.reason,
		report.attacker_initial, report.attacker_survivors,
		report.defender_initial, report.defender_survivors,
		report.turns, consequences]
	result_overlay.visible = true
	selected = null
	_refresh()

func _on_back_to_map_pressed() -> void:
	if not GameManager.is_game_active:
		GameManager.change_state(GameStateEnums.State.MENU)
		get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
		return
	GameManager.change_state(GameStateEnums.State.MAP)
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")
