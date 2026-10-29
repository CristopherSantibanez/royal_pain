extends Node2D
# Ficha de un viajero (TravelerData) junto al castillo donde está: su cara con marco plateado
# y una nota al pasar el ratón (nombre, rango y destino). Igual que la ficha del jugador (player_token.gd).

const SIZE := 26
const OFFSET := Vector2(40, -8)       # a la derecha del castillo (la del jugador va a la izquierda)
const STACK_STEP := Vector2(0, 28)    # varios viajeros en el mismo castillo, en columna
const FRAME_COLOR := Color("b8c0cc")

func setup(r: Relationship, castle: Castle, index: int, tip: String) -> void:
	z_index = 5
	position = castle.position_on_map + OFFSET + STACK_STEP * index
	var face := FaceIcon.make(r.character, SIZE, FRAME_COLOR, false)
	face.position = Vector2(-SIZE / 2.0, -SIZE / 2.0)
	face.mouse_filter = Control.MOUSE_FILTER_PASS
	face.tooltip_text = tip
	add_child(face)

func _draw() -> void:
	draw_circle(Vector2(0, 2), SIZE * 0.62, Color(0, 0, 0, 0.35))
