extends Control

@export var player_character: Character
@export var enemy_character: Character

# Duelo singular dentro de una batalla (ver battle.gd): la escena va encima del tablero, no toca la
# campaña (CombatSetup) y al terminar avisa con embedded_finished en vez de cambiar de escena.
# player_character es quien lucha por tu bando (tú o el jefe de uno de tus pelotones).
signal embedded_finished(winner: Character)
var embedded := false
var _embedded_winner: Character

@onready var background: TextureRect = %TextureRect
@onready var portrait_player: TextureRect = %PortraitPlayer
@onready var portrait_enemy: TextureRect = %PortraitEnemy
@onready var btn_volver_menu: Button = %BtnVolverMenu
@onready var log_label: Label = %LogLabel
@onready var turn_indicator_label: Label = %TurnIndicatorLabel
@onready var hint_label: Label = %HintLabel
@onready var screen_margin: MarginContainer = %ScreenMargin

const ENEMY_TURN_DELAY := 1.2  # segundos de pausa antes de que el enemigo actúe
const DEFAULT_HINT := "Elige una postura y una acción."
const KO_SLOW_MO := 0.5        # segundos reales de cámara lenta en el golpe final
const HINT_MAX_LINES := 2   # la pista tiene altura fija: así no descoloca el menú al pasar el ratón

const HEALTH_COLOR := Color("a1342a")
const STAMINA_COLOR := Color("6b8a2a")
const MORALE_COLOR := Color("3f6d8a")
const TO_DEATH_COLOR := Color("e0503c")
const UniqueItems = preload("res://scripts/resources/unique_items.gd")

# [postura, nombre, tecla, descripción]
const POSTURES := [
	[CombatEnums.Posture.OFENSIVA, "Ofensiva", KEY_Q, "Más daño, menos defensa. No permite la Guardia."],
	[CombatEnums.Posture.DEFENSIVA, "Defensiva", KEY_W, "Menos daño recibido y una Guardia más firme. No permite Empujar."],
	[CombatEnums.Posture.ESGRIMA, "Esgrima", KEY_E, "Ágil: la Guardia esquiva más a menudo y desarmas mejor. No permite Empujar."],
	[CombatEnums.Posture.DESESPERADA, "Desesperada", KEY_R, "Último recurso: gran daño y poca defensa. Solo Atacar y Empujar."],
]
const ACTION_ABANDON := -1   # botón único que pregunta: rendirse o retirarse
# [acción, nombre, tecla, descripción]
const ACTIONS := [
	[CombatEnums.ActionType.ATACAR, "Atacar", KEY_1, "Golpea al oponente. Falla si estás desarmado."],
	[CombatEnums.ActionType.DEFENDER, "Guardia", KEY_2, "Reduces el próximo golpe y a veces lo evitas del todo (más en Esgrima)."],
	[CombatEnums.ActionType.CONTRAATACAR, "Contraatacar", KEY_3, "Esperas su golpe para pararlo y devolverlo."],
	[CombatEnums.ActionType.FINTA, "Finta", KEY_4, "Amagas un golpe. Si espera para contraatacar, pierde su parada y te deja la guardia abierta; si no, es un golpe flojo."],
	[CombatEnums.ActionType.DESARMAR, "Desarmar", KEY_5, "Intentas quitarle el arma un par de turnos."],
	[CombatEnums.ActionType.EMPUJAR, "Empujar", KEY_6, "Rompe su guardia y le quita aliento y moral."],
	[ACTION_ABANDON, "Abandonar…", KEY_7, "Rendirte o intentar retirarte del duelo."],
]

var duel: DuelManager
var player_turn := true
var _cards := {}                        # Character -> {name, role, bars, status, posture}
var _posture_buttons := {}              # postura -> Button
var _action_buttons: Array[Button] = []
var _key_bindings := {}                 # keycode -> Callable
var _hovered_order := ""                # orden bajo el ratón, para refrescar su previsión
var _enemy_intent := {}                 # jugada del rival ya decidida y adivinada por el jugador (Estrategia)
const READ_ICON := "👁 "
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
var _practice := false             # duelo de práctica con un compañero (RelationsData.start_practice)
var _practice_snapshot := {}       # Character -> estado previo: la práctica no hiere ni cuesta honor
const TOURNAMENT_FAME := 10
const CHAMPION_WIN_HONOR := 3
const CHAMPION_WIN_FAME := 2
const CHAMPION_LOSS_HONOR := -2
const CHAMPION_OWNER_XP_SHARE := 0.25   # parte de la experiencia del campeón que recibe su señor
const XpRules = preload("res://scripts/resources/xp_rules.gd")

func _ready() -> void:
	if player_character == null:
		player_character = CombatSetup.player_character if CombatSetup.player_character != null \
			else CharacterLoader.make_test_character("Sir Alaric", Character.Role.CABALLERO)
	if enemy_character == null:
		enemy_character = CombatSetup.enemy_character if CombatSetup.enemy_character != null \
			else CharacterLoader.make_test_character("Bandido Renco", Character.Role.SOLDADO)
	_owner = player_character
	_practice = CombatSetup.is_campaign and not embedded and RelationsData.is_practice() \
		and enemy_character.full_name() == RelationsData.practice_partner
	if _practice:
		for c: Character in [player_character, enemy_character]:
			_practice_snapshot[c] = {"honor": c.honor, "gold": c.gold, "role": c.role, "health": c.current_health,
				"won": c.duels_won, "lost": c.duels_lost, "wounds": c.wound_months}
	if CombatSetup.duel_to_death and not embedded:
		await _warn_to_death()
	# En campaña (no en torneos ni prácticas), un campeón de tu séquito puede batirse por ti.
	var champions: Array[Character] = []
	if CombatSetup.is_campaign and not CombatSetup.is_tournament() and GameManager.is_game_active and not embedded and not _practice:
		champions = RelationsData.duel_champions()
	if not champions.is_empty():
		var chosen: Character = await _ask_champion(champions)
		if chosen != _owner:
			_champion = chosen
			_champion.set_meta("champion", true)   # la IA del duelo sabe que es un luchador curtido
			player_character = chosen
	_begin()

# Aviso previo de un duelo a muerte: queda claro lo que está en juego antes del primer golpe.
func _warn_to_death() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.08, 0, 0, 0.75)
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
	title.text = "☠ DUELO A MUERTE contra %s" % enemy_character.full_name()
	title.add_theme_color_override("font_color", TO_DEATH_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var note := Label.new()
	note.text = "Aquí no hay cuartel: quien caiga, muere. Si caes tú, tu heredero tomará el relevo de la dinastía; si lucha un campeón por ti, es su vida la que arriesga. Aún puedes rendirte o retirarte durante el duelo, a costa de tu honor."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(560, 0)
	box.add_child(note)
	var btn := Button.new()
	btn.text = "Desenvainar"
	btn.theme_type_variation = &"PrimaryButton"
	box.add_child(btn)
	btn.grab_focus.call_deferred()
	Sfx.play("guard", -4.0)
	await btn.pressed
	overlay.queue_free()

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
	# El campeón designado (RelationsData.designated_champion) se destaca y lleva el foco.
	var preferred: Character = champions[0] if RelationsData.is_designated_champion(champions[0]) else _owner
	for c: Character in candidates:
		var card := VBoxContainer.new()
		card.add_child(FaceIcon.make(c, 110, Color("d4af5a") if c == preferred else FaceIcon.FRAME_COLOR))
		var btn := Button.new()
		btn.text = "Yo mismo" if c == _owner else (c.first_name + (" (campeón)" if c == preferred else ""))
		btn.tooltip_text = "%s · Combate %d, Defensa %d · Vida %d/%d" % [c.full_name(), c.combat, c.defense, c.current_health, c.max_health]
		btn.theme_type_variation = &"PrimaryButton" if c == preferred else &""
		btn.pressed.connect(func(): result[0] = c)
		card.add_child(btn)
		row.add_child(card)
		if c == preferred:
			btn.grab_focus.call_deferred()
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
	hint_label.max_lines_visible = HINT_MAX_LINES
	hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint_label.custom_minimum_size.y = hint_label.get_line_height() * HINT_MAX_LINES + 4
	portrait_player.texture = player_character.get_portrait()
	portrait_enemy.texture = enemy_character.get_portrait()
	_refresh_ui()
	_update_turn_indicator()

	is_campaign = CombatSetup.is_campaign and not embedded
	if embedded:
		btn_volver_menu.text = "Volver a la batalla"
		btn_volver_menu.disabled = true
		btn_volver_menu.tooltip_text = "Termina el duelo (o ríndete / retírate) para volver a la batalla."
		turn_log_buffer = "DUELO SINGULAR — %s contra %s, ante los dos ejércitos" % [player_character.full_name(), enemy_character.full_name()]
		log_label.text = turn_log_buffer
	_spoken[player_character] = {"hurt": false, "low": false, "cooldown": 0}
	_spoken[enemy_character] = {"hurt": false, "low": false, "cooldown": 0}
	_opening_lines()
	_focus_attack()
	if duel.roll_first(player_character, enemy_character) == enemy_character:
		_enemy_opens()
	else:
		_read_enemy()
		_refresh_ui()
	_update_action_blocks()
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
		elif _practice:
			turn_log_buffer = "DUELO DE PRÁCTICA contra %s — sin heridas ni honor en juego" % enemy_character.full_name()
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
	# Una sola línea de estado, de altura fija: así nunca encoge el retrato. El detalle va en el tooltip.
	refs.status = _label(box, "MutedLabel")
	refs.status.add_theme_font_size_override("font_size", 15)
	refs.status.autowrap_mode = TextServer.AUTOWRAP_OFF
	refs.status.clip_text = true
	refs.status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	refs.status.mouse_filter = Control.MOUSE_FILTER_PASS
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
		elif a[0] == ACTION_ABANDON:
			b.theme_type_variation = &"FlatButton"
		if b.theme_type_variation != &"":
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				b.remove_theme_stylebox_override(state)
			_compact(b)
		b.pressed.connect(_on_action_pressed.bind(a[0]))
		b.set_meta("action", a[0])
		b.set_meta("base_tooltip", b.tooltip_text)
		_action_buttons.append(b)
		_key_bindings[a[2]] = _on_action_pressed.bind(a[0])

func _order_button(parent: Node, text: String, key: Key, description: String) -> Button:
	var b := Button.new()
	b.text = text
	var key_name := OS.get_keycode_string(key)
	b.tooltip_text = "%s  [tecla %s]" % [description, key_name]
	b.focus_mode = Control.FOCUS_ALL    # mando y flechas; las teclas 1–7 / Q–R siguen siendo atajos
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
	var description := ""
	for list in [POSTURES, ACTIONS]:
		for entry in list:
			if entry[1] == order_name:
				base = "[%s] %s" % [OS.get_keycode_string(entry[2]), entry[1]]
				description = entry[3]
	if duel == null:
		return "%s — %s" % [base, description]
	var me := player_character
	var foe := enemy_character
	var extra := ""
	match order_name:
		"Atacar":
			var dmg := duel.preview_damage(me, foe)
			extra = "Daño previsto: %d–%d." % [dmg.x, dmg.y]
			if duel.countering[foe]:
				extra += " Prepara una parada (%d%%)." % roundi(duel.parry_chance(me, foe) * 100)
			elif duel.defending[foe] or duel.dodging[foe]:
				extra += " En guardia: mitad de daño o lo evita (%d%%)." % roundi(duel.guard_dodge_chance(me, foe) * 100)
			var my_adv: String = duel.advantage.get(me, "")
			if my_adv == DuelManager.ADV_CONTRA:
				extra += " ★ Contra: +50%, imparable."
			elif my_adv == DuelManager.ADV_ACECHO:
				extra += " ★ Acecho: +25% crítico."
			elif my_adv == DuelManager.ADV_ABIERTO:
				extra += " ★ Guardia abierta: +25%, imparable."
			if duel.is_predictable(me):
				extra += " Tercer golpe seguido: −15%."
			if duel.unbalanced.get(me, false):
				extra += " Desequilibrado: −20%."
		"Contraatacar":
			extra = "Probabilidad de parar su próximo golpe: %d%%." % roundi(duel.parry_chance(foe, me) * 100)
			if duel.advantage.get(foe, "") == duel.ADV_CONTRA:
				extra += " Su contra no se puede parar."
		"Guardia":
			extra = "Mitad de daño; evita el golpe entero un %d%%." % roundi(duel.guard_dodge_chance(foe, me) * 100)
		"Desarmar":
			extra = "Éxito: %d%%." % roundi(duel.disarm_chance(me, foe) * 100) if not duel.is_fatigued(me) else "Sin aliento."
			if duel.posture.get(me) == CombatEnums.Posture.ESGRIMA:
				extra += " Esgrima: +%d%%." % roundi(DuelManager.ESGRIMA_DISARM_BONUS * 100)
			if duel.advantage.get(me, "") == duel.ADV_DESEQUILIBRIO:
				extra += " ★ Rival desequilibrado: +25%."
		"Empujar":
			extra = "Éxito: %d%%. Rompe su guardia." % roundi(duel.push_chance(me, foe) * 100) if not duel.is_fatigued(me) else "Sin aliento."
		"Abandonar…":
			extra = "Retirarte: %d%% de éxito (cuesta honor), o rendirte." % roundi(duel.retreat_chance(me, foe) * 100)
		"Finta":
			if duel.is_fatigued(me):
				extra = "Sin aliento."
			elif duel.countering[foe]:
				extra = "¡Espera para parar! Su parada se pierde y tu próximo golpe es imparable (+25%)."
			else:
				extra = "Si está en contraataque: su parada se pierde y tu próximo golpe es imparable (+25%). Si no, golpe flojo (−50%)."
	for entry in ACTIONS:
		if entry[1] == order_name and not duel.can_act(me, entry[0]):
			extra = "✖ " + CombatEnums.block_reason(duel.posture[me], entry[0])
	return "%s: %s" % [base, extra.strip_edges()] if not extra.is_empty() else "%s — %s" % [base, description]

# Menos relleno lateral que un botón normal: caben 4 posturas y 4 acciones por fila.
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
	_update_action_blocks()

func _on_action_pressed(action: int) -> void:
	if action == ACTION_ABANDON:
		_ask_abandon()
	else:
		_player_action(action)

# «Abandonar…»: rendirse (seguro, cuesta honor) o intentar retirarse (puede fallar).
func _ask_abandon() -> void:
	if not player_turn or duel == null or duel.is_over:
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Abandonar el duelo"
	dlg.dialog_text = "Retirarte: %d%% de éxito, cuesta honor.\nRendirte: terminas ya, pierdes el duelo." % roundi(duel.retreat_chance(player_character, enemy_character) * 100)
	dlg.ok_button_text = "Rendirse"
	dlg.cancel_button_text = "Seguir luchando"
	dlg.add_button("Retirarse", true, "retreat")
	dlg.confirmed.connect(func(): _player_action(CombatEnums.ActionType.RENDIRSE))
	dlg.custom_action.connect(func(_a): dlg.hide(); _player_action(CombatEnums.ActionType.RETIRARSE))
	dlg.visibility_changed.connect(func(): if not dlg.visible: dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()
	dlg.get_cancel_button().grab_focus.call_deferred()

func _player_action(action: int) -> void:
	if not player_turn or duel.is_over:
		return
	if not duel.can_act(player_character, action):
		Sfx.play("whoosh", -10.0)
		hint_label.text = CombatEnums.block_reason(duel.posture[player_character], action)
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
	# Si el jugador leyó su jugada, el rival ya está comprometido con ella (salvo que lo hayan desarmado).
	var choice: Dictionary = _enemy_intent
	_enemy_intent = {}
	if choice.is_empty() or (CombatEnums.Status.DESARMADO in duel.statuses[enemy_character] \
			and choice.action in [CombatEnums.ActionType.ATACAR, CombatEnums.ActionType.DESARMAR]):
		choice = DuelAI.choose(duel, enemy_character, player_character)
	duel.set_posture(enemy_character, choice.posture)
	duel.take_turn(enemy_character, choice.action)
	for c: Character in _spoken:
		_spoken[c].cooldown -= 1

	player_turn = true
	_read_enemy()
	_refresh_ui()
	_set_buttons_enabled(not duel.is_over)
	_focus_attack()
	_update_turn_indicator()

# Estrategia: al empezar tu turno puedes adivinar qué hará el rival. Si lo adivinas, el rival ya
# ha decidido su jugada y la mantendrá (ver _enemy_turn).
func _read_enemy() -> void:
	_enemy_intent = {}
	if duel.is_over or randf() >= duel.read_chance(player_character, enemy_character):
		return
	_enemy_intent = DuelAI.choose(duel, enemy_character, player_character)
	turn_log_buffer += "\n%s%s" % [READ_ICON, DuelManager.intent_text(_enemy_intent)]
	log_label.text = turn_log_buffer

# Las acciones que la postura actual no permite se ven apagadas, con el motivo en la ayuda.
func _update_action_blocks() -> void:
	if duel == null:
		return
	var p: int = duel.posture.get(player_character, CombatEnums.Posture.DEFENSIVA)
	for b: Button in _action_buttons:
		var action: int = b.get_meta("action")
		var reason := CombatEnums.block_reason(p, action)
		b.disabled = not reason.is_empty() or not player_turn or duel.is_over
		if not reason.is_empty():
			b.tooltip_text = "%s\n✖ %s" % [b.get_meta("base_tooltip"), reason]
		else:
			b.tooltip_text = b.get_meta("base_tooltip")

func _refresh_ui() -> void:
	for c: Character in [player_character, enemy_character]:
		var refs: Dictionary = _cards[c]
		refs.name.text = c.full_name()
		refs.role.text = c.role_name()
		_set_bar(refs.bars.health, c.current_health, c.max_health)
		_set_bar(refs.bars.stamina, c.current_stamina, c.max_stamina)
		_set_bar(refs.bars.morale, c.current_morale, c.max_morale)
		# Línea corta con iconos (postura · guardia · ventaja · desequilibrio · estados); detalle en el tooltip.
		var short: Array[String] = [CombatEnums.posture_name(duel.posture.get(c, CombatEnums.Posture.DEFENSIVA))]
		var detail: Array[String] = ["Postura: " + short[0]]
		var guard := duel.guard_text(c)
		if not guard.is_empty():
			short.append("⚑")
			detail.append("⚑ " + guard)
		var adv := duel.advantage_text(c)
		if not adv.is_empty():
			short.append("★")
			detail.append("★ Ventaja: " + adv)
		if duel.unbalanced.get(c, false):
			short.append("↯")
			detail.append("↯ Desequilibrado: su próximo golpe hace −20%")
		var statuses: Array = duel.statuses.get(c, [])
		if not statuses.is_empty():
			short.append(_status_text(statuses))
			detail.append(_status_text(statuses))
		refs.status.text = " · ".join(short)
		refs.status.tooltip_text = "\n".join(detail)
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
	CombatFx.squash(portrait, 0.05 + strength * 0.005)
	CombatFx.sparks(self, _portrait_center(c) - global_position, Color(1.0, 0.85, 0.4), spark_amount)
	CombatFx.shake(screen_margin, strength, 0.25)

const ADVANTAGE_FLOATS := {"contra": "¡Contra lista!", "acecho": "¡Al acecho!", "desequilibrio": "¡Desequilibrado!", "abierto": "¡Guardia abierta!"}

# El que ataca embiste hacia su rival (los retratos están enfrentados: izquierda contra derecha).
func _lunge(actor: Character) -> void:
	var dir := Vector2.RIGHT if actor == player_character else Vector2.LEFT
	CombatFx.lunge(_portrait_of(actor), dir, 26.0)

# Golpe con su nivel: sacudida y pausa de impacto según el daño.
func _tiered_hit(actor: Character, target: Character, amount: int, extra: int = 0) -> void:
	var tier := mini(CombatFx.tier_for(amount) + extra, CombatFx.Tier.BIG)
	_lunge(actor)
	_impact(target, CombatFx.TIER_SHAKE[tier], 16 + tier * 16)
	CombatFx.hit_stop(get_tree(), CombatFx.TIER_HIT_STOP[tier])

func _on_combat_event(kind: String, actor: Character, target: Character, amount: int) -> void:
	if kind in ["hit", "crit", "parry", "parry_fail"]:
		_maybe_taunt(kind, actor, target)
	match kind:
		"hit":
			Sfx.play("clash", -4.0)
			Sfx.play("hit")
			_tiered_hit(actor, target, amount)
			_float(target, "-%d" % amount, CombatFx.DAMAGE_COLOR, 30 + CombatFx.tier_for(amount) * 6)
		"crit":
			Sfx.play("crit")
			_tiered_hit(actor, target, amount, 2)
			_float(target, "¡CRÍTICO! -%d" % amount, CombatFx.CRIT_COLOR, 44)
		"parry":
			# El acero choca primero y la respuesta llega justo después: dos impactos.
			Sfx.play("clash")
			CombatFx.flash(_portrait_of(actor), Color(1.7, 1.55, 0.8), 0.35)
			_float(actor, "¡Parada!", CombatFx.CRIT_COLOR, 30)
			CombatFx.sparks(self, _portrait_center(actor) - global_position, Color(1.0, 0.95, 0.7), 30)
			await get_tree().create_timer(0.3).timeout
			Sfx.play("hit", -2.0)
			_tiered_hit(actor, target, amount, 1)
			_float(target, "Respuesta -%d" % amount, CombatFx.DAMAGE_COLOR, 30)
		"parry_fail":
			Sfx.play("clash", -6.0)
			Sfx.play("hit")
			_tiered_hit(actor, target, amount)
			_float(target, "Parada fallida -%d" % amount, CombatFx.DAMAGE_COLOR, 28)
		"feint":
			Sfx.play("whoosh", -3.0)
			_lunge(actor)
			CombatFx.flash(_portrait_of(target), Color(1.6, 1.4, 0.7), 0.3)
			_float(target, "¡Parada en falso!", CombatFx.MISS_COLOR, 28)
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
			_lunge(actor)
			CombatFx.lunge(_portrait_of(target), Vector2.LEFT if target == player_character else Vector2.RIGHT, 30.0)
			CombatFx.flash(_portrait_of(target), Color(0.75, 0.95, 1.7), 0.3)
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
			_tiered_hit(actor, target, 10)
			_float(target, "¡Desarmado!", CombatFx.CRIT_COLOR, 36)
		"push":
			Sfx.play("push")
			_lunge(actor)
			CombatFx.squash(_portrait_of(target), 0.2)
			CombatFx.shake(screen_margin, 8.0, 0.2)
			_float(target, "¡Empujón!", CombatFx.DAMAGE_COLOR, 28)
		"miss":
			Sfx.play("whoosh")
			_lunge(actor)
			_float(target, "Falla", CombatFx.MISS_COLOR, 28)
		"advantage":
			# Llega justo después del golpe que la provocó: se muestra un poco más tarde y más arriba.
			await get_tree().create_timer(0.45).timeout
			Sfx.stinger("crit", -8.0, 0.5)
			CombatFx.flash(_portrait_of(actor), Color(1.7, 1.5, 0.6), 0.5)
			var adv_text: String = "★ " + ADVANTAGE_FLOATS.get(duel.advantage.get(actor, ""), "¡Ventaja!")
			CombatFx.banner(self, adv_text, CombatFx.CRIT_COLOR, 30, 0.6, _banner_area())
		"retreat_fail":
			Sfx.play("guard", -4.0)
			_float(actor, "¡No logra huir!", CombatFx.MISS_COLOR, 28)

# Los carteles salen sobre el registro central (no tapan los botones ni los retratos).
func _banner_area() -> Rect2:
	return (log_label.get_parent() as Control).get_global_rect()

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
	if embedded:
		_embedded_winner = winner
		if winner != null and player_character.is_alive():
			var xp_text := _xp_line(player_character, XpRules.BATTLE_DUEL_WIN if winner == player_character else XpRules.BATTLE_DUEL_LOSS)
			if not xp_text.is_empty():
				turn_log_buffer += "\n" + xp_text
				log_label.text = turn_log_buffer
		btn_volver_menu.disabled = false
		btn_volver_menu.tooltip_text = ""
		btn_volver_menu.grab_focus.call_deferred()
		return

	if is_campaign and _practice:
		_end_practice(winner)
		return
	if is_campaign:
		# La rivalidad se registra antes del resumen: vencer a un rival conocido suma honor.
		# Los combates de evento contra bandidos y similares no crean rivalidades.
		var event_foe: bool = CombatSetup.pending_outcome.get("no_rival", false)
		var event_fight := not CombatSetup.pending_outcome.is_empty()
		var death := _resolve_death(winner)
		var rivalry := "" if event_foe else RelationsData.register_duel(enemy_character, winner == player_character, winner == null)
		var outcome := CombatSetup.apply_outcome(winner == player_character)
		if not outcome.is_empty():
			rivalry = (rivalry + " " + outcome).strip_edges()
		rivalry += _champion_outcome(winner)
		if MissionData.has_method("on_duel_finished"):
			MissionData.on_duel_finished(enemy_character, winner == player_character)
		rivalry = " ".join([rivalry, death, _award_xp(winner, event_fight)]).strip_edges()
		# Fuera de los torneos, un duelo hostil puede acabar con el vencido preso del vencedor.
		if not CombatSetup.is_tournament():
			var caught := CaptureData.after_duel(_owner, player_character, enemy_character, winner, event_fight or _hostile_foe())
			if not caught.is_empty():
				rivalry = (rivalry + " " + caught).strip_edges()
				if CaptureData.is_captive():
					CombatSetup.return_scene = "res://scenes/map/map.tscn"
		btn_volver_menu.disabled = false
		btn_volver_menu.tooltip_text = ""
		if CombatSetup.is_tournament():
			_tournament_round_ended(winner, rivalry)
			return
		# Las heridas ya no se curan solas al terminar: la vida se recupera con los meses.
		var wound := player_character.after_fight_recovery() if _champion == null and player_character.is_alive() else ""
		CombatSetup.last_result_text = " ".join([_campaign_summary(winner), rivalry, wound]).strip_edges()
		if winner == player_character and not event_foe:
			_offer_trophy()

## ¿Es un enemigo de verdad (rival enconado, némesis o de un reino en guerra con el tuyo)?
func _hostile_foe() -> bool:
	var r := RelationsData.get_relation(enemy_character.full_name())
	if r == null:
		return false
	if r.at_war or r.rivalry_stage() in [Relationship.RivalryStage.RIVAL, Relationship.RivalryStage.NEMESIS]:
		return true
	return r.kingdom >= 0 and GameManager.player_kingdom >= 0 \
		and KingdomDiplomacy.at_war(RelationsData.kingdom_wars, r.kingdom, GameManager.player_kingdom)

# Práctica con un compañero: se deshace lo que el duelo haya cambiado (vida, honor, rescate, récord)
# y solo quedan la experiencia y la confianza (RelationsData.finish_practice).
func _end_practice(winner: Character) -> void:
	for c: Character in _practice_snapshot:
		var s: Dictionary = _practice_snapshot[c]
		c.honor = s.honor
		c.gold = s.gold
		c.role = s.role
		c.current_health = s.health
		c.duels_won = s.won
		c.duels_lost = s.lost
		c.wound_months = s.wounds
	_demotion_text = ""
	var text := RelationsData.finish_practice(winner == player_character, winner == null)
	CombatSetup.last_result_text = text
	turn_log_buffer += "\n" + text
	log_label.text = turn_log_buffer
	btn_volver_menu.disabled = false
	btn_volver_menu.tooltip_text = ""
	btn_volver_menu.grab_focus.call_deferred()

# Trofeo: si el vencido lleva una pieza única, el jugador puede reclamarla (cuesta honor y el vencido
# guarda rencor) o dejarla estar. Lo decide en una ventana al terminar el duelo.
func _offer_trophy() -> void:
	var item := UniqueItems.carried_by(enemy_character)
	var taker: Character = _owner if _owner != null else player_character
	if item == null or taker == null:
		return
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
	title.text = "%s lleva %s" % [enemy_character.full_name(), item.equipment_name]
	title.add_theme_color_override("font_color", Color("f0c060"))
	box.add_child(title)
	var note := Label.new()
	note.text = "%s\n\nPuedes reclamarla como trofeo: es tu derecho de vencedor, pero no es de caballeros (−%d de honor) y %s no lo olvidará (+%d de rencor)." % [
		item.description, UniqueItems.TROPHY_HONOR_COST, enemy_character.full_name(), UniqueItems.TROPHY_GRUDGE]
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(560, 0)
	box.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var claim := Button.new()
	claim.text = "Reclamar el trofeo"
	claim.theme_type_variation = &"PrimaryButton"
	row.add_child(claim)
	var leave := Button.new()
	leave.text = "Dejarla estar"
	row.add_child(leave)
	claim.pressed.connect(func():
		var text := UniqueItems.claim_trophy(taker, enemy_character)
		CombatSetup.last_result_text = (CombatSetup.last_result_text + " " + text).strip_edges()
		turn_log_buffer += "\n" + text
		log_label.text = turn_log_buffer
		overlay.queue_free())
	leave.pressed.connect(func(): overlay.queue_free())
	leave.grab_focus.call_deferred()

# Duelo a muerte: quien cae (vida a 0) muere. Rendirse o huir salva la vida.
func _resolve_death(winner: Character) -> String:
	if not CombatSetup.duel_to_death or winner == null:
		return ""
	var loser := duel.opponent_of(winner)
	if loser.is_alive():
		return ""
	var cause := "en un duelo a muerte contra %s" % winner.full_name()
	if loser == _owner:
		if DynastyData.has_method("on_player_died"):
			DynastyData.on_player_died(cause)
		CombatSetup.return_scene = "res://scenes/map/map.tscn"   # el mapa abre la sucesión
		btn_volver_menu.text = "Volver al Mapa"
		turn_log_buffer += "\n☠ %s muere %s." % [loser.full_name(), cause]
		log_label.text = turn_log_buffer
		return "☠ Has muerto %s. Tu dinastía buscará un heredero." % cause
	if RelationsData.has_method("on_character_died"):
		RelationsData.on_character_died(loser.full_name(), "duelo a muerte")
	turn_log_buffer += "\n☠ %s muere %s." % [loser.full_name(), cause]
	log_label.text = turn_log_buffer
	if loser == _champion:
		return "☠ Tu campeón %s muere en el duelo." % loser.full_name()
	return "☠ %s muere a tus pies." % loser.full_name() if _champion == null else "☠ %s muere a manos de tu campeón." % loser.full_name()

# Experiencia del duelo (ver XpRules): para quien luchó; si fue un campeón, su señor recibe una parte.
func _award_xp(winner: Character, event_fight: bool) -> String:
	var fighter := player_character
	if winner == null or not fighter.is_alive():
		return ""
	var won := winner == fighter
	var amount: int
	if CombatSetup.is_tournament():
		amount = XpRules.TOURNAMENT_ROUND if won else XpRules.DUEL_LOSS
		if won and CombatSetup.is_final_round():
			amount += XpRules.TOURNAMENT_CHAMPION
	elif won:
		amount = XpRules.DUEL_WIN + XpRules.DUEL_RANK_BONUS * maxi(0, enemy_character.rank() - fighter.rank())
		if event_fight:
			amount += XpRules.EVENT_FIGHT_WIN
	else:
		amount = XpRules.DUEL_LOSS
	var text := _xp_line(fighter, amount)
	if _champion != null and _owner.is_alive():
		text += " " + _xp_line(_owner, roundi(amount * CHAMPION_OWNER_XP_SHARE))
	return text.strip_edges()

func _xp_line(c: Character, amount: int) -> String:
	if amount <= 0:
		return ""
	var levels := c.gain_xp(amount, XpRules.SOURCE_DUEL)
	amount = c.last_xp_gained
	if amount <= 0:
		return ""
	var who := "" if c == _owner else c.first_name + ": "
	if levels > 0:
		return "%sExperiencia +%d. ¡Sube a nivel %d!" % [who, amount, c.level]
	return "%sExperiencia +%d." % [who, amount]

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
	CombatFx.slow_mo(get_tree(), KO_SLOW_MO)
	await get_tree().create_timer(0.5).timeout   # deja sonar el último golpe
	Sfx.stinger("victory" if won else "defeat", 0.0, 2.5)
	CombatFx.banner(self, "¡Victoria!" if won else "Derrota",
		CombatFx.CRIT_COLOR if won else CombatFx.DAMAGE_COLOR, 46, 1.2, _banner_area())
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
		if randf() < UniqueItems.TOURNAMENT_CHANCE:   # a veces el premio del campeón es una pieza única
			var prize := UniqueItems.grant(player_character)
			if not prize.is_empty():
				text += " " + prize
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
	if embedded:
		embedded_finished.emit(_embedded_winner)
		return
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
	if enabled:
		_update_action_blocks()

func _update_turn_indicator() -> void:
	if duel.is_over:
		return
	if player_turn:
		turn_indicator_label.text = "Tu turno"
	else:
		turn_indicator_label.text = "Turno de %s..." % enemy_character.full_name()
	if CombatSetup.duel_to_death and not embedded:
		turn_indicator_label.text = "☠ A MUERTE · " + turn_indicator_label.text
