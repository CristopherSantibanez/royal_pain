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
var _hovered_order := ""                # orden bajo el ratón, para refrescar su previsión
var _spoken := {}                       # Character -> {"hurt": bool, "low": bool, "cooldown": int}
const TAUNT_CHANCE := 0.6
const TAUNT_COOLDOWN := 2               # turnos propios sin volver a hablar tras una pulla
const BUBBLE_TIME := 3.2

# --- Duelo de campaña ---
var is_campaign := false
var _honor_before := 0
var _gold_before := 0
var _demotion_text := ""
var _pending_next_round := false   # torneo: el botón lleva a la siguiente ronda
var _owner: Character              # el personaje del jugador (aunque luche un campeón por él)
var _champion: Character           # miembro del séquito que lucha en tu lugar, o null
const TOURNAMENT_FAME := 10
const CHAMPION_WIN_HONOR := 3
const CHAMPION_WIN_FAME := 2
const CHAMPION_LOSS_HONOR := -2

func _ready() -> void:
	if player_character == null:
		player_character = CombatSetup.player_character if CombatSetup.player_character != null \
			else CharacterLoader.make_test_character("Sir Alaric", Character.Role.CABALLERO)
	if enemy_character == null:
		enemy_character = CombatSetup.enemy_character if CombatSetup.enemy_character != null \
			else CharacterLoader.make_test_character("Bandido Renco", Character.Role.SOLDADO)
	_owner = player_character
	# En campaña (no en torneos), un campeón de tu séquito puede batirse por ti.
	var champions: Array[Character] = []
	if CombatSetup.is_campaign and not CombatSetup.is_tournament() and GameManager.is_game_active:
		champions = RelationsData.duel_champions()
	if not champions.is_empty():
		var chosen: Character = await _ask_champion(champions)
		if chosen != _owner:
			_champion = chosen
			_champion.set_meta("champion", true)   # la IA del duelo sabe que es un luchador curtido
			player_character = chosen
	_begin()

# Ventana previa: ¿quién combate? Devuelve el personaje elegido.
func _ask_champion(champions: Array[Character]) -> Character:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 70
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "¿Quién se bate contra %s?" % enemy_character.full_name()
	box.add_child(title)
	var note := Label.new()
	note.theme_type_variation = &"MutedLabel"
	note.text = "Un campeón de tu séquito puede luchar en tu nombre: tú ganas algo de honor y fama si vence, y las heridas son suyas."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(560, 0)
	box.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var result := [null]
	var candidates: Array[Character] = [_owner]
	candidates.append_array(champions)
	for c: Character in candidates:
		var card := VBoxContainer.new()
		card.add_child(FaceIcon.make(c, 110, Color("d4af5a") if c == _owner else FaceIcon.FRAME_COLOR))
		var btn := Button.new()
		btn.text = "Yo mismo" if c == _owner else c.first_name
		btn.tooltip_text = "%s · Combate %d, Defensa %d · Vida %d/%d" % [c.full_name(), c.combat, c.defense, c.current_health, c.max_health]
		btn.theme_type_variation = &"PrimaryButton" if c == _owner else &""
		btn.pressed.connect(func(): result[0] = c)
		card.add_child(btn)
		row.add_child(card)
	while result[0] == null:
		await get_tree().process_frame
	overlay.queue_free()
	return result[0]

func _begin() -> void:
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
	_spoken[player_character] = {"hurt": false, "low": false, "cooldown": 0}
	_spoken[enemy_character] = {"hurt": false, "low": false, "cooldown": 0}
	_opening_lines()
	_focus_attack()
	if duel.roll_first(player_character, enemy_character) == enemy_character:
		_enemy_opens()
	if is_campaign:
		_honor_before = _owner.honor
		_gold_before = _owner.gold
		# En campaña no se puede abandonar a mitad: para salir hay que rendirse o retirarse.
		btn_volver_menu.text = "Volver al Mapa" if CombatSetup.return_scene.ends_with("map.tscn") \
			else "Volver a Relaciones" if CombatSetup.return_scene.ends_with("relations.tscn") else "Volver al Castillo"
		btn_volver_menu.disabled = true
		btn_volver_menu.tooltip_text = "Termina el duelo (o ríndete / retírate) para volver."
		if CombatSetup.is_tournament():
			turn_log_buffer = "TORNEO — Ronda %d de %d contra %s" % [
				CombatSetup.tournament_round, CombatSetup.tournament_opponents.size(), enemy_character.full_name()]
			log_label.text = turn_log_buffer

# --- Diálogo: cada luchador habla según su personalidad y su historia con el otro ---

func _opening_lines() -> void:
	var topic := "duel_open"
	var r := RelationsData.get_relation(enemy_character.full_name()) if is_campaign else null
	if r != null and r.kind == Relationship.Kind.RIVAL_DUELO:
		match r.rivalry_stage():
			Relationship.RivalryStage.RIVAL: topic = "duel_open_rival"
			Relationship.RivalryStage.NEMESIS: topic = "duel_open_nemesis"
			Relationship.RivalryStage.RESPETO: topic = "duel_open_respect"
	_say(enemy_character, topic, 0.4)
	_say(player_character, "duel_open", 2.2)

func _enemy_opens() -> void:
	player_turn = false
	_set_buttons_enabled(false)
	_update_turn_indicator()
	turn_log_buffer = "%s toma la iniciativa." % enemy_character.full_name()
	log_label.text = turn_log_buffer
	await get_tree().create_timer(ENEMY_TURN_DELAY + 1.0).timeout
	_enemy_turn()

func _say(c: Character, topic: String, delay: float = 0.0) -> void:
	var other := enemy_character if c == player_character else player_character
	var text := DialogueCatalog.line(topic, c, other, {"player": other.full_name()})
	if text.is_empty():
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_inside_tree():
		return
	var bubble := PanelContainer.new()
	bubble.theme_type_variation = &"ParchmentPanel"
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.z_index = 80
	var label := Label.new()
	label.theme_type_variation = &"InkLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(230, 0)
	label.add_theme_font_size_override("font_size", 16)
	bubble.add_child(label)
	add_child(bubble)
	bubble.reset_size()
	# El globo sale del lado del retrato que da a la arena, a la altura del pecho, sin tapar la cara.
	var portrait := _portrait_of(c).get_global_rect()
	var x := portrait.end.x - 30.0 if c == player_character else portrait.position.x - bubble.size.x + 30.0
	x = clampf(x, 8.0, get_viewport_rect().size.x - bubble.size.x - 8.0)
	bubble.global_position = Vector2(x, portrait.position.y + portrait.size.y * 0.3)
	UiAnim.fade_in(bubble, 0.2)
	var tw := bubble.create_tween()
	tw.tween_interval(BUBBLE_TIME)
	tw.tween_property(bubble, "modulate:a", 0.0, 0.4)
	tw.tween_callback(bubble.queue_free)

# Pullas durante el duelo: tras un golpe fuerte, al quedar malherido o al borde de caer.
func _maybe_taunt(kind: String, actor: Character, target: Character) -> void:
	if duel.is_over:
		return
	if kind == "crit" or kind == "parry":
		var speaker := actor if kind == "crit" else actor
		if _spoken[speaker].cooldown <= 0 and randf() < TAUNT_CHANCE:
			_spoken[speaker].cooldown = TAUNT_COOLDOWN
			_say(speaker, "taunt_hit", 0.5)
			return
	var hp := float(target.current_health) / target.max_health
	if hp < 0.25 and not _spoken[target].low:
		_spoken[target].low = true
		_say(target, "taunt_low", 0.6)
	elif hp < 0.5 and not _spoken[target].hurt:
		_spoken[target].hurt = true
		_say(target, "taunt_hurt", 0.6)

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
		if b.theme_type_variation != &"":
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				b.remove_theme_stylebox_override(state)
			_compact(b)
		b.pressed.connect(_player_action.bind(a[0]))
		_action_buttons.append(b)
		_key_bindings[a[2]] = _player_action.bind(a[0])

func _order_button(parent: Node, text: String, key: Key, description: String) -> Button:
	var b := Button.new()
	b.text = text
	var key_name := OS.get_keycode_string(key)
	b.tooltip_text = "%s  [tecla %s]" % [description, key_name]
	b.focus_mode = Control.FOCUS_ALL    # mando y flechas; las teclas 1–8 / Q–T siguen siendo atajos
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(0, 34)
	parent.add_child(b)
	_compact(b)
	b.set_meta("hint", "[%s] %s — %s" % [key_name, text, description])
	b.mouse_entered.connect(func():
		_hovered_order = text
		hint_label.text = _order_hint(text))
	b.mouse_exited.connect(func():
		_hovered_order = ""
		hint_label.text = DEFAULT_HINT)
	return b

# Descripción de una orden con lo que cabe esperar ahora mismo (daño, probabilidades, aliento).
func _order_hint(order_name: String) -> String:
	var base := ""
	for list in [POSTURES, ACTIONS]:
		for entry in list:
			if entry[1] == order_name:
				base = "[%s] %s — %s" % [OS.get_keycode_string(entry[2]), entry[1], entry[3]]
	if duel == null:
		return base
	var me := player_character
	var foe := enemy_character
	var extra := ""
	match order_name:
		"Atacar":
			var dmg := duel.preview_damage(me, foe)
			extra = "Daño previsto: %d–%d." % [dmg.x, dmg.y]
			if duel.countering[foe]:
				extra += " ¡Cuidado! Prepara una parada (%d%%)." % roundi(duel.parry_chance(me, foe) * 100)
			elif duel.dodging[foe]:
				extra += " Puede esquivarlo (%d%%)." % roundi(duel.dodge_chance(me, foe) * 100)
			elif duel.defending[foe]:
				extra += " Está en guardia: el golpe se reduce a la mitad."
		"Contraatacar":
			extra = "Probabilidad de parar su próximo golpe: %d%%." % roundi(duel.parry_chance(foe, me) * 100)
		"Esquivar":
			extra = "Probabilidad de esquivar: %d%%." % roundi(duel.dodge_chance(foe, me) * 100)
		"Desarmar":
			extra = "Éxito: %d%%." % roundi(duel.disarm_chance(me, foe) * 100) if not duel.is_fatigued(me) else "Sin aliento: no puedes intentarlo."
		"Empujar":
			extra = "Éxito: %d%%. Rompe su guardia si la tiene." % roundi(duel.push_chance(me, foe) * 100) if not duel.is_fatigued(me) else "Sin aliento: no puedes intentarlo."
		"Retirarse":
			extra = "Éxito: %d%% (cuesta honor)." % roundi(duel.retreat_chance(me, foe) * 100)
	return base + ("\n" + extra if not extra.is_empty() else "")

# Menos relleno lateral que un botón normal: caben 5 posturas y 4 acciones por fila.
func _compact(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := b.get_theme_stylebox(state).duplicate() as StyleBox
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		b.add_theme_stylebox_override(state, sb)

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

	# Cada personalidad pelea a su manera (ver DuelAI) y se adapta a lo que hace el jugador.
	var choice := DuelAI.choose(duel, enemy_character, player_character)
	duel.set_posture(enemy_character, choice.posture)
	duel.take_turn(enemy_character, choice.action)
	for c: Character in _spoken:
		_spoken[c].cooldown -= 1

	player_turn = true
	_refresh_ui()
	_set_buttons_enabled(not duel.is_over)
	_focus_attack()
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
		var guard := duel.guard_text(c)
		if not guard.is_empty():
			refs.status.text += "\n⚑ " + guard
		refs.posture.text = "Postura: " + CombatEnums.posture_name(duel.posture.get(c, CombatEnums.Posture.DEFENSIVA))
	var current: int = duel.posture.get(player_character, CombatEnums.Posture.DEFENSIVA)
	if _posture_buttons.has(current):
		_posture_buttons[current].set_pressed_no_signal(true)
	_update_music_intensity()
	if not _hovered_order.is_empty():
		hint_label.text = _order_hint(_hovered_order)

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

# --- Efectos de combate ---

func _portrait_of(c: Character) -> TextureRect:
	return portrait_player if c == player_character else portrait_enemy

func _portrait_center(c: Character) -> Vector2:
	return _portrait_of(c).get_global_rect().get_center()

func _float(c: Character, text: String, color: Color, font_size: int = 32) -> void:
	CombatFx.floating_text(self, _portrait_center(c), text, color, font_size)

func _impact(c: Character, strength: float, spark_amount: int) -> void:
	var portrait := _portrait_of(c)
	CombatFx.flash(portrait)
	CombatFx.punch(portrait, 0.08 + strength * 0.006)
	CombatFx.sparks(self, _portrait_center(c) - global_position, Color(1.0, 0.85, 0.4), spark_amount)
	CombatFx.shake(screen_margin, strength, 0.25)

func _on_combat_event(kind: String, actor: Character, target: Character, amount: int) -> void:
	if kind in ["hit", "crit", "parry", "parry_fail"]:
		_maybe_taunt(kind, actor, target)
	match kind:
		"hit":
			Sfx.play("clash", -4.0)
			Sfx.play("hit")
			_impact(target, 6.0, 20)
			_float(target, "-%d" % amount, CombatFx.DAMAGE_COLOR)
		"crit":
			Sfx.play("crit")
			_impact(target, 16.0, 48)
			_float(target, "¡CRÍTICO! -%d" % amount, CombatFx.CRIT_COLOR, 44)
			CombatFx.hit_stop(get_tree(), 0.12)
		"parry":
			# El acero choca primero y la respuesta llega justo después: dos impactos.
			Sfx.play("clash")
			_float(actor, "¡Parada!", CombatFx.CRIT_COLOR, 30)
			CombatFx.sparks(self, _portrait_center(actor) - global_position, Color(1.0, 0.95, 0.7), 30)
			await get_tree().create_timer(0.3).timeout
			Sfx.play("hit", -2.0)
			_impact(target, 10.0, 24)
			_float(target, "Respuesta -%d" % amount, CombatFx.DAMAGE_COLOR, 30)
		"parry_fail":
			Sfx.play("clash", -6.0)
			Sfx.play("hit")
			_impact(target, 8.0, 20)
			_float(target, "Parada fallida -%d" % amount, CombatFx.DAMAGE_COLOR, 28)
		"guard_break":
			Sfx.play("push")
			Sfx.play("guard", -4.0)
			CombatFx.punch(_portrait_of(target), 0.22)
			CombatFx.shake(screen_margin, 10.0, 0.25)
			_float(target, "¡Guardia rota!", CombatFx.CRIT_COLOR, 32)
		"winded":
			Sfx.play("whoosh", -8.0)
			_float(actor, "Sin aliento", CombatFx.MISS_COLOR, 26)
		"dodge":
			Sfx.play("whoosh")
			CombatFx.shake(_portrait_of(target), 14.0, 0.2)
			_float(target, "¡Esquiva!", CombatFx.MISS_COLOR)
		"unarmed":
			Sfx.play("whoosh", -6.0)
			_float(actor, "¡Sin arma!", CombatFx.MISS_COLOR, 26)
		"guard":
			Sfx.play("guard")
			CombatFx.flash(_portrait_of(actor), Color(0.7, 0.9, 1.6), 0.4)
			_float(actor, "En guardia", CombatFx.INFO_COLOR, 24)
		"dodge_ready":
			Sfx.play("whoosh", -5.0)
			_float(actor, "Atento a esquivar", CombatFx.INFO_COLOR, 24)
		"counter_ready":
			Sfx.play("clash", -10.0)
			CombatFx.flash(_portrait_of(actor), Color(1.6, 1.4, 0.7), 0.4)
			_float(actor, "Espera para parar", CombatFx.INFO_COLOR, 24)
		"disarm":
			Sfx.play("disarm")
			_impact(target, 8.0, 32)
			_float(target, "¡Desarmado!", CombatFx.CRIT_COLOR, 36)
		"push":
			Sfx.play("push")
			CombatFx.punch(_portrait_of(target), 0.2)
			CombatFx.shake(screen_margin, 8.0, 0.2)
			_float(target, "¡Empujón!", CombatFx.DAMAGE_COLOR, 28)
		"miss":
			Sfx.play("whoosh")
			_float(target, "Falla", CombatFx.MISS_COLOR, 28)
		"retreat_fail":
			Sfx.play("guard", -4.0)
			_float(actor, "¡No logra huir!", CombatFx.MISS_COLOR, 28)

func _exit_tree() -> void:
	Engine.time_scale = 1.0   # por si se sale de la escena durante un hit-stop

func _status_text(statuses: Array) -> String:
	if statuses.is_empty():
		return "Sin alteraciones"
	var names := []
	for s in statuses:
		names.append(CombatEnums.status_name(s))
	return " · ".join(names)

var turn_log_buffer: String = ""

func _on_log_message(text: String) -> void:
	if turn_log_buffer.is_empty():
		turn_log_buffer = text
	else:
		turn_log_buffer += "\n" + text
	log_label.text = turn_log_buffer

func _start_new_turn_log() -> void:
	turn_log_buffer = ""

func _on_duel_ended(winner: Character, reason: String) -> void:
	if winner == null:
		Sfx.play("whoosh")
	else:
		_play_end_sound(winner == player_character)
		_say(winner, "duel_win", 0.9)
		_say(duel.opponent_of(winner), "duel_lose", 2.6)
	var winner_name := winner.full_name() if winner != null else "Nadie (huida)"
	turn_log_buffer += "\n DUELO TERMINADO Ganador: %s" % winner_name
	log_label.text = turn_log_buffer

	if is_campaign:
		# La rivalidad se registra antes del resumen: vencer a un rival conocido suma honor.
		# Los combates de evento contra bandidos y similares no crean rivalidades.
		var event_foe: bool = CombatSetup.pending_outcome.get("no_rival", false)
		var rivalry := "" if event_foe else RelationsData.register_duel(enemy_character, winner == player_character, winner == null)
		var outcome := CombatSetup.apply_outcome(winner == player_character)
		if not outcome.is_empty():
			rivalry = (rivalry + " " + outcome).strip_edges()
		rivalry += _champion_outcome(winner)
		if MissionData.has_method("on_duel_finished"):
			MissionData.on_duel_finished(enemy_character, winner == player_character)
		btn_volver_menu.disabled = false
		btn_volver_menu.tooltip_text = ""
		if CombatSetup.is_tournament():
			_tournament_round_ended(winner, rivalry)
			return
		# Las heridas ya no se curan solas al terminar: la vida se recupera con los meses.
		var wound := player_character.after_fight_recovery() if _champion == null else ""
		CombatSetup.last_result_text = " ".join([_campaign_summary(winner), rivalry, wound]).strip_edges()

# Si luchó un campeón, el jugador recibe parte de la gloria (o de la vergüenza).
func _champion_outcome(winner: Character) -> String:
	if _champion == null:
		return ""
	_champion.after_fight_recovery()
	_champion.remove_meta("champion")
	if winner == _champion:
		_owner.gain_honor(CHAMPION_WIN_HONOR)
		_owner.add_fame(CHAMPION_WIN_FAME)
		_say(_champion, "champion_win", 3.6)
		return " Tu campeón %s vence en tu nombre (honor %+d, fama %+d)." % [_champion.full_name(), CHAMPION_WIN_HONOR, CHAMPION_WIN_FAME]
	if winner != null:
		_owner.gain_honor(CHAMPION_LOSS_HONOR)
		_say(_champion, "champion_lose", 3.6)
		return " Tu campeón %s cae derrotado (honor %+d)." % [_champion.full_name(), CHAMPION_LOSS_HONOR]
	return ""

func _play_end_sound(won: bool) -> void:
	await get_tree().create_timer(0.5).timeout   # deja sonar el último golpe
	Sfx.play("victory" if won else "defeat", 0.0, 0.0)
	if not won:
		CombatFx.flash(portrait_player, Color(0.6, 0.6, 0.6), 1.2)

func _tournament_round_ended(winner: Character, rivalry: String) -> void:
	var round_num := CombatSetup.tournament_round
	var total := CombatSetup.tournament_opponents.size()
	var won := winner == player_character
	var badly_hurt := player_character.current_health < player_character.max_health * Character.SEVERE_WOUND_RATIO
	if won:
		player_character.honor = clampi(player_character.honor + CombatSetup.TOURNAMENT_ROUND_HONOR, 0, 100)

	if won and not CombatSetup.is_final_round() and not badly_hurt:
		_pending_next_round = true
		btn_volver_menu.text = "Siguiente ronda (%d/%d)" % [round_num + 1, total]
		turn_log_buffer += "\n¡Pasas a la ronda %d!" % (round_num + 1)
		log_label.text = turn_log_buffer
		return

	var text: String
	if won and CombatSetup.is_final_round():
		player_character.gold += CombatSetup.TOURNAMENT_PRIZE_GOLD
		player_character.honor = clampi(player_character.honor + CombatSetup.TOURNAMENT_PRIZE_HONOR, 0, 100)
		text = "¡Campeón del torneo! Vences las %d rondas y ganas %d de oro y %d de honor." % [
			total, CombatSetup.TOURNAMENT_PRIZE_GOLD, CombatSetup.TOURNAMENT_PRIZE_HONOR]
		player_character.add_fame(TOURNAMENT_FAME)
		text += " Fama %+d." % TOURNAMENT_FAME
		var reactions := RelationsData.rival_reactions()
		if not reactions.is_empty():
			text += " " + reactions
	elif won:
		text = "Ganas la ronda %d, pero tus heridas te obligan a retirarte del torneo." % round_num
	else:
		text = "Quedas eliminado en la ronda %d del torneo." % round_num
	text += " Balance del torneo: honor %+d, oro %+d." % [
		player_character.honor - CombatSetup.tournament_honor_start, player_character.gold - CombatSetup.tournament_gold_start]
	var wound := player_character.after_fight_recovery()
	CombatSetup.last_result_text = " ".join([text, rivalry, _demotion_text, wound]).strip_edges()
	turn_log_buffer += "\n" + text
	log_label.text = turn_log_buffer

func _campaign_summary(winner: Character) -> String:
	var outcome: String
	if winner == player_character:
		outcome = "Venciste en duelo a %s." % enemy_character.full_name() if _champion == null else "Tu campeón venció a %s." % enemy_character.full_name()
	elif winner == null:
		outcome = "El duelo contra %s terminó con una huida." % enemy_character.full_name()
	else:
		outcome = "%s te derrotó en duelo." % enemy_character.full_name()
	var text := "%s Honor %+d, oro %+d. Duelos: %d ganados / %d perdidos." % [
		outcome, _owner.honor - _honor_before, _owner.gold - _gold_before,
		_owner.duels_won, _owner.duels_lost]
	if not _demotion_text.is_empty():
		text += " " + _demotion_text
	return text

func _on_character_demoted(character: Character, old_role: int, new_role: int) -> void:
	# El mensaje ya queda en el log mediante log_message; en campaña además se
	# guarda para mostrarlo al volver al castillo.
	if is_campaign and character == player_character:
		_demotion_text = "Caes en deshonra: de %s a %s." % [Character.role_name_for(old_role), Character.role_name_for(new_role)]

func _on_volver_menu_pressed() -> void:
	if _pending_next_round:
		CombatSetup.advance_tournament_round()
		get_tree().change_scene_to_file("res://scenes/combat/combat.tscn")
		return
	if is_campaign:
		var scene := CombatSetup.return_scene
		CombatSetup.clear()
		get_tree().change_scene_to_file(scene)
		return
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


# Teclado y mando: en tu turno el foco vuelve a «Atacar».
func _focus_attack() -> void:
	if not _action_buttons.is_empty() and not duel.is_over:
		_action_buttons[0].grab_focus.call_deferred()

func _set_buttons_enabled(enabled: bool) -> void:
	for b: Button in _action_buttons:
		b.disabled = not enabled
	for b: Button in _posture_buttons.values():
		b.disabled = not enabled

func _update_turn_indicator() -> void:
	if duel.is_over:
		return
	if player_turn:
		turn_indicator_label.text = "Tu turno"
	else:
		turn_indicator_label.text = "Turno de %s..." % enemy_character.full_name()
