extends RefCounted
# Efectos del mapa: anillos al seleccionar, estallido al conquistar, rebote de la ficha y cambio de mes.
# Uso: const MapJuice = preload("res://scenes/map/map_juice.gd")

const RING_TIME := 0.5
const BURST_TIME := 0.9
const BURST_SPARKS := 36
const BOUNCE_SQUASH := 0.18
const MONTH_DIP_ALPHA := 0.28      # oscurece un instante el mapa al pasar el mes (pasar de página)
const MONTH_DIP_TIME := 0.18
const MONTH_BANNER_TIME := 0.6
const MONTH_BANNER_FONT := 34
const MONTH_BANNER_Z := 2

## Anillo que se expande y se desvanece en `pos` (coordenadas de `parent`).
static func ring(parent: Node2D, pos: Vector2, color: Color, radius: float = 34.0, time: float = RING_TIME) -> void:
	if not is_instance_valid(parent):
		return
	var r := _Ring.new()
	r.position = pos
	r.color = color
	r.max_radius = radius
	r.z_index = 20
	parent.add_child(r)
	var tw := r.create_tween()
	tw.tween_property(r, "t", 1.0, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(r.queue_free)

## Estallido de conquista: dos anillos y chispas del color del nuevo dueño.
static func burst(parent: Node2D, pos: Vector2, color: Color) -> void:
	ring(parent, pos, color, 60.0, BURST_TIME)
	ring(parent, pos, Color(1, 0.9, 0.6), 36.0, BURST_TIME * 0.6)
	if CombatFx._reduced() or not is_instance_valid(parent):
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 21
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = BURST_SPARKS
	p.lifetime = 0.8
	p.spread = 180.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 160.0
	p.gravity = Vector2(0, 120)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.5
	p.color = color.lightened(0.3)
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

## Rebote al llegar (aplasta y estira) para objetos del mundo del mapa.
static func bounce(node: Node2D) -> void:
	if not is_instance_valid(node):
		return
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2(1.0 + BOUNCE_SQUASH, 1.0 - BOUNCE_SQUASH), 0.07)
	tw.tween_property(node, "scale", Vector2(1.0 - BOUNCE_SQUASH * 0.5, 1.0 + BOUNCE_SQUASH * 0.5), 0.08)
	tw.tween_property(node, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Cambio de mes: el mapa se oscurece un instante (pasar página) y aparece la fecha.
static func month_turn(ui_layer: Node, date_text: String) -> void:
	if not is_instance_valid(ui_layer):
		return
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(host)
	if not CombatFx._reduced():
		var dip := ColorRect.new()
		dip.color = Color(0, 0, 0, 0)
		dip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(dip)
		var tw := dip.create_tween()
		tw.tween_property(dip, "color:a", MONTH_DIP_ALPHA, MONTH_DIP_TIME)
		tw.tween_property(dip, "color:a", 0.0, MONTH_DIP_TIME * 2.0)
	CombatFx.banner(host, date_text, Color("f0d48a"), MONTH_BANNER_FONT, MONTH_BANNER_TIME)
	for child in host.get_children():
		(child as CanvasItem).z_index = MONTH_BANNER_Z   # por debajo de los paneles (opciones, eventos)
	host.get_tree().create_timer(MONTH_BANNER_TIME + 1.2).timeout.connect(host.queue_free)

class _Ring extends Node2D:
	var color := Color.WHITE
	var max_radius := 34.0
	var t := 0.0:
		set(v):
			t = v
			queue_redraw()

	func _draw() -> void:
		draw_arc(Vector2.ZERO, max_radius * (0.25 + 0.75 * t), 0.0, TAU, 32, Color(color, 1.0 - t), 3.0 * (1.0 - t) + 1.0)
