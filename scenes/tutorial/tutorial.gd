extends Control
# Tutorial de combate: lecciones con el DuelManager y el BattleManager reales.
# El rival sigue un guion (postura y acción fijas por paso) para que cada lección muestre
# un caso concreto; lo que ocurre se explica con los números reales de la jugada.

const MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"
const BattleBoardScript = preload("res://scenes/battle/battle_board.gd")
const BattleUnitScript = preload("res://scripts/resources/battle_unit.gd")
const BOARD_SCALE := 0.62

const A := CombatEnums.ActionType
const P := CombatEnums.Posture
const U := BattleEnums.UnitType
const T := BattleEnums.Terrain

static var return_scene := ""   # escena a la que vuelve «Volver» (por defecto, el menú)

@onready var lessons_box: VBoxContainer = %LessonsBox
@onready var lesson_title: Label = %LessonTitle
@onready var step_label: Label = %StepLabel
@onready var step_counter: Label = %StepCounter
@onready var arena: Control = %Arena
@onready var result_label: Label = %ResultLabel
@onready var result_panel: PanelContainer = %ResultPanel
@onready var btn_next: Button = %BtnNext
@onready var btn_retry: Button = %BtnRetry
@onready var btn_back: Button = %BtnBack

var lessons: Array = []
var _lesson: Dictionary = {}
var _lesson_index := -1
var _step := 0
var _lesson_buttons: Array[Button] = []

# --- Duelo ---
var duel: DuelManager
var player: Character
var enemy: Character
var _log: Array[String] = []
var _chosen_posture: int = P.DEFENSIVA
var _posture_buttons := {}
var _action_buttons := {}
var _player_card: Label
var _enemy_card: Label
var _player_portrait: TextureRect
var _enemy_portrait: TextureRect
var _awaiting_input := false

# --- Batalla ---
var battle: BattleManager
var board: Control

func _ready() -> void:
	lessons = _build_lessons()
	var group := ButtonGroup.new()
	for i in lessons.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, lessons[i].title]
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = &"FlatButton"
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(start_lesson.bind(i))
		lessons_box.add_child(b)
		_lesson_buttons.append(b)
	btn_next.pressed.connect(_on_next)
	btn_retry.pressed.connect(func(): start_lesson(_lesson_index))
	btn_back.pressed.connect(_on_back)
	start_lesson(0)

func _on_back() -> void:
	Engine.time_scale = 1.0
	var scene := return_scene if not return_scene.is_empty() else MENU_SCENE
	return_scene = ""
	get_tree().change_scene_to_file(scene)

# =====================================================================
# Lecciones
# =====================================================================

func _build_lessons() -> Array:
	return [
		{"title": "Daño y posturas", "kind": "duel",
			"intro": "Cada golpe hace 24 × A/(A+D), ±20%. La postura suma a tu ataque (A) o a tu defensa (D).",
			"player": [8, 6], "enemy": [8, 6, Character.Personality.LEAL],
			"steps": [
				{"text": "Elige la postura Ofensiva (+4 ataque, −1 defensa) y ataca. Antes de actuar, mira el daño previsto.",
					"posture": P.OFENSIVA, "action": A.ATACAR, "enemy": [P.DEFENSIVA, A.ATACAR]},
				{"text": "Ahora prueba Defensiva (−1 ataque, +4 defensa) y ataca: harás menos daño, pero su golpe te dolerá menos.",
					"posture": P.DEFENSIVA, "action": A.ATACAR, "enemy": [P.OFENSIVA, A.ATACAR]},
				{"text": "Desesperada (+6 ataque, −3 defensa): el máximo daño… y la máxima exposición.",
					"posture": P.DESESPERADA, "action": A.ATACAR, "enemy": [P.OFENSIVA, A.ATACAR]},
			]},
		{"title": "La Guardia y el aliento", "kind": "duel",
			"intro": "Atacar gasta 15 de aliento y recuperas 5 por turno. La Guardia recupera 25 y reduce a la mitad el próximo golpe.",
			"player": [8, 6], "enemy": [8, 6, Character.Personality.AMBICIOSO], "player_stamina": 25,
			"steps": [
				{"text": "Te queda poco aliento. Si sigues atacando quedarás Fatigado. Defiéndete.",
					"posture": P.DEFENSIVA, "action": A.DEFENDER, "enemy": [P.OFENSIVA, A.ATACAR]},
				{"text": "Con el aliento recuperado, vuelve a atacar.",
					"posture": P.OFENSIVA, "action": A.ATACAR, "enemy": [P.DEFENSIVA, A.ATACAR]},
			]},
		{"title": "Empujar rompe la guardia", "kind": "duel",
			"intro": "La Guardia y la parada duran hasta el próximo turno de quien las prepara. Empujar las rompe.",
			"player": [8, 6], "enemy": [8, 6, Character.Personality.PRUDENTE],
			"steps": [
				{"enemy_first": [P.DEFENSIVA, A.CONTRAATACAR],
					"text": "El rival espera para parar tu golpe y devolvértelo. Si atacas te arriesgas. Empújalo: su parada se pierde y le quitas 20 de aliento.",
					"posture": P.OFENSIVA, "action": A.EMPUJAR, "enemy": [P.DEFENSIVA, A.DEFENDER]},
				{"text": "Vuelve a ponerse en guardia. Empujar otra vez lo deja sin aliento… pero esta vez ataca: el golpe atravesará media guardia.",
					"posture": P.OFENSIVA, "action": A.ATACAR, "enemy": [P.DEFENSIVA, A.ATACAR]},
			]},
		{"title": "Contraatacar: la parada", "kind": "duel",
			"intro": "Contraatacar espera el golpe del rival: 55% (± diferencia de Combate) de no recibir nada y devolver un golpe ×1,25.",
			"player": [8, 6], "enemy": [8, 6, Character.Personality.ARROGANTE],
			"steps": [
				{"text": "Tu rival es arrogante: ataca sin pausa. Espéralo con una parada.",
					"posture": P.DEFENSIVA, "action": A.CONTRAATACAR, "enemy": [P.OFENSIVA, A.ATACAR]},
				{"text": "Otra vez: contra quien solo ataca, parar sale a cuenta aunque a veces falle.",
					"posture": P.DEFENSIVA, "action": A.CONTRAATACAR, "enemy": [P.OFENSIVA, A.ATACAR]},
				{"text": "Pero cuidado: si el rival empuja en vez de atacar, tu parada no sirve de nada.",
					"posture": P.DEFENSIVA, "action": A.CONTRAATACAR, "enemy": [P.OFENSIVA, A.EMPUJAR]},
			]},
		{"title": "Guardia y Esgrima", "kind": "duel",
			"intro": "La Guardia, además de reducir el golpe, a veces lo evita del todo: un 15% en Defensiva y un 40% en Esgrima (más si superas al rival en Combate).",
			"player": [9, 5], "enemy": [8, 6, Character.Personality.AMBICIOSO],
			"steps": [
				{"text": "Adopta Esgrima y ponte en Guardia: es la postura que más esquiva.",
					"posture": P.ESGRIMA, "action": A.DEFENDER, "enemy": [P.OFENSIVA, A.ATACAR]},
				{"text": "Ahora la Guardia en Defensiva: esquiva menos, pero el golpe que entra duele menos.",
					"posture": P.DEFENSIVA, "action": A.DEFENDER, "enemy": [P.OFENSIVA, A.ATACAR]},
			]},
		{"title": "Desarmar", "kind": "duel",
			"intro": "Desarmar deja al rival sin poder atacar 2 turnos. La probabilidad depende de tu Combate frente a su Defensa.",
			"player": [11, 5], "enemy": [8, 5, Character.Personality.LEAL],
			"steps": [
				{"text": "Tu Combate supera su Defensa: intenta desarmarlo.",
					"posture": P.OFENSIVA, "action": A.DESARMAR, "enemy": [P.OFENSIVA, A.ATACAR]},
				{"text": "Si lo lograste, no puede atacarte: aprovecha para golpear.",
					"posture": P.OFENSIVA, "action": A.ATACAR, "enemy": [P.DEFENSIVA, A.ATACAR]},
			]},
		{"title": "La fatiga", "kind": "duel",
			"intro": "Por debajo del 20% de aliento estás Fatigado: −30% de daño, esquivas la mitad y no puedes desarmar ni empujar.",
			"player": [8, 6], "enemy": [8, 6, Character.Personality.LEAL], "player_stamina": 28,
			"steps": [
				{"text": "Ataca una vez más con el poco aliento que te queda y fíjate en el daño.",
					"posture": P.OFENSIVA, "action": A.ATACAR, "enemy": [P.DEFENSIVA, A.ATACAR]},
				{"text": "Fatigado, intenta empujar…",
					"posture": P.OFENSIVA, "action": A.EMPUJAR, "enemy": [P.OFENSIVA, A.ATACAR]},
				{"text": "No puedes. Defiéndete para recuperar el aliento.",
					"posture": P.DEFENSIVA, "action": A.DEFENDER, "enemy": [P.OFENSIVA, A.ATACAR]},
			]},
		{"title": "Posturas que comprometen", "kind": "duel",
			"intro": "Cada postura cierra alguna acción: Ofensiva no deja la Guardia; Defensiva y Esgrima no dejan Empujar; Desesperada solo deja Atacar y Empujar. Abandonar siempre se puede.",
			"player": [8, 6], "enemy": [8, 6, Character.Personality.ARROGANTE],
			"steps": [
				{"text": "Elige Defensiva: fíjate en que Empujar se apaga. Espera su golpe con una parada.",
					"posture": P.DEFENSIVA, "action": A.CONTRAATACAR, "enemy": [P.OFENSIVA, A.ATACAR]},
				{"text": "Ahora Esgrima: no puedes empujar, pero desarmas mejor (+10%). Intenta desarmarlo.",
					"posture": P.ESGRIMA, "action": A.DESARMAR, "enemy": [P.OFENSIVA, A.ATACAR]},
				{"text": "Desesperada lo apuesta todo: solo Atacar o Empujar. Ataca con todo.",
					"posture": P.DESESPERADA, "action": A.ATACAR, "enemy": [P.DEFENSIVA, A.ATACAR]},
			]},
		{"title": "Leer al rival", "kind": "duel",
			"intro": "Con buena Estrategia, al empezar tu turno puedes adivinar la próxima jugada del rival (👁 «Parece que va a desarmarte»). Si la adivinas, el rival la mantiene: aprovéchalo. La probabilidad sube con tu Estrategia frente a la suya y con Lectura del Rival.",
			"player": [8, 6], "enemy": [8, 6, Character.Personality.ARROGANTE],
			"steps": [
				{"text": "Has leído que va a atacarte en postura Ofensiva. Espéralo con una parada.",
					"posture": P.DEFENSIVA, "action": A.CONTRAATACAR, "enemy": [P.OFENSIVA, A.ATACAR]},
				{"enemy_first": [P.DEFENSIVA, A.CONTRAATACAR],
					"text": "Leíste bien: se ha quedado esperando para parar. Empújalo para romper su parada… pero en Defensiva no se puede empujar. Cambia a Ofensiva y empuja.",
					"posture": P.OFENSIVA, "action": A.EMPUJAR, "enemy": [P.DEFENSIVA, A.DEFENDER]},
			]},
		{"title": "Rendirse y huir", "kind": "duel",
			"intro": "Huir puede fallar y cuesta 3 de honor si sale bien. Rendirse es una derrota segura: −5 de honor, −3 extra y 25 de oro de rescate, pero evita caer herido.",
			"player": [8, 6], "enemy": [10, 7, Character.Personality.ARROGANTE], "player_health": 18,
			"steps": [
				{"text": "Estás al borde de caer. Intenta huir (mira la probabilidad).",
					"posture": P.DEFENSIVA, "action": A.RETIRARSE, "enemy": [P.OFENSIVA, A.ATACAR]},
				{"text": "Si no lo lograste, ríndete antes de caer: caer en duelo te deja herido varios meses.",
					"posture": P.DEFENSIVA, "action": A.RENDIRSE, "enemy": [P.OFENSIVA, A.ATACAR]},
			]},
		{"title": "Cómo pelea cada personalidad", "kind": "ai",
			"intro": "El rival elige según su carácter y se adapta a ti. Aquí cada personalidad pelea 5 turnos contra alguien que solo ataca: fíjate cómo empiezan a esperarte con paradas.",
			"steps": [{"text": "Pulsa «Simular de nuevo» para ver otra pelea: las decisiones tienen algo de azar."}]},
		{"title": "Batalla: tipos de pelotón", "kind": "battle",
			"intro": "Un círculo de ventajas: caballería > arqueros > infantería > piqueros > caballería. Quien ataca a su presa hace un 30% más; caballería contra infantería y arqueros contra piqueros luchan sin ventaja. ★ marca la versión avanzada de cada familia.",
			"steps": [
				{"text": "Tu caballería carga contra unos arqueros: los arqueros no responden en el cuerpo a cuerpo.",
					"setup": [[U.CABALLERIA, Vector2i(4, 3), T.LLANO], [U.ARQUEROS, Vector2i(5, 3), T.LLANO]]},
				{"text": "Tus piqueros frenan a la caballería enemiga: el muro de picas le hace más daño y aguanta su respuesta.",
					"setup": [[U.PIQUEROS, Vector2i(4, 3), T.LLANO], [U.CABALLERIA, Vector2i(5, 3), T.LLANO]]},
				{"text": "Tus arqueros disparan a la infantería desde 3 casillas: nadie les responde.",
					"setup": [[U.ARQUEROS, Vector2i(2, 3), T.LLANO], [U.INFANTERIA, Vector2i(5, 3), T.LLANO]]},
				{"text": "Tu infantería se mete entre las picas: contra los piqueros es la que manda.",
					"setup": [[U.INFANTERIA, Vector2i(4, 3), T.LLANO], [U.PIQUEROS, Vector2i(5, 3), T.LLANO]]},
			]},
		{"title": "Batalla: terreno, murallas y moral", "kind": "battle",
			"intro": "El terreno del defensor reduce las bajas: Bosque +25% de defensa, Colina +20%, Muralla +50%. Un pelotón con moral por debajo de 25 huye.",
			"steps": [
				{"text": "Infantería contra infantería en llano: la referencia.",
					"setup": [[U.INFANTERIA, Vector2i(4, 3), T.LLANO], [U.INFANTERIA, Vector2i(5, 3), T.LLANO]]},
				{"text": "El mismo ataque contra un pelotón en el bosque.",
					"setup": [[U.INFANTERIA, Vector2i(4, 3), T.LLANO], [U.INFANTERIA, Vector2i(5, 3), T.BOSQUE]]},
				{"text": "Y contra un pelotón tras la muralla: por eso hace falta ~1,5 veces la guarnición para tomar un castillo.",
					"setup": [[U.INFANTERIA, Vector2i(4, 3), T.LLANO], [U.INFANTERIA, Vector2i(5, 3), T.MURALLA]]},
				{"text": "Este pelotón enemigo está desmoralizado (moral 32). Un buen golpe lo hará huir. Los compañeros de tu séquito que encabezan pelotones los hacen más fuertes y aguantan mejor la moral.",
					"setup": [[U.INFANTERIA, Vector2i(4, 3), T.LLANO], [U.INFANTERIA, Vector2i(5, 3), T.LLANO]], "enemy_morale": 32},
			]},
	]

# =====================================================================
# Flujo
# =====================================================================

func start_lesson(index: int) -> void:
	Engine.time_scale = 1.0
	_lesson_index = index
	_lesson = lessons[index]
	# Marcar sin señal no pasa por el ButtonGroup: se desmarcan las demás a mano.
	for i in _lesson_buttons.size():
		_lesson_buttons[i].set_pressed_no_signal(i == index)
	_step = 0
	lesson_title.text = _lesson.title
	result_panel.visible = false
	for child in arena.get_children():
		child.queue_free()
	match _lesson.kind:
		"duel":
			_setup_duel()
		"battle":
			pass
		"ai":
			_run_ai_demo()
	_show_step()
	UiAnim.fade_in(arena, 0.25)

func _steps() -> Array:
	return _lesson.steps

func _show_step() -> void:
	var steps := _steps()
	step_counter.text = "Paso %d de %d" % [_step + 1, steps.size()]
	var step: Dictionary = steps[_step]
	var text: String = step.text
	if _step == 0:
		text = "%s\n\n%s" % [_lesson.intro, text]
	step_label.text = text
	btn_next.visible = false
	result_panel.visible = false
	match _lesson.kind:
		"duel":
			_duel_step(step)
		"battle":
			_battle_step(step)
		"ai":
			btn_next.visible = false

func _on_next() -> void:
	if _step + 1 < _steps().size():
		_step += 1
		_show_step()
	elif _lesson_index + 1 < lessons.size():
		start_lesson(_lesson_index + 1)

func _finish_step() -> void:
	btn_next.visible = true
	var last := _step + 1 >= _steps().size()
	btn_next.text = "Siguiente paso ▸" if not last else ("Siguiente lección ▸" if _lesson_index + 1 < lessons.size() else "Fin del tutorial")
	btn_next.disabled = last and _lesson_index + 1 >= lessons.size()
	btn_next.grab_focus()

func _show_result(text: String) -> void:
	result_label.text = text
	result_panel.visible = true
	UiAnim.fade_in(result_panel, 0.2)

# =====================================================================
# Duelo
# =====================================================================

func _make_fighter(name: String, stats: Array) -> Character:
	var c: Character = CharacterLoader.make_test_character(name, Character.Role.CABALLERO)
	c.combat = stats[0]
	c.defense = stats[1]
	if stats.size() > 2:
		c.personality = stats[2]
	return c

func _setup_duel() -> void:
	player = _make_fighter("Aprendiz", _lesson.player)
	enemy = _make_fighter("Maestro de armas", _lesson.enemy)
	enemy.gender = CharacterEnums.Gender.MASCULINO
	if _lesson.has("player_stamina"):
		player.current_stamina = _lesson.player_stamina
	if _lesson.has("player_health"):
		player.current_health = _lesson.player_health
	player.gold = 100
	duel = DuelManager.new()
	duel.log_message.connect(func(t): _log.append(t))
	duel.combat_event.connect(_on_combat_event)
	duel.start_duel(player, enemy)
	_build_duel_arena()

func _build_duel_arena() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena.add_child(row)
	var left := _fighter_column(player, true)
	row.add_child(left)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 6)
	row.add_child(center)
	var lbl := Label.new()
	lbl.theme_type_variation = &"SubheaderLabel"
	lbl.text = "Postura"
	center.add_child(lbl)
	var postures := HFlowContainer.new()
	postures.add_theme_constant_override("h_separation", 4)
	postures.add_theme_constant_override("v_separation", 4)
	center.add_child(postures)
	var group := ButtonGroup.new()
	_posture_buttons.clear()
	for p in CombatEnums.POSTURES_SHOWN:
		var b := _small_button(CombatEnums.posture_name(p))
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(func():
			_chosen_posture = p
			_update_blocks())
		postures.add_child(b)
		_posture_buttons[p] = b
	var lbl2 := Label.new()
	lbl2.theme_type_variation = &"SubheaderLabel"
	lbl2.text = "Acción"
	center.add_child(lbl2)
	var actions := GridContainer.new()
	actions.columns = 4
	actions.add_theme_constant_override("h_separation", 4)
	actions.add_theme_constant_override("v_separation", 4)
	center.add_child(actions)
	_action_buttons.clear()
	for a in CombatEnums.ACTIONS_SHOWN:
		var b := _small_button(CombatEnums.action_name(a))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_player_action.bind(a))
		actions.add_child(b)
		_action_buttons[a] = b
	var preview := Label.new()
	preview.name = "Preview"
	preview.theme_type_variation = &"MutedLabel"
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_theme_font_size_override("font_size", 15)
	center.add_child(preview)
	row.add_child(_fighter_column(enemy, false))

func _fighter_column(c: Character, is_player: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(170, 0)
	var portrait := TextureRect.new()
	portrait.texture = c.get_portrait()
	portrait.custom_minimum_size = Vector2(0, 150)
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.flip_h = not is_player
	col.add_child(portrait)
	var card := Label.new()
	card.add_theme_font_size_override("font_size", 15)
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(card)
	if is_player:
		_player_card = card
		_player_portrait = portrait
	else:
		_enemy_card = card
		_enemy_portrait = portrait
	return col

func _small_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	return b

func _refresh_cards() -> void:
	for pair in [[player, _player_card, "Tú"], [enemy, _enemy_card, "Rival"]]:
		var c: Character = pair[0]
		var guard := duel.guard_text(c)
		pair[1].text = "%s (%s)\nVida %d/%d\nAliento %d/%d\nPostura: %s%s%s" % [
			pair[2], DialogueCatalog.personality_name(c.personality) if c == enemy else "Combate %d · Defensa %d" % [c.combat, c.defense],
			c.current_health, c.max_health, c.current_stamina, c.max_stamina,
			CombatEnums.posture_name(duel.posture.get(c, P.DEFENSIVA)),
			"\n⚑ " + guard if not guard.is_empty() else "",
			"\nFatigado" if duel.is_fatigued(c) else ""]

func _duel_step(step: Dictionary) -> void:
	_log.clear()
	var before_text := ""
	if step.has("enemy_first") and not duel.is_over:
		duel.set_posture(enemy, step.enemy_first[0])
		duel.take_turn(enemy, step.enemy_first[1])
		before_text = "Antes de tu turno: " + " ".join(_log)
		_log.clear()
	# Recomendación: la postura y la acción del paso se resaltan.
	_chosen_posture = step.posture
	for p in _posture_buttons:
		_posture_buttons[p].set_pressed_no_signal(p == step.posture)
		_posture_buttons[p].disabled = duel.is_over
	for a in _action_buttons:
		var b: Button = _action_buttons[a]
		b.theme_type_variation = &"PrimaryButton" if a == step.action else &""
		b.disabled = duel.is_over
	_awaiting_input = not duel.is_over
	_update_blocks()
	_refresh_cards()
	arena.find_child("Preview", true, false).text = _forecast(step.action) + ("\n" + before_text if not before_text.is_empty() else "")
	if duel.is_over:
		_show_result("El duelo ya terminó en el paso anterior, así que este paso no hace falta.")
		_finish_step()

# Lo que cabe esperar de la acción recomendada, calculado con las fórmulas reales.
func _forecast(action: int) -> String:
	duel.posture[player] = _chosen_posture
	var dmg := duel.preview_damage(player, enemy)
	var lines: Array[String] = ["¿Qué pasará? Tu golpe haría %d–%d de daño con esta postura." % [dmg.x, dmg.y]]
	match action:
		A.CONTRAATACAR:
			lines.append("Probabilidad de parar su golpe: %d%%." % roundi(duel.parry_chance(enemy, player) * 100))
		A.DEFENDER:
			lines.append("Tu Guardia evita su golpe entero un %d%%; si no, lo reduce a la mitad." % roundi(duel.guard_dodge_chance(enemy, player) * 100))
		A.DESARMAR:
			lines.append("Probabilidad de desarmar: %d%%." % roundi(duel.disarm_chance(player, enemy) * 100))
		A.EMPUJAR:
			lines.append("Probabilidad de empujar: %d%%." % roundi(duel.push_chance(player, enemy) * 100))
		A.RETIRARSE:
			lines.append("Probabilidad de huir: %d%%." % roundi(duel.retreat_chance(player, enemy) * 100))
	if duel.countering.get(enemy, false):
		lines.append("El rival prepara una parada (%d%%)." % roundi(duel.parry_chance(player, enemy) * 100))
	return " ".join(lines)

# Cada postura cierra alguna acción: esas se ven apagadas, con el motivo al pasar el ratón.
func _update_blocks() -> void:
	for a in _action_buttons:
		var b: Button = _action_buttons[a]
		var reason := CombatEnums.block_reason(_chosen_posture, a)
		b.disabled = duel == null or duel.is_over or not _awaiting_input or not reason.is_empty()
		b.tooltip_text = reason

func _on_player_action(action: int) -> void:
	if not _awaiting_input or duel.is_over:
		return
	if CombatEnums.is_blocked(_chosen_posture, action):
		return
	_awaiting_input = false
	var step: Dictionary = _steps()[_step]
	var before := _snapshot()
	_log.clear()
	duel.set_posture(player, _chosen_posture)
	duel.take_turn(player, action)
	var mine := _log.duplicate()
	_log.clear()
	var middle := _snapshot()
	var theirs: Array[String] = []
	if not duel.is_over:
		await get_tree().create_timer(0.7).timeout
		duel.set_posture(enemy, step.enemy[0])
		duel.take_turn(enemy, step.enemy[1])
		theirs = _log.duplicate()
	var after := _snapshot()
	for b in _action_buttons.values():
		b.disabled = true
	_refresh_cards()
	_show_result(_explain(action, before, middle, after, mine, theirs))
	_finish_step()

func _snapshot() -> Dictionary:
	return {"php": player.current_health, "pst": player.current_stamina, "ehp": enemy.current_health,
		"est": enemy.current_stamina, "honor": player.honor, "gold": player.gold}

func _explain(action: int, before: Dictionary, middle: Dictionary, after: Dictionary, mine: Array, theirs: Array) -> String:
	var lines: Array[String] = ["¿Qué pasó?"]
	lines.append("Tú: " + " ".join(mine))
	if not theirs.is_empty():
		lines.append("Rival: " + " ".join(theirs))
	var dealt: int = before.ehp - after.ehp
	var taken: int = before.php - after.php
	lines.append("Daño causado: %d · Daño recibido: %d · Tu aliento: %d → %d" % [dealt, taken, before.pst, after.pst])
	match action:
		A.DEFENDER:
			lines.append("La Guardia te devolvió aliento y, si el rival te golpeó, su golpe se dividió entre 2 (o lo evitaste).")
		A.CONTRAATACAR:
			lines.append("La parada solo funciona si el rival ataca. Con un 55% de base, a veces falla: entonces recibes el golpe normal.")
		A.EMPUJAR:
			if middle.est < before.est:
				lines.append("El rival perdió %d de aliento por el empujón." % (before.est - middle.est))
	if after.honor != before.honor or after.gold != before.gold:
		lines.append("Honor %+d · Oro %+d" % [after.honor - before.honor, after.gold - before.gold])
	if duel.is_over:
		lines.append("El duelo ha terminado.")
	return "\n".join(lines)

func _on_combat_event(kind: String, actor: Character, target: Character, amount: int) -> void:
	var portrait := _player_portrait if target == player else _enemy_portrait
	if portrait == null or not is_inside_tree():
		return
	var center := portrait.get_global_rect().get_center()
	match kind:
		"hit", "crit", "parry", "parry_fail":
			Sfx.play("crit" if kind == "crit" else "hit")
			if kind == "parry":
				Sfx.play("clash")
			CombatFx.flash(portrait)
			CombatFx.floating_text(self, center, "-%d" % amount, CombatFx.CRIT_COLOR if kind == "crit" else CombatFx.DAMAGE_COLOR, 30)
		"dodge":
			Sfx.play("whoosh")
			CombatFx.floating_text(self, center, "¡Esquiva!", CombatFx.MISS_COLOR, 28)
		"guard", "dodge_ready", "counter_ready":
			Sfx.play("guard", -6.0)
		"push", "guard_break":
			Sfx.play("push")
			CombatFx.floating_text(self, center, "¡Guardia rota!" if kind == "guard_break" else "¡Empujón!", CombatFx.DAMAGE_COLOR, 26)
		"disarm":
			Sfx.play("disarm")
			CombatFx.floating_text(self, center, "¡Desarmado!", CombatFx.CRIT_COLOR, 28)
		"winded", "unarmed", "miss":
			Sfx.play("whoosh", -6.0)

# =====================================================================
# Personalidades (demostración con la IA real)
# =====================================================================

func _run_ai_demo() -> void:
	for child in arena.get_children():
		child.queue_free()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	arena.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	for key in Character.Personality.keys():
		var personality: int = Character.Personality[key]
		var me := _make_fighter("Tú", [8, 6])
		var foe := _make_fighter("Rival", [8, 6, personality])
		var d := DuelManager.new()
		d.start_duel(me, foe)
		var picks: Array[String] = []
		for turn in 5:
			if d.is_over:
				break
			d.set_posture(me, P.OFENSIVA)
			d.take_turn(me, A.ATACAR)
			if d.is_over:
				break
			var choice := DuelAI.choose(d, foe, me)
			d.set_posture(foe, choice.posture)
			d.take_turn(foe, choice.action)
			picks.append("%s/%s" % [CombatEnums.posture_name(choice.posture), CombatEnums.action_name(choice.action)])
		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanel"
		var lbl := Label.new()
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.text = "%s: %s" % [DialogueCatalog.personality_name(personality), " → ".join(picks)]
		card.add_child(lbl)
		box.add_child(card)
	var again := Button.new()
	again.text = "Simular de nuevo"
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.pressed.connect(_run_ai_demo)
	box.add_child(again)

# =====================================================================
# Batalla
# =====================================================================

func _battle_step(step: Dictionary) -> void:
	for child in arena.get_children():
		child.queue_free()
	battle = BattleManager.new()
	battle.player_side = BattleEnums.Side.ATACANTE
	battle.has_walls = false
	battle.location_name = "el campo de prácticas"
	battle.attacker_cmd = _make_fighter("Tú", [8, 6])
	battle.defender_cmd = _make_fighter("Rival", [8, 6])
	battle.terrain.clear()
	for x in BattleManager.GRID_W:
		var column: Array = []
		for y in BattleManager.GRID_H:
			column.append(T.LLANO)
		battle.terrain.append(column)
	var mine := _unit(BattleEnums.Side.ATACANTE, step.setup[0])
	var theirs := _unit(BattleEnums.Side.DEFENSOR, step.setup[1])
	if step.has("enemy_morale"):
		theirs.morale = step.enemy_morale
	battle.units.append(mine)
	battle.units.append(theirs)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 14)
	arena.add_child(row)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(BattleManager.GRID_W, BattleManager.GRID_H) * BattleBoardScript.CELL_SIZE * BOARD_SCALE
	row.add_child(holder)
	board = BattleBoardScript.new()
	board.scale = Vector2.ONE * BOARD_SCALE
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(board)
	board.setup(battle)
	board.set_selection(mine, [] as Array[Vector2i], [theirs] as Array[BattleUnit])

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	row.add_child(side)
	var dist := battle.distance(mine.cell, theirs.cell)
	var predicted := battle._compute_casualties(mine, theirs, dist, false)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 15)
	info.text = "Tu pelotón: %s\nTerreno: %s\n\nEnemigo: %s\nTerreno: %s\n\nBajas previstas: %d%s" % [
		mine.describe(), BattleEnums.terrain_name(battle.terrain_at(mine.cell)),
		theirs.describe(), BattleEnums.terrain_name(battle.terrain_at(theirs.cell)), predicted,
		"\nRespuesta prevista: ~%d" % int(battle._compute_casualties(theirs, mine, dist, false) * BattleManager.RETALIATION_FACTOR)
			if dist == 1 and theirs.type != U.ARQUEROS else "\nSin respuesta enemiga."]
	side.add_child(info)
	var order := Button.new()
	order.text = "Ordenar el ataque"
	order.theme_type_variation = &"PrimaryButton"
	side.add_child(order)
	order.pressed.connect(func():
		order.disabled = true
		var before := [mine.soldiers, theirs.soldiers]
		var ok := battle.attack(mine, theirs)
		var lines: Array[String] = ["¿Qué pasó?"]
		if not ok:
			lines.append("El ataque no fue posible (fuera de alcance).")
		else:
			lines.append("Bajas enemigas: %d (previstas %d, con ±15%% de azar)." % [before[1] - theirs.soldiers, predicted])
			lines.append("Tus bajas: %d." % (before[0] - mine.soldiers))
			lines.append("Moral enemiga: %d%s" % [theirs.morale, " — ¡rompe filas y huye!" if theirs.routed else ""])
		_show_result("\n".join(lines))
		_finish_step())

func _unit(side: int, spec: Array) -> BattleUnit:
	var u: BattleUnit = BattleUnitScript.new()
	u.side = side
	u.type = spec[0]
	u.soldiers = BattleManager.SOLDIERS_PER_UNIT
	u.max_soldiers = BattleManager.SOLDIERS_PER_UNIT
	u.morale = BattleManager.BASE_MORALE
	u.cell = spec[1]
	battle.terrain[spec[1].x][spec[1].y] = spec[2]
	return u
