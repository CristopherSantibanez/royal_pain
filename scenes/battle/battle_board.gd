class_name BattleBoard
extends Control

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)

const CELL_SIZE := 56

const TERRAIN_COLORS := {
	BattleEnums.Terrain.LLANO: Color(0.56, 0.68, 0.36),
	BattleEnums.Terrain.BOSQUE: Color(0.18, 0.40, 0.20),
	BattleEnums.Terrain.COLINA: Color(0.64, 0.53, 0.33),
	BattleEnums.Terrain.MURALLA: Color(0.48, 0.48, 0.50),
	BattleEnums.Terrain.RIO: Color(0.20, 0.40, 0.68),
	BattleEnums.Terrain.VADO: Color(0.42, 0.62, 0.78),
	BattleEnums.Terrain.PUENTE: Color(0.50, 0.36, 0.22),
	BattleEnums.Terrain.ALDEA: Color(0.66, 0.58, 0.40),
}
# Tinte del tablero según la hora y el clima; y lo que no ves en la niebla o de noche.
const TIME_TINT := {
	BattleEnums.TimeOfDay.ATARDECER: Color(0.95, 0.45, 0.15, 0.14),
	BattleEnums.TimeOfDay.NOCHE: Color(0.04, 0.06, 0.22, 0.38),
}
const FOG_TINT := Color(0.88, 0.90, 0.95, 0.22)
const UNSEEN_SHADE := Color(0.02, 0.03, 0.08, 0.35)
const RAIN_COLOR := Color(0.75, 0.85, 1.0, 0.35)
const SNOW_COLOR := Color(1, 1, 1, 0.75)
const ORDER_COLOR := Color(1, 1, 1, 0.95)
const FACING_COLOR := Color(1, 0.92, 0.6, 0.95)   # muesca de orientación del pelotón
const PLAYER_COLOR := Color(0.20, 0.45, 0.90)
const ENEMY_COLOR := Color(0.85, 0.20, 0.20)
const ALLY_COLOR := Color(0.22, 0.62, 0.42)    # de tu bando, pero los mueve la IA aliada
const CHALLENGE_HIGHLIGHT := Color(1.0, 0.8, 0.2, 0.45)   # jefes a los que puedes retar a duelo
const SPENT_DARKEN := 0.45
const SELECT_COLOR := Color(1.0, 0.9, 0.2)
const MOVE_HIGHLIGHT := Color(1, 1, 1, 0.30)
const TARGET_HIGHLIGHT := Color(1, 0.15, 0.15, 0.45)
const MORALE_BAR_COLOR := Color(1.0, 0.85, 0.25)
const COMPANION_BADGE_COLOR := Color("f0d48a")
const GENERAL_COLOR := Color("e8c14a")          # estandarte del general sobre su pelotón
const INTENT_COLOR := Color(1.0, 0.55, 0.2, 0.8) # lo que parece que hará un pelotón enemigo (Estrategia)
const ADVANCED_STAR := "★"
const LEADER_FACE_SIZE := 24.0

# --- Animaciones de combate ---
const FX_SPACING := 0.45      # segundos entre ataques encadenados (el turno de la IA ocurre de golpe)
const ARROW_TIME := 0.32
const LUNGE_TIME := 0.25
const LUNGE_DISTANCE := 16.0
const IMPACT_TIME := 0.7
const ROUT_FADE := 0.7
const CASUALTY_COLOR := Color(1.0, 0.4, 0.35)
# Sacudida del tablero por impacto (se dibuja desplazado: no mueve el diseño de la pantalla).
const IMPACT_TIERS := [8, 20]                 # bajas: hasta 8 pequeño, hasta 20 medio, más grande
const BOARD_SHAKE := [1.5, 4.0, 8.0]          # píxeles por nivel
const BOARD_HIT_STOP := 0.06                  # pausa solo en los golpes grandes
const SHAKE_DECAY := 30.0                     # píxeles por segundo
const TRAIL_COLOR := Color(0.85, 0.75, 0.55, 0.55)   # polvo de la carga de caballería
const PUFF_COLOR := Color(0.8, 0.8, 0.8, 0.5)        # humareda cuando un pelotón rompe filas
const PUFF_TIME := 0.6
const FLICKER_SPEED := 38.0

var battle: BattleManager
var selected: BattleUnit
var move_cells: Array[Vector2i] = []
var target_units: Array[BattleUnit] = []
var _hover_cell := Vector2i(-1, -1)

var _clock := 0.0
var _next_slot := 0.0
var _last_attack_start := 0.0
var _fx := []   # {type, start, dur, ...}; el sonido suena al empezar
var _shake := 0.0
var _shake_offset := Vector2.ZERO

func setup(b: BattleManager) -> void:
	battle = b
	set_process(false)
	battle.unit_attacked.connect(play_attack)
	battle.unit_routed.connect(play_rout)
	custom_minimum_size = Vector2(BattleManager.GRID_W * CELL_SIZE, BattleManager.GRID_H * CELL_SIZE)
	queue_redraw()

func set_selection(unit: BattleUnit, moves: Array[Vector2i], targets: Array[BattleUnit]) -> void:
	selected = unit
	move_cells = moves
	target_units = targets
	queue_redraw()

## Azul: tuyos. Verde: aliados que mueve la IA. Rojo: enemigos.
func unit_color(u: BattleUnit) -> Color:
	if battle.is_player_unit(u):
		return PLAYER_COLOR
	return ALLY_COLOR if battle.is_friendly(u) else ENEMY_COLOR

## Jefes enemigos a los que el pelotón elegido puede retar (se resaltan en dorado).
var challenge_units: Array[BattleUnit] = []

func set_challenge_targets(targets: Array[BattleUnit]) -> void:
	challenge_units = targets
	queue_redraw()

## Intenciones enemigas que adivina tu Estrategia: [[pelotón, {target, text}], ...].
var intents: Array = []

func set_intents(list: Array) -> void:
	intents = list
	queue_redraw()

func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))

func _cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL_SIZE

# --- Animaciones ---

## Encola la animación de un ataque. Los ataques que llegan juntos se reproducen uno tras otro.
func play_attack(attacker: BattleUnit, target: BattleUnit, casualties: int, counter: int, ranged: bool) -> void:
	var start := maxf(_clock, _next_slot)
	_next_slot = start + FX_SPACING
	_last_attack_start = start
	var from := attacker.cell
	var to := target.cell
	if ranged:
		_add_fx({"type": "arrow", "start": start, "dur": ARROW_TIME, "from": from, "to": to, "sound": "arrows"})
		_add_impact(to, casualties, start + ARROW_TIME, "")
	else:
		_add_fx({"type": "lunge", "start": start, "dur": LUNGE_TIME, "unit": attacker, "from": from, "to": to, "sound": "melee",
			"cavalry": BattleEnums.is_cavalry(attacker.type)})
		_add_impact(to, casualties, start + LUNGE_TIME * 0.5, "")
		if counter > 0:
			_add_impact(from, counter, start + LUNGE_TIME, "")

## El pelotón deshecho se sigue viendo hasta que le llega su golpe y luego se desvanece.
func play_rout(unit: BattleUnit, annihilated: bool) -> void:
	var fade_at := maxf(_clock, _last_attack_start + LUNGE_TIME + 0.1)
	var color := unit_color(unit)
	_add_fx({"type": "ghost", "start": _clock, "dur": fade_at - _clock + ROUT_FADE, "fade_at": fade_at,
		"cell": unit.cell, "color": color, "letter": BattleEnums.unit_type_letter(unit.type)})
	_add_fx({"type": "puff", "start": fade_at, "dur": PUFF_TIME, "cell": unit.cell})
	_add_fx({"type": "text", "start": fade_at, "dur": 1.0, "cell": unit.cell, "sound": "rout",
		"text": "Aniquilado" if annihilated else "¡Huyen!", "color": Color.WHITE})

## Tiempo que falta para que terminen las animaciones en cola.
func fx_remaining() -> float:
	var end := _clock
	for fx in _fx:
		end = maxf(end, fx.start + fx.dur)
	return end - _clock

func _add_impact(cell: Vector2i, amount: int, start: float, sound: String) -> void:
	_add_fx({"type": "impact", "start": start, "dur": IMPACT_TIME, "cell": cell, "sound": sound,
		"text": "-%d" % amount, "color": CASUALTY_COLOR, "amount": amount})

## Sacude el tablero (sin mover el diseño): `pixels` antes de aplicar la opción de sacudida.
func shake(pixels: float) -> void:
	_shake = maxf(_shake, pixels * CombatFx.shake_scale())
	if _shake > 0.0:
		set_process(true)

func _impact_tier(amount: int) -> int:
	return 0 if amount <= IMPACT_TIERS[0] else (1 if amount <= IMPACT_TIERS[1] else 2)

# Un impacto que empieza ahora: sacude el tablero según las bajas; los grandes paran un instante.
func _on_impact_started(fx: Dictionary) -> void:
	var tier := _impact_tier(int(fx.get("amount", 0)))
	_shake = maxf(_shake, BOARD_SHAKE[tier] * CombatFx.shake_scale())
	if tier == 2:
		CombatFx.hit_stop(get_tree(), BOARD_HIT_STOP)

func _add_fx(fx: Dictionary) -> void:
	fx["played"] = false
	_fx.append(fx)
	set_process(true)

func _process(delta: float) -> void:
	_clock += delta
	for fx in _fx:
		if not fx.played and _clock >= fx.start:
			fx.played = true
			if not fx.get("sound", "").is_empty():
				Sfx.play(fx.sound)
			if fx.type == "impact":
				_on_impact_started(fx)
	_fx = _fx.filter(func(fx): return _clock < fx.start + fx.dur)
	_shake = move_toward(_shake, 0.0, SHAKE_DECAY * delta)
	_shake_offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake)) if _shake > 0.0 else Vector2.ZERO
	if _fx.is_empty() and _shake <= 0.0:
		set_process(false)
	queue_redraw()

func _progress(fx: Dictionary) -> float:
	return clampf((_clock - fx.start) / fx.dur, 0.0, 1.0)

func _unit_offset(u: BattleUnit) -> Vector2:
	for fx in _fx:
		if fx.type == "lunge" and fx.unit == u and _clock >= fx.start:
			var dir := (Vector2(fx.to) - Vector2(fx.from)).normalized()
			return dir * sin(PI * _progress(fx)) * LUNGE_DISTANCE
	return Vector2.ZERO

func _draw_fx(font: Font) -> void:
	for fx in _fx:
		if _clock < fx.start and fx.type != "ghost":
			continue
		var p := _progress(fx)
		match fx.type:
			"lunge":
				if fx.get("cavalry", false) and not CombatFx._reduced():
					var head := _cell_center(fx.from) + _unit_offset(fx.unit)
					var back := (Vector2(fx.from) - Vector2(fx.to)).normalized()
					var side := Vector2(-back.y, back.x)
					for k in 3:
						var o := side * (k - 1) * 9.0
						draw_line(head + o, head + o + back * (18.0 + 14.0 * sin(PI * p)), Color(TRAIL_COLOR, TRAIL_COLOR.a * (1.0 - p)), 3.0)
			"puff":
				if not CombatFx._reduced():
					var c := _cell_center(fx.cell)
					for k in 4:
						var ang := TAU * k / 4.0 + 0.6
						draw_circle(c + Vector2.from_angle(ang) * (8.0 + 22.0 * p), 6.0 + 8.0 * p, Color(PUFF_COLOR, PUFF_COLOR.a * (1.0 - p)))
			"arrow":
				var a := _cell_center(fx.from)
				var b := _cell_center(fx.to)
				var pos := a.lerp(b, p) + Vector2(0, -sin(PI * p) * 22.0)
				var tangent := (b - a).normalized()
				draw_line(pos - tangent * 12.0, pos, Color(0.95, 0.9, 0.7), 2.0)
				draw_circle(pos, 2.5, Color.WHITE)
			"impact":
				var rect := _cell_rect(fx.cell)
				draw_rect(rect, Color(1, 0.85, 0.7, 0.65 * (1.0 - p)))
				draw_arc(rect.get_center(), CELL_SIZE * (0.2 + 0.5 * p), 0, TAU, 24, Color(1, 1, 1, 1.0 - p), 3.0)
				_draw_rising_text(font, fx, p, 22)
			"ghost":
				var alpha := 1.0
				if _clock < fx.fade_at and not CombatFx._reduced():
					alpha = 0.65 + 0.35 * sin(_clock * FLICKER_SPEED)   # tiembla antes de romper filas
				if _clock >= fx.fade_at:
					alpha = 1.0 - clampf((_clock - fx.fade_at) / ROUT_FADE, 0.0, 1.0)
				var inner := _cell_rect(fx.cell).grow(-6 - (1.0 - alpha) * 10.0)
				draw_rect(inner, Color(fx.color, alpha))
				draw_rect(inner, Color(0, 0, 0, alpha), false, 2.0)
				draw_string(font, inner.position + Vector2(4, 17), fx.letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, alpha))
			"text":
				_draw_rising_text(font, fx, p, 16)

func _draw_rising_text(font: Font, fx: Dictionary, p: float, font_size: int) -> void:
	var pos := _cell_center(fx.cell) + Vector2(-CELL_SIZE * 0.45, -12.0 - p * 30.0)
	var color: Color = fx.color
	color.a = 1.0 - maxf(0.0, p - 0.5) * 2.0
	draw_string_outline(font, pos, fx.text, HORIZONTAL_ALIGNMENT_CENTER, CELL_SIZE * 0.9, font_size, 4, Color(0, 0, 0, color.a))
	draw_string(font, pos, fx.text, HORIZONTAL_ALIGNMENT_CENTER, CELL_SIZE * 0.9, font_size, color)

# Detalles dibujados para distinguir el terreno de un vistazo.
func _draw_terrain_detail(t: int, rect: Rect2) -> void:
	var c := rect.get_center()
	match t:
		BattleEnums.Terrain.ALDEA:
			var base := Rect2(c + Vector2(-11, -2), Vector2(22, 14))
			draw_rect(base, Color(0.85, 0.78, 0.62))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -2), c + Vector2(0, -14), c + Vector2(14, -2)]), Color(0.62, 0.26, 0.18))
			draw_rect(Rect2(c + Vector2(-3, 4), Vector2(6, 8)), Color(0.35, 0.22, 0.12))
		BattleEnums.Terrain.PUENTE:
			for i in range(5):
				var y := rect.position.y + 6 + i * 10
				draw_line(Vector2(rect.position.x + 3, y), Vector2(rect.end.x - 3, y), Color(0.32, 0.22, 0.12), 2.0)
			draw_line(rect.position + Vector2(4, 0), Vector2(rect.position.x + 4, rect.end.y), Color(0.25, 0.16, 0.08), 3.0)
			draw_line(Vector2(rect.end.x - 4, rect.position.y), rect.end - Vector2(4, 0), Color(0.25, 0.16, 0.08), 3.0)
		BattleEnums.Terrain.RIO, BattleEnums.Terrain.VADO:
			for i in range(3):
				var y := rect.position.y + 12 + i * 15
				draw_arc(Vector2(c.x - 8, y), 7, PI * 0.1, PI * 0.9, 6, Color(1, 1, 1, 0.28), 1.5)
				draw_arc(Vector2(c.x + 8, y + 4), 7, PI * 0.1, PI * 0.9, 6, Color(1, 1, 1, 0.28), 1.5)
			if t == BattleEnums.Terrain.VADO:
				for pos in [Vector2(-12, -10), Vector2(6, -4), Vector2(-4, 10), Vector2(12, 14)]:
					draw_circle(c + pos, 3.5, Color(0.55, 0.52, 0.46))
		BattleEnums.Terrain.BOSQUE:
			for pos in [Vector2(-12, -6), Vector2(10, -10), Vector2(0, 10)]:
				draw_colored_polygon(PackedVector2Array([c + pos + Vector2(-7, 6), c + pos + Vector2(0, -8), c + pos + Vector2(7, 6)]), Color(0.10, 0.28, 0.12))
		BattleEnums.Terrain.COLINA:
			draw_arc(c + Vector2(0, 14), 18, PI * 1.15, PI * 1.85, 10, Color(0.45, 0.36, 0.20), 2.5)

# Hora, clima y lo que la niebla o la noche ocultan.
func _draw_conditions() -> void:
	var board_rect := Rect2(Vector2.ZERO, Vector2(BattleManager.GRID_W, BattleManager.GRID_H) * CELL_SIZE)
	if TIME_TINT.has(battle.time_of_day):
		draw_rect(board_rect, TIME_TINT[battle.time_of_day])
	match battle.weather:
		BattleEnums.Weather.NIEBLA:
			draw_rect(board_rect, FOG_TINT)
		BattleEnums.Weather.LLUVIA:
			for i in range(70):
				var p := Vector2(fmod(i * 97.0, board_rect.size.x), fmod(i * 53.0 + i * i * 3.0, board_rect.size.y))
				draw_line(p, p + Vector2(-5, 12), RAIN_COLOR, 1.0)
		BattleEnums.Weather.NIEVE:
			for i in range(90):
				var p := Vector2(fmod(i * 83.0, board_rect.size.x), fmod(i * 41.0 + i * i * 7.0, board_rect.size.y))
				draw_circle(p, 1.6, SNOW_COLOR)
	var vision := battle.vision_range()
	if vision > 0:
		var mine := battle.active_units(battle.player_side)
		for x in range(BattleManager.GRID_W):
			for y in range(BattleManager.GRID_H):
				var cell := Vector2i(x, y)
				if not mine.any(func(u: BattleUnit) -> bool: return battle.distance(u.cell, cell) <= vision):
					draw_rect(_cell_rect(cell), UNSEEN_SHADE)

func _draw() -> void:
	if battle == null or battle.terrain.is_empty():
		return
	draw_set_transform(_shake_offset)

	for x in range(BattleManager.GRID_W):
		for y in range(BattleManager.GRID_H):
			var rect := _cell_rect(Vector2i(x, y))
			draw_rect(rect, TERRAIN_COLORS.get(battle.terrain[x][y], Color.GRAY))
			_draw_terrain_detail(battle.terrain[x][y], rect)
			draw_rect(rect, Color(0, 0, 0, 0.25), false, 1.0)
	_draw_conditions()

	for cell in move_cells:
		draw_rect(_cell_rect(cell), MOVE_HIGHLIGHT)
	for t: BattleUnit in challenge_units:
		draw_rect(_cell_rect(t.cell), CHALLENGE_HIGHLIGHT)
	for t: BattleUnit in target_units:
		draw_rect(_cell_rect(t.cell), TARGET_HIGHLIGHT)
		if t.cell == _hover_cell:
			draw_rect(_cell_rect(t.cell).grow(-1), Color(1, 0.85, 0.4), false, 3.0)

	var font := get_theme_default_font()
	for u: BattleUnit in battle.units:
		if not u.is_active() or not battle.is_visible_to(battle.player_side, u):
			continue
		var rect := _cell_rect(u.cell)
		rect.position += _unit_offset(u)
		var inner := rect.grow(-6)
		var color := unit_color(u)
		if battle.is_player_unit(u) and u.has_acted:
			color = color.darkened(SPENT_DARKEN)
		draw_rect(inner, color)
		draw_rect(inner, Color.BLACK, false, 2.0)

		# Barra de moral en el borde inferior del pelotón
		var bar := Rect2(inner.position.x, inner.end.y - 5, inner.size.x * (u.morale / 100.0), 4)
		draw_rect(bar, MORALE_BAR_COLOR)

		var letter := BattleEnums.unit_type_letter(u.type) + (ADVANCED_STAR if BattleEnums.is_advanced(u.type) else "")
		draw_string(font, inner.position + Vector2(4, 17), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		# Estandarte del general: si cae este pelotón, su bando pierde.
		if u.general:
			var pole := Vector2(inner.position.x + 3, inner.position.y + 20)
			draw_line(pole, pole + Vector2(0, 14), GENERAL_COLOR, 2.0)
			draw_colored_polygon(PackedVector2Array([pole, pole + Vector2(10, 3), pole + Vector2(0, 7)]), GENERAL_COLOR)
		draw_string(font, inner.position + Vector2(4, inner.size.y - 9), str(u.soldiers),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		# Orden en curso: escudo (mantener) o flecha (cargar) junto al número de soldados.
		if u.order == BattleEnums.Order.MANTENER:
			var c := Vector2(inner.end.x - 9, inner.end.y - 15)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -6), c + Vector2(6, -6), c + Vector2(6, 1), c + Vector2(0, 7), c + Vector2(-6, 1)]), ORDER_COLOR)
		elif u.order == BattleEnums.Order.CARGAR:
			var c := Vector2(inner.end.x - 9, inner.end.y - 15)
			var dir := 1.0 if u.side == BattleEnums.Side.ATACANTE else -1.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(-6 * dir, -6), c + Vector2(6 * dir, 0), c + Vector2(-6 * dir, 6)]), ORDER_COLOR)

		# Orientación: muesca en el borde hacia donde mira; formación: triángulo (cuña) o cuadrado (cuadro).
		var fc := inner.get_center()
		var fd := Vector2(u.facing)
		var tip := fc + fd * (inner.size.x * 0.5 + 4.0)
		var sd := Vector2(-fd.y, fd.x) * 5.0
		draw_colored_polygon(PackedVector2Array([tip, tip - fd * 7.0 + sd, tip - fd * 7.0 - sd]), FACING_COLOR)
		if u.formation == BattleEnums.Formation.CUNA:
			var wc := inner.position + Vector2(inner.size.x * 0.5, 11)
			draw_colored_polygon(PackedVector2Array([wc + Vector2(0, -6), wc + Vector2(6, 5), wc + Vector2(-6, 5)]), ORDER_COLOR)
		elif u.formation == BattleEnums.Formation.CUADRO:
			draw_rect(Rect2(inner.position + Vector2(inner.size.x * 0.5 - 5, 6), Vector2(10, 10)), ORDER_COLOR, false, 2.0)

		# La cara de quien lo dirige, siempre a la vista: marco dorado si es un compañero,
		# blanco si es el comandante y del color del bando si es un capitán de tropa.
		var leader := u.leader()
		if leader != null:
			var face_rect := Rect2(inner.end.x - LEADER_FACE_SIZE + 3, inner.position.y - 3, LEADER_FACE_SIZE, LEADER_FACE_SIZE)
			var frame := color.lightened(0.35)
			if u.companion != null:
				frame = COMPANION_BADGE_COLOR
			elif leader == battle.attacker_cmd or leader == battle.defender_cmd:
				frame = Color.WHITE
			if u.general:
				frame = GENERAL_COLOR
			draw_rect(face_rect.grow(2), frame)
			var face := leader.get_face()
			if face != null:
				draw_texture_rect(face, face_rect, false)

		if u == selected:
			draw_rect(rect.grow(-2), SELECT_COLOR, false, 3.0)

	# Flechas de intención: hacia quién va cada pelotón enemigo que sabes leer.
	for pair: Array in intents:
		var e: BattleUnit = pair[0]
		var t: BattleUnit = pair[1].get("target")
		if t == null or not e.is_active():
			continue
		var from := _cell_center(e.cell)
		var to := _cell_center(t.cell)
		var dir := (to - from).normalized()
		from += dir * CELL_SIZE * 0.35
		to -= dir * CELL_SIZE * 0.35
		draw_dashed_line(from, to, INTENT_COLOR, 2.0, 6.0)
		var side := Vector2(-dir.y, dir.x) * 5.0
		draw_colored_polygon(PackedVector2Array([to, to - dir * 9.0 + side, to - dir * 9.0 - side]), INTENT_COLOR)

	if has_focus() and cursor.x >= 0:
		draw_rect(_cell_rect(cursor).grow(-1), CURSOR_COLOR, false, 2.0)

	_draw_fx(font)

# Cursor de teclado y mando: flechas o cruceta para moverlo, Intro o A para actuar en la casilla.
var cursor := Vector2i(-1, -1)
const CURSOR_COLOR := Color(1, 1, 1, 0.9)

func _move_cursor(step: Vector2i) -> void:
	if cursor.x < 0:
		cursor = selected.cell if selected != null else Vector2i(0, BattleManager.GRID_H / 2)
	else:
		cursor = Vector2i(clampi(cursor.x + step.x, 0, BattleManager.GRID_W - 1), clampi(cursor.y + step.y, 0, BattleManager.GRID_H - 1))
	_hover_cell = cursor
	cell_hovered.emit(cursor)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if battle == null:
		return
	for dir in [["ui_left", Vector2i.LEFT], ["ui_right", Vector2i.RIGHT], ["ui_up", Vector2i.UP], ["ui_down", Vector2i.DOWN]]:
		if event.is_action_pressed(dir[0], true):
			_move_cursor(dir[1])
			accept_event()
			return
	if event.is_action_pressed("ui_accept") and cursor.x >= 0:
		cell_clicked.emit(cursor)
		accept_event()
		return
	if event is InputEventMouseMotion:
		var hover := Vector2i(int(event.position.x / CELL_SIZE), int(event.position.y / CELL_SIZE))
		if hover != _hover_cell and battle.in_bounds(hover):
			_hover_cell = hover
			cell_hovered.emit(hover)
			queue_redraw()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := Vector2i(int(event.position.x / CELL_SIZE), int(event.position.y / CELL_SIZE))
		if battle.in_bounds(cell):
			cell_clicked.emit(cell)
			accept_event()
