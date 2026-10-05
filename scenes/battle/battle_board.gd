class_name BattleBoard
extends Control

signal cell_clicked(cell: Vector2i)

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

var battle: BattleManager
var selected: BattleUnit
var move_cells: Array[Vector2i] = []
var target_units: Array[BattleUnit] = []

func setup(b: BattleManager) -> void:
	battle = b
	custom_minimum_size = Vector2(BattleManager.GRID_W * CELL_SIZE, BattleManager.GRID_H * CELL_SIZE)
	queue_redraw()

func set_selection(unit: BattleUnit, moves: Array[Vector2i], targets: Array[BattleUnit]) -> void:
	selected = unit
	move_cells = moves
	target_units = targets
	queue_redraw()

func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))

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

	var font := get_theme_default_font()
	for u: BattleUnit in battle.units:
		if not u.is_active():
			continue
		var rect := _cell_rect(u.cell)
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

		if u == selected:
			draw_rect(rect.grow(-2), SELECT_COLOR, false, 3.0)

func _gui_input(event: InputEvent) -> void:
	if battle == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := Vector2i(int(event.position.x / CELL_SIZE), int(event.position.y / CELL_SIZE))
		if battle.in_bounds(cell):
			cell_clicked.emit(cell)
			accept_event()
