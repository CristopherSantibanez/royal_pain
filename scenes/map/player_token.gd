extends Node2D
# Ficha del jugador en el mapa: su cara con marco dorado junto al castillo donde está (ver TravelData).
# Al viajar se desliza por la ruta hasta el castillo siguiente.

const SIZE := 34
const OFFSET := Vector2(-44, -10)     # a la izquierda del castillo, sin tapar su icono ni los ejércitos
const MOVE_TIME := 0.6
const MapJuice = preload("res://scenes/map/map_juice.gd")
const ARRIVAL_RING_COLOR := Color(0.85, 0.75, 0.55)

var _castle_id := ""

func setup(character: Character, castle_id: String) -> void:
	z_index = 5
	var face := FaceIcon.make(character, SIZE, Color("d4af5a"), false)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.position = Vector2(-SIZE / 2.0, -SIZE / 2.0)
	add_child(face)
	var label := Label.new()
	label.text = "Tú"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("f2e6c8"))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.reset_size()
	label.position = Vector2(-label.size.x / 2.0, SIZE / 2.0 - 2.0)
	place_at(castle_id, true)

static func position_for(castle_id: String) -> Vector2:
	var c := MapData.get_castle_by_id(castle_id)
	return c.position_on_map + OFFSET if c != null else Vector2.ZERO

## Coloca la ficha en un castillo; si no es instantáneo, recorre la ruta desde donde estaba.
func place_at(castle_id: String, instant: bool = false) -> void:
	var target := position_for(castle_id)
	if instant or _castle_id.is_empty() or _castle_id == castle_id:
		position = target
	else:
		var tw := create_tween()
		tw.tween_property(self, "position", target, MOVE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		# Al llegar: rebote y un anillo de polvo.
		tw.tween_callback(func():
			MapJuice.bounce(self)
			MapJuice.ring(get_parent() as Node2D, position, ARRIVAL_RING_COLOR, 26.0))
	_castle_id = castle_id

func _draw() -> void:
	draw_circle(Vector2(0, 2), SIZE * 0.62, Color(0, 0, 0, 0.35))
