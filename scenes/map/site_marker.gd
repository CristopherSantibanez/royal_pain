extends Area2D
# Marcador de un lugar para explorar (ver ExplorationData): un rombo del color del lugar con su nombre.

signal site_clicked(uid: String)

const RADIUS := 13.0

var uid := ""
var color := Color.WHITE
var _label: Label
var _hover := false

func setup(site: Dictionary, site_name: String, site_color: Color) -> void:
	uid = site.uid
	color = site_color
	position = ExplorationData.site_position(site)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS + 6.0
	shape.shape = circle
	add_child(shape)
	_label = Label.new()
	_label.text = "%s (%d m.)" % [site_name, int(site.months_left)]
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color("f2e6c8"))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_label.reset_size()
	_label.position = Vector2(-_label.size.x / 2.0, RADIUS + 3.0)
	input_pickable = true
	input_event.connect(func(_viewport: Node, event: InputEvent, _shape_idx: int):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			site_clicked.emit(uid))
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())
	var tw := create_tween().set_loops()
	tw.tween_property(self, "scale", Vector2(1.12, 1.12), 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_SINE)

func _draw() -> void:
	var r := RADIUS * (1.2 if _hover else 1.0)
	var pts := PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])
	draw_colored_polygon(pts, color)
	pts.append(pts[0])
	draw_polyline(pts, Color("d4af5a"), 2.5, true)
	draw_circle(Vector2.ZERO, 3.0, Color("f2e6c8"))
