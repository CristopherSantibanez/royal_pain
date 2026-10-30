extends Control
# Tutorial de combate: lecciones del combate RPG (la pantalla real, scenes/rpg_battle) y del BattleManager.
# Las lecciones RPG explican y abren un combate de prueba incrustado; las de batalla muestran casos
# concretos del tablero con los números reales.

const MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"
const BattleBoardScript = preload("res://scenes/battle/battle_board.gd")
const BattleUnitScript = preload("res://scripts/resources/battle_unit.gd")
const BOARD_SCALE := 0.62

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

# --- Combate RPG ---
const RPG_SCENE := "res://scenes/rpg_battle/rpg_battle.tscn"
var _rpg_layer: CanvasLayer

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
		{"title": "Turnos y órdenes", "kind": "rpg",
			"intro": "Arriba, la línea de turnos: el más ágil actúa antes. PV = vida; PT = puntos de técnica (Atacar y Defender los recuperan).",
			"steps": [{"text": "Prueba: tú y un compañero contra dos bandidos. Atacar → elige objetivo (←/→ o ratón).", "demo": "fight", "a": 2, "b": ["bandido", "bandido"]}]},
		{"title": "Debilidades", "kind": "rpg",
			"intro": "Cada arma hace un tipo de daño y cada armadura lo sufre o lo resiste: Débil ×1,4, Resiste ×0,6.",
			"steps": [
				{"text": "La tabla (fila: tu daño; columna: su armadura).", "demo": "table"},
				{"text": "Al elegir objetivo verás «Débil» o «Resiste» sobre cada rival.", "demo": "fight", "a": 1, "b": ["bandido", "infanteria_pesada"]},
			]},
		{"title": "Técnicas, cambiar y abandonar", "kind": "rpg",
			"intro": "Técnicas: gastan PT (salen del árbol de habilidades). Cambiar: entra alguien de la reserva. Abandonar: rendirse (derrota sin heridas) o retirarse (puede fallar).",
			"steps": [{"text": "Prueba con 4 en línea y 1 en reserva.", "demo": "fight", "a": 5, "b": ["soldado", "arquero", "miliciano"]}]},
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
		"battle":
			pass
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
		"rpg":
			_rpg_step(step)
		"battle":
			_battle_step(step)

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
# Combate RPG
# =====================================================================

func _rpg_step(step: Dictionary) -> void:
	for ch in arena.get_children():
		ch.queue_free()
	match step.get("demo", ""):
		"table":
			_affinity_table()
			_finish_step()
		"fight":
			var center := CenterContainer.new()
			center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			arena.add_child(center)
			var btn := Button.new()
			btn.text = "Probar el combate"
			btn.theme_type_variation = &"PrimaryButton"
			btn.pressed.connect(_open_rpg.bind(step))
			center.add_child(btn)
			btn.grab_focus.call_deferred()

func _affinity_table() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena.add_child(center)
	var grid := GridContainer.new()
	grid.columns = RpgStats.ARMOR_NAMES.size() + 1
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	center.add_child(grid)
	grid.add_child(Label.new())
	for an in RpgStats.ARMOR_NAMES:
		var h := Label.new()
		h.text = an
		h.theme_type_variation = &"MutedLabel"
		grid.add_child(h)
	for dt in RpgStats.DAMAGE_NAMES.size():
		var r := Label.new()
		r.text = RpgStats.DAMAGE_NAMES[dt]
		grid.add_child(r)
		for ac in RpgStats.ARMOR_NAMES.size():
			var cell := Label.new()
			match RpgStats.affinity(dt, ac):
				RpgStats.Affinity.DEBIL:
					cell.text = "Débil"
					cell.add_theme_color_override("font_color", Color("ffd25a"))
				RpgStats.Affinity.RESISTE:
					cell.text = "Resiste"
					cell.add_theme_color_override("font_color", Color("9fb4c8"))
				_:
					cell.text = "—"
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			grid.add_child(cell)

func _make_fighter(name: String, stats: Array) -> Character:
	var c: Character = CharacterLoader.make_test_character(name, Character.Role.CABALLERO)
	c.combat = stats[0]
	c.defense = stats[1]
	if stats.size() > 2:
		c.personality = stats[2]
	return c

func _tutorial_char(name: String) -> Character:
	var c: Character = CharacterLoader.make_test_character(name, Character.Role.CABALLERO)
	c.level = 3
	SkillTreeCatalog.auto_learn(c)
	return c

## Abre la pantalla de combate real, incrustada, con bandos de prueba (sin consecuencias).
func _open_rpg(step: Dictionary) -> void:
	if _rpg_layer != null:
		return
	var a: Array = [_tutorial_char("Aprendiz")]
	for i in int(step.get("a", 1)) - 1:
		a.append(_tutorial_char("Compañero %d" % (i + 1)))
	var b: Array = []
	for t in step.get("b", ["bandido"]):
		b.append(EnemyCatalog.make_enemy(t, 2))
	_rpg_layer = CanvasLayer.new()
	_rpg_layer.layer = 30
	add_child(_rpg_layer)
	var sc = load(RPG_SCENE).instantiate()
	sc.player_character = a[0]
	sc.enemy_character = b[0]
	sc.side_a = a
	sc.side_b = b
	sc.embedded = true
	sc.title_text = "Tutorial · " + _lesson.title
	_rpg_layer.add_child(sc)
	var winner: Character = await sc.embedded_finished
	_rpg_layer.queue_free()
	_rpg_layer = null
	_show_result("¡Victoria!" if winner == a[0] else ("Derrota. Prueba otra vez." if winner != null else "Te retiraste."))
	_finish_step()

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
