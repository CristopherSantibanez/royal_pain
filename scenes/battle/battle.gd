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
@onready var forces_bar: ProgressBar = %ForcesBar
@onready var result_panel: PanelContainer = %ResultPanel
@onready var companions_label: Label = %CompanionsLabel

const MAX_LOG_LINES := 12
# Compañeros que trae el señor enemigo según su rango (cortesanos de su reino).
const ENEMY_COMPANIONS_BY_ROLE := {Character.Role.NOBLEZA_BAJA: 1, Character.Role.NOBLEZA_ALTA: 2, Character.Role.REGENTE: 3}
const ENEMY_COMPANION_CHANCE := 0.7
const DEFENDER_HINT := "Defiendes tras la muralla (+50% de defensa). Esperar no basta: usa tus arqueros desde el muro y golpea a quien se acerque."
const IDLE_HINT := "Selecciona uno de tus pelotones (azul). Casillas claras: movimiento. Rojas: objetivos (pasa el ratón para ver las bajas esperadas)."

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
	_style_forces_bar()

	battle = BattleManager.new()
	battle.log_message.connect(_on_log_message)
	battle.state_updated.connect(_refresh)
	battle.battle_ended.connect(_on_battle_ended)
	board.setup(battle)
	board.cell_clicked.connect(_on_cell_clicked)
	board.cell_hovered.connect(_on_cell_hovered)

	var player: Character = GameManager.player_character
	# Los señores de la IA comandan con su propia ficha (liderazgo, estrategia y habilidades de batalla).
	var attacker_cmd: Character = RelationsData.character_of(army.owner_name) if player_defending else player
	var defender_cmd: Character = player if player_defending else RelationsData.character_of(castle.owner_name)
	battle.player_side = BattleEnums.Side.DEFENSOR if player_defending else BattleEnums.Side.ATACANTE
	var enemy_cmd: Character = attacker_cmd if player_defending else defender_cmd
	var enemy_kingdom: int = army.kingdom if player_defending else castle.kingdom
	var mine := _player_companions()
	var theirs := _enemy_companions(enemy_cmd, enemy_kingdom)
	battle.start_battle(army.size, castle.garrison_size, true, attacker_cmd, defender_cmd, castle.castle_name, mine, theirs)
	_show_companions(mine, theirs)
	Sfx.play("horn", 0.0, 0.0)
	_refresh()

# --- Compañeros ---

# Séquito del jugador (o compañeros de facción prestados por su señor), si el sistema social lo ofrece.
func _player_companions() -> Array[Character]:
	var result: Array[Character] = []
	if RelationsData.has_method("battle_companions"):
		for c in RelationsData.battle_companions():
			if c is Character:
				result.append(c)
	return result

# El señor enemigo lleva cortesanos de su reino a la batalla, más cuanto más alto es su rango.
func _enemy_companions(enemy_cmd: Character, kingdom: int) -> Array[Character]:
	var result: Array[Character] = []
	var count: int = ENEMY_COMPANIONS_BY_ROLE.get(enemy_cmd.role if enemy_cmd != null else -1, 0)
	var pool := RelationsData.courtiers(kingdom)
	pool.shuffle()
	for r: Relationship in pool:
		if result.size() >= count:
			break
		if r.character != null and not r.character.is_wounded() and randf() < ENEMY_COMPANION_CHANCE:
			result.append(r.character)
	return result

func _show_companions(mine: Array[Character], theirs: Array[Character]) -> void:
	var lines: Array[String] = []
	if not mine.is_empty():
		lines.append("Contigo: " + ", ".join(mine.map(func(c: Character): return c.full_name())))
		var first: Character = mine[0]
		var topic := "faction_companion" if first.has_meta("faction_companion") else "retinue_battle"
		_on_log_message("%s: «%s»" % [first.full_name(), DialogueCatalog.line(topic, first, GameManager.player_character, {"player": GameManager.player_character.full_name()})])
	if not theirs.is_empty():
		lines.append("Con el enemigo: " + ", ".join(theirs.map(func(c: Character): return c.full_name())))
	companions_label.text = "\n".join(lines)
	companions_label.visible = not lines.is_empty()

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
		if clicked != selected:
			Sfx.play("click", -8.0)
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

# Al pasar sobre un enemigo atacable se muestran las bajas esperadas (sin azar) de ambos lados.
func _on_cell_hovered(cell: Vector2i) -> void:
	if battle == null or battle.is_over or selected == null or not selected.is_active() or not battle.can_attack(selected):
		return
	var target := battle.unit_at(cell)
	if target == null or battle.is_player_unit(target) or not target in battle.targets_in_range(selected):
		_refresh()
		return
	var p := battle.preview_attack(selected, target)
	var counter_text := "Sin respuesta enemiga" if p.counter == 0 else "Respuesta: ≈%d bajas propias" % p.counter
	unit_info_label.text = "%s → %s\nBajas enemigas esperadas: ≈%d de %d\n%s\nTerreno del objetivo: %s" % [
		BattleEnums.unit_type_name(selected.type), BattleEnums.unit_type_name(target.type),
		p.casualties, target.soldiers, counter_text,
		BattleEnums.terrain_name(battle.terrain_at(target.cell))]

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
	var mine := _active_soldiers(battle.player_side)
	var theirs := _active_soldiers(battle._other_side(battle.player_side))
	forces_label.text = "Tus tropas: %d  ·  Enemigos: %d" % [mine, theirs]
	forces_bar.value = mine / float(maxi(1, mine + theirs))
	# La capa de tambores sube a medida que caen soldados de ambos bandos.
	Music.set_intensity(smoothstep(0.0, 0.35, battle.casualty_fraction()) * 0.6 + (0.4 if battle.turn > 1 else 0.0))

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
		unit_info_label.text = (DEFENDER_HINT + "\n" if player_defending and battle.turn <= 2 else "") + IDLE_HINT
	board.set_selection(selected, moves, targets)

	btn_end_turn.disabled = battle.is_over
	btn_retreat.disabled = battle.is_over

# Barra de fuerzas: tu parte en azul sobre fondo rojo (el enemigo).
func _style_forces_bar() -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = BattleBoard.PLAYER_COLOR
	fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = BattleBoard.ENEMY_COLOR.darkened(0.25)
	bg.set_corner_radius_all(3)
	forces_bar.add_theme_stylebox_override("fill", fill)
	forces_bar.add_theme_stylebox_override("background", bg)

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
	result_title.add_theme_color_override("font_color", Color("f0d48a") if player_won else Color("c9584c"))
	result_label.text = "%s\n\nAtacantes: %d → %d\nDefensores: %d → %d\nTurnos: %d\n\n%s" % [
		report.reason,
		report.attacker_initial, report.attacker_survivors,
		report.defender_initial, report.defender_survivors,
		report.turns, consequences]
	if not report.get("wounded_companions", []).is_empty():
		result_label.text += "\n\nHeridos: %s." % ", ".join(report.wounded_companions)
	selected = null
	_refresh()
	# El resultado ya está aplicado; el cartel espera a que terminen de verse los últimos golpes.
	await get_tree().create_timer(board.fx_remaining() + 0.3).timeout
	Music.stop(0.8)
	Sfx.play("victory" if player_won else "defeat", 0.0, 0.0)
	result_overlay.visible = true
	UiAnim.fade_in(result_panel, 0.3)

func _on_back_to_map_pressed() -> void:
	if not GameManager.is_game_active:
		GameManager.change_state(GameStateEnums.State.MENU)
		get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
		return
	GameManager.change_state(GameStateEnums.State.MAP)
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")
