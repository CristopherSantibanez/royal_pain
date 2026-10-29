extends Control

@export var player_character: Character
@export var enemy_character: Character

@onready var background: TextureRect = %TextureRect
@onready var portrait_player: TextureRect = %PortraitPlayer
@onready var portrait_enemy: TextureRect = %PortraitEnemy
@onready var btn_volver_menu: Button = %BtnVolverMenu
@onready var log_label: Label = %LogLabel
@onready var turn_indicator_label: Label = %TurnIndicatorLabel
@onready var hint_label: Label = %HintLabel
@onready var screen_margin: MarginContainer = %ScreenMargin

const ENEMY_TURN_DELAY := 1.2  # segundos de pausa antes de que el enemigo actúe
const DEFAULT_HINT := "Elige una postura y luego una acción. Pasa el ratón sobre una orden para ver qué hace."

const HEALTH_COLOR := Color("a1342a")
const STAMINA_COLOR := Color("6b8a2a")
const MORALE_COLOR := Color("3f6d8a")

# [postura, nombre, tecla, descripción]
const POSTURES := [
	[CombatEnums.Posture.OFENSIVA, "Ofensiva", KEY_Q, "Aumenta tu daño de ataque, pero te deja más vulnerable a recibir golpes."],
	[CombatEnums.Posture.DEFENSIVA, "Defensiva", KEY_W, "Reduce el daño que recibes, a cambio de menor poder ofensivo."],
	[CombatEnums.Posture.ESGRIMA, "Esgrima", KEY_E, "Prioriza la evasión y la agilidad sobre la fuerza bruta."],
	[CombatEnums.Posture.MURO, "Muro", KEY_R, "Defensa máxima. Ideal para resistir, pero casi no aporta al ataque."],
	[CombatEnums.Posture.DESESPERADA, "Desesperada", KEY_T, "Último recurso: gran daño ofensivo, pero tu defensa cae drásticamente."],
]
# [acción, nombre, tecla, descripción]
const ACTIONS := [
	[CombatEnums.ActionType.ATACAR, "Atacar", KEY_1, "Golpea al oponente. Falla si estás desarmado."],
	[CombatEnums.ActionType.DEFENDER, "Defender", KEY_2, "Te pones en guardia, reduciendo el daño del próximo ataque que recibas."],
	[CombatEnums.ActionType.ESQUIVAR, "Esquivar", KEY_3, "Te preparas para esquivar el próximo ataque, con posibilidad de evitarlo por completo."],
	[CombatEnums.ActionType.CONTRAATACAR, "Contraatacar", KEY_4, "Adoptas guardia de contraataque: si el enemigo te ataca, le devuelves parte del daño."],
	[CombatEnums.ActionType.DESARMAR, "Desarmar", KEY_5, "Intentas desarmar al oponente, dejándolo incapaz de atacar por un par de turnos."],
	[CombatEnums.ActionType.EMPUJAR, "Empujar", KEY_6, "Empujas al oponente, reduciendo su resistencia y moral si tienes éxito."],
	[CombatEnums.ActionType.RENDIRSE, "Rendirse", KEY_7, "Terminas el duelo inmediatamente. El oponente gana."],
	[CombatEnums.ActionType.RETIRARSE, "Retirarse", KEY_8, "Intentas huir del combate. Puede fallar si el oponente te lo impide."],
]

var duel: DuelManager
var player_turn := true
var _cards := {}                        # Character -> {name, role, bars, status, posture}
var _posture_buttons := {}              # postura -> Button
var _action_buttons: Array[Button] = []
var _key_bindings := {}                 # keycode -> Callable

# --- Duelo de campaña ---
var is_campaign := false
var _honor_before := 0
var _gold_before := 0
var _demotion_text := ""
var _pending_next_round := false   # torneo: el botón lleva a la siguiente ronda

func _ready() -> void:
	if player_character == null:
		player_character = CombatSetup.player_character if CombatSetup.player_character != null \
			else CharacterLoader.make_test_character("Sir Alaric", Character.Role.CABALLERO)
	if enemy_character == null:
		enemy_character = CombatSetup.enemy_character if CombatSetup.enemy_character != null \
			else CharacterLoader.make_test_character("Bandido Renco", Character.Role.SOLDADO)

	_cards[player_character] = _build_card(%PlayerCard)
	_cards[enemy_character] = _build_card(%EnemyCard)
	_build_orders()
	_pick_background()

	duel = DuelManager.new()
	duel.log_message.connect(_on_log_message)
	duel.duel_ended.connect(_on_duel_ended)
	duel.state_updated.connect(_refresh_ui)
	duel.character_demoted.connect(_on_character_demoted)
	duel.combat_event.connect(_on_combat_event)
	duel.start_duel(player_character, enemy_character)

	btn_volver_menu.pressed.connect(_on_volver_menu_pressed)
	hint_label.text = DEFAULT_HINT
	portrait_player.texture = player_character.get_portrait()
	portrait_enemy.texture = enemy_character.get_portrait()
	_refresh_ui()
	_update_turn_indicator()

	is_campaign = CombatSetup.is_campaign
	if is_campaign:
		_honor_before = player_character.honor
		_gold_before = player_character.gold
		# En campaña no se puede abandonar a mitad: para salir hay que rendirse o retirarse.
		btn_volver_menu.text = "Volver al Castillo"
		btn_volver_menu.disabled = true
		btn_volver_menu.tooltip_text = "Termina el duelo (o ríndete / retírate) para volver."
		if CombatSetup.is_tournament():
			turn_log_buffer = "TORNEO — Ronda %d de %d contra %s" % [
				CombatSetup.tournament_round, CombatSetup.tournament_opponents.size(), enemy_character.full_name()]
			log_label.text = turn_log_buffer

# --- Construcción de la interfaz ---

func _build_card(card: PanelContainer) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var refs := {}
	refs.name = _label(box, "SubheaderLabel")
	refs.name.add_theme_font_size_override("font_size", 17)
	refs.role = _label(box, "MutedLabel")
	refs.bars = {}
	for stat in [["health", "Vida", HEALTH_COLOR], ["stamina", "Aliento", STAMINA_COLOR], ["morale", "Moral", MORALE_COLOR]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var lbl := _label(row, "")
		lbl.text = stat[1]
		lbl.custom_minimum_size = Vector2(62, 0)
		lbl.add_theme_font_size_override("font_size", 15)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = stat[2]
		fill.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		var val := _label(row, "")
		val.custom_minimum_size = Vector2(62, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.add_theme_font_size_override("font_size", 15)
		refs.bars[stat[0]] = [bar, val]
	refs.status = _label(box, "")
	refs.status.add_theme_font_size_override("font_size", 16)
	refs.posture = _label(box, "MutedLabel")
	return refs

func _label(parent: Node, variation: String) -> Label:
	var l := Label.new()
	if not variation.is_empty():
		l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l

func _build_orders() -> void:
	var group := ButtonGroup.new()
	for p in POSTURES:
		var b := _order_button(%PostureRow, p[1], p[2], p[3])
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_player_posture.bind(p[0]))
		_posture_buttons[p[0]] = b
		_key_bindings[p[2]] = _player_posture.bind(p[0])
	for a in ACTIONS:
		var b := _order_button(%ActionGrid, a[1], a[2], a[3])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if a[0] == CombatEnums.ActionType.ATACAR:
			b.theme_type_variation = &"PrimaryButton"
		elif a[0] in [CombatEnums.ActionType.RENDIRSE, CombatEnums.ActionType.RETIRARSE]:
			b.theme_type_variation = &"FlatButton"
		b.pressed.connect(_player_action.bind(a[0]))
		_action_buttons.append(b)
		_key_bindings[a[2]] = _player_action.bind(a[0])

func _order_button(parent: Node, text: String, key: Key, description: String) -> Button:
	var b := Button.new()
	b.text = text
	var key_name := OS.get_keycode_string(key)
	b.tooltip_text = "%s  [tecla %s]" % [description, key_name]
	b.focus_mode = Control.FOCUS_NONE   # las teclas 1–8 / Q–T son el atajo; el foco solo estorbaría
	b.mouse_entered.connect(func(): hint_label.text = "[%s] %s — %s" % [key_name, text, description])
	b.mouse_exited.connect(func(): hint_label.text = DEFAULT_HINT)
	parent.add_child(b)
	return b

# Fondo según dónde se libra el duelo: torneos en el patio de armas; en campaña, según el reino del castillo.
func _pick_background() -> void:
	var path := "res://assets/TurnFight-Trining_Ground.png"
	if CombatSetup.is_campaign and not CombatSetup.is_tournament() and GameManager.current_castle != null:
		match GameManager.current_castle.kingdom:
			KingdomEnums.Kingdom.HIELO, KingdomEnums.Kingdom.CUMBRES, KingdomEnums.Kingdom.GRIS:
				path = "res://assets/TurnFight-Snow.png"
			KingdomEnums.Kingdom.DESIERTO, KingdomEnums.Kingdom.AMBAR, KingdomEnums.Kingdom.DORADO:
				path = "res://assets/TurnFight-Desert.png"
			KingdomEnums.Kingdom.AZUL, KingdomEnums.Kingdom.NEUTRAL:
				path = "res://assets/TurnFight-Seaside.png"
			_:
				path = "res://assets/TurnFight-Meadow.png"
	background.texture = load(path)

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var action: Callable = _key_bindings.get(key.physical_keycode, _key_bindings.get(key.keycode, Callable()))
	if action.is_valid():
		get_viewport().set_input_as_handled()
		action.call()

# --- Turnos ---

func _player_posture(p: int) -> void:
	if not player_turn or duel.is_over:
		return
	duel.set_posture(player_character, p)
	_refresh_ui()

func _player_action(action: int) -> void:
	if not player_turn or duel.is_over:
		return
	_start_new_turn_log()
	duel.take_turn(player_character, action)
	_refresh_ui()
	if not duel.is_over:
		player_turn = false
		_set_buttons_enabled(false)
		_update_turn_indicator()
		await get_tree().create_timer(ENEMY_TURN_DELAY).timeout
		_enemy_turn()

func _enemy_turn() -> void:
	player_turn = false
	if duel.is_over:
		_set_buttons_enabled(false)
		return

	_start_new_turn_log()

	var chosen_posture := CombatEnums.Posture.OFENSIVA
	if CombatEnums.Status.HERIDO in duel.statuses[enemy_character]:
		chosen_posture = CombatEnums.Posture.DEFENSIVA
	duel.set_posture(enemy_character, chosen_posture)

	var action := CombatEnums.ActionType.ATACAR
	if CombatEnums.Status.HERIDO in duel.statuses[enemy_character] and randf() < 0.5:
		action = CombatEnums.ActionType.DEFENDER
	duel.take_turn(enemy_character, action)

	player_turn = true
	_refresh_ui()
	_set_buttons_enabled(not duel.is_over)
	_update_turn_indicator()

func _refresh_ui() -> void:
	for c: Character in [player_character, enemy_character]:
		var refs: Dictionary = _cards[c]
		refs.name.text = c.full_name()
		refs.role.text = c.role_name()
		_set_bar(refs.bars.health, c.current_health, c.max_health)
		_set_bar(refs.bars.stamina, c.current_stamina, c.max_stamina)
		_set_bar(refs.bars.morale, c.current_morale, c.max_morale)
		refs.status.text = _status_text(duel.statuses.get(c, []))
		refs.posture.text = "Postura: " + CombatEnums.posture_name(duel.posture.get(c, CombatEnums.Posture.DEFENSIVA))
	var current: int = duel.posture.get(player_character, CombatEnums.Posture.DEFENSIVA)
	if _posture_buttons.has(current):
		_posture_buttons[current].set_pressed_no_signal(true)
	_update_music_intensity()

# Las barras bajan de forma animada en vez de saltar al nuevo valor.
func _set_bar(bar_and_label: Array, value: float, max_value: float) -> void:
	var bar: ProgressBar = bar_and_label[0]
	bar_and_label[1].text = "%d/%d" % [value, max_value]
	bar.max_value = max_value
	if is_equal_approx(bar.value, value):
		return
	bar.create_tween().tween_property(bar, "value", value, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

# La capa de tambores de la música sube cuando alguno de los dos está contra las cuerdas.
func _update_music_intensity() -> void:
	var lowest := minf(float(player_character.current_health) / player_character.max_health,
		float(enemy_character.current_health) / enemy_character.max_health)
	Music.set_intensity(smoothstep(0.75, 0.3, lowest))

