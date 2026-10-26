class_name CombatFx
extends RefCounted
# Efectos visuales de combate reutilizables (sin texturas: todo por código).

const DAMAGE_COLOR := Color(1.0, 0.35, 0.3)
const CRIT_COLOR := Color(1.0, 0.82, 0.2)
const MISS_COLOR := Color(0.85, 0.9, 1.0)
const INFO_COLOR := Color(0.75, 0.95, 0.75)

## Texto que sube y se desvanece (daño, "¡Esquiva!", etc.), centrado en `at` (coordenadas globales).
static func floating_text(host: Control, at: Vector2, text: String, color: Color, font_size: int = 38) -> void:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.z_index = 100
	host.add_child(label)
	label.reset_size()
	label.pivot_offset = label.size / 2
	var pos := at - label.size / 2 + Vector2(randf_range(-20, 20), 0)
	var screen := host.get_viewport_rect().size
	pos.x = clampf(pos.x, 8.0, maxf(8.0, screen.x - label.size.x - 8.0))   # que no se salga por los lados
	label.global_position = pos
	label.scale = Vector2(0.4, 0.4)

	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector2(1.2, 1.2), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "scale", Vector2.ONE, 0.08)
	tw.parallel().tween_property(label, "position:y", label.position.y - 70, 0.9).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.5)
	tw.tween_callback(label.queue_free)

## Destello de color sobre un nodo (por ejemplo, rojo al recibir daño).
static func flash(node: CanvasItem, color: Color = Color(1.8, 0.5, 0.5), duration: float = 0.3) -> void:
	node.modulate = color
	node.create_tween().tween_property(node, "modulate", Color.WHITE, duration)

## Retroceso: el nodo se encoge y vuelve, como si encajara el golpe.
static func punch(node: Control, strength: float = 0.12) -> void:
	node.pivot_offset = node.size / 2
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2.ONE * (1.0 - strength), 0.05)
	tw.tween_property(node, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Temblor: desplaza el nodo al azar y lo devuelve a su sitio.
static func shake(node: Control, strength: float = 10.0, duration: float = 0.3) -> void:
	var origin := node.position
	var tw := node.create_tween()
	var steps := int(duration / 0.03)
	for i in range(steps):
		var s := strength * (1.0 - float(i) / steps)
		tw.tween_property(node, "position", origin + Vector2(randf_range(-s, s), randf_range(-s, s)), 0.03)
	tw.tween_property(node, "position", origin, 0.03)

## Ráfaga de chispas en `at` (coordenadas locales de `host`).
static func sparks(host: CanvasItem, at: Vector2, color: Color = Color(1.0, 0.85, 0.4), amount: int = 24) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.z_index = 90
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.45
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 180.0
	p.initial_velocity_max = 420.0
	p.gravity = Vector2(0, 700)
	p.damping_min = 80.0
	p.damping_max = 160.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 0.9))
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	host.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

## Congela el juego un instante para dar peso a un golpe fuerte.
static func hit_stop(tree: SceneTree, duration: float = 0.09) -> void:
	Engine.time_scale = 0.05
	await tree.create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
