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
}
const PLAYER_COLOR := Color(0.20, 0.45, 0.90)
const ENEMY_COLOR := Color(0.85, 0.20, 0.20)
const SPENT_DARKEN := 0.45
const SELECT_COLOR := Color(1.0, 0.9, 0.2)
const MOVE_HIGHLIGHT := Color(1, 1, 1, 0.30)
const TARGET_HIGHLIGHT := Color(1, 0.15, 0.15, 0.45)
const MORALE_BAR_COLOR := Color(1.0, 0.85, 0.25)
const COMPANION_BADGE_COLOR := Color("f0d48a")

# --- Animaciones de combate ---
const FX_SPACING := 0.45      # segundos entre ataques encadenados (el turno de la IA ocurre de golpe)
const ARROW_TIME := 0.32
const LUNGE_TIME := 0.25
const LUNGE_DISTANCE := 16.0
const IMPACT_TIME := 0.7
const ROUT_FADE := 0.7
const CASUALTY_COLOR := Color(1.0, 0.4, 0.35)

var battle: BattleManager
var selected: BattleUnit
var move_cells: Array[Vector2i] = []
var target_units: Array[BattleUnit] = []
var _hover_cell := Vector2i(-1, -1)

var _clock := 0.0
var _next_slot := 0.0
var _last_attack_start := 0.0
var _fx := []   # {type, start, dur, ...}; el sonido suena al empezar

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
		_add_fx({"type": "lunge", "start": start, "dur": LUNGE_TIME, "unit": attacker, "from": from, "to": to, "sound": "melee"})
		_add_impact(to, casualties, start + LUNGE_TIME * 0.5, "")
		if counter > 0:
			_add_impact(from, counter, start + LUNGE_TIME, "")

## El pelotón deshecho se sigue viendo hasta que le llega su golpe y luego se desvanece.
func play_rout(unit: BattleUnit, annihilated: bool) -> void:
	var fade_at := maxf(_clock, _last_attack_start + LUNGE_TIME + 0.1)
	var color := PLAYER_COLOR if battle.is_player_unit(unit) else ENEMY_COLOR
	_add_fx({"type": "ghost", "start": _clock, "dur": fade_at - _clock + ROUT_FADE, "fade_at": fade_at,
		"cell": unit.cell, "color": color, "letter": BattleEnums.unit_type_letter(unit.type)})
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
		"text": "-%d" % amount, "color": CASUALTY_COLOR})

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
	_fx = _fx.filter(func(fx): return _clock < fx.start + fx.dur)
	if _fx.is_empty():
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

func _draw() -> void:
	if battle == null or battle.terrain.is_empty():
		return

	for x in range(BattleManager.GRID_W):
		for y in range(BattleManager.GRID_H):
			var rect := _cell_rect(Vector2i(x, y))
			draw_rect(rect, TERRAIN_COLORS.get(battle.terrain[x][y], Color.GRAY))
			draw_rect(rect, Color(0, 0, 0, 0.25), false, 1.0)

	for cell in move_cells:
		draw_rect(_cell_rect(cell), MOVE_HIGHLIGHT)
	for t: BattleUnit in target_units:
		draw_rect(_cell_rect(t.cell), TARGET_HIGHLIGHT)
		if t.cell == _hover_cell:
			draw_rect(_cell_rect(t.cell).grow(-1), Color(1, 0.85, 0.4), false, 3.0)

	var font := get_theme_default_font()
	for u: BattleUnit in battle.units:
		if not u.is_active():
			continue
		var rect := _cell_rect(u.cell)
		rect.position += _unit_offset(u)
		var inner := rect.grow(-6)
		var color := PLAYER_COLOR if battle.is_player_unit(u) else ENEMY_COLOR
		if battle.is_player_unit(u) and u.has_acted:
			color = color.darkened(SPENT_DARKEN)
		draw_rect(inner, color)
		draw_rect(inner, Color.BLACK, false, 2.0)

		# Barra de moral en el borde inferior del pelotón
		var bar := Rect2(inner.position.x, inner.end.y - 5, inner.size.x * (u.morale / 100.0), 4)
		draw_rect(bar, MORALE_BAR_COLOR)

		draw_string(font, inner.position + Vector2(4, 17), BattleEnums.unit_type_letter(u.type),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		draw_string(font, inner.position + Vector2(4, inner.size.y - 9), str(u.soldiers),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

		# Pelotón al mando de un compañero: insignia dorada con su inicial.
		if u.companion != null:
			var badge := inner.position + Vector2(inner.size.x - 9, 9)
			draw_circle(badge, 8, COMPANION_BADGE_COLOR)
			draw_arc(badge, 8, 0, TAU, 16, Color.BLACK, 1.5)
			draw_string(font, badge + Vector2(-8, 5), u.companion.first_name.left(1), HORIZONTAL_ALIGNMENT_CENTER, 16, 12, Color.BLACK)

		if u == selected:
			draw_rect(rect.grow(-2), SELECT_COLOR, false, 3.0)

	_draw_fx(font)

func _gui_input(event: InputEvent) -> void:
	if battle == null:
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
