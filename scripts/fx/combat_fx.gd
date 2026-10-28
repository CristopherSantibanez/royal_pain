class_name CombatFx
extends RefCounted
# Efectos visuales de combate reutilizables (sin texturas: todo por código).

const DAMAGE_COLOR := Color(1.0, 0.35, 0.3)
const CRIT_COLOR := Color(1.0, 0.82, 0.2)
const MISS_COLOR := Color(0.85, 0.9, 1.0)
const INFO_COLOR := Color(0.75, 0.95, 0.75)

# Niveles de respuesta: lo pequeño apenas se nota, lo grande para el juego un instante.
enum Tier { SMALL, MEDIUM, BIG }
const TIER_SHAKE := [4.0, 9.0, 16.0]          # píxeles de sacudida
const TIER_HIT_STOP := [0.0, 0.045, 0.1]      # segundos de pausa de impacto (nunca más de MAX_HIT_STOP)
const MAX_HIT_STOP := 0.12
const HIT_STOP_SCALE := 0.05
const LUNGE_TIME := 0.16
const BANNER_TIME := 1.4
const SLOW_MO_SCALE := 0.35

## Nivel según el daño: hasta 6 pequeño, hasta 14 medio, más grande.
static func tier_for(amount: int) -> int:
	return Tier.SMALL if amount <= 6 else (Tier.MEDIUM if amount <= 14 else Tier.BIG)

# Las opciones se buscan al usarse (no al compilar): este script también se carga en pruebas sin autoloads.
static func _settings() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("Settings") if loop != null else null

static func _reduced() -> bool:
	var s := _settings()
	return s != null and s.reduced_effects

## Factor de sacudida según las opciones (1 si no hay opciones cargadas).
static func shake_scale() -> float:
	var s := _settings()
	return s.shake_scale() if s != null else 1.0

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
	if _reduced():
		color = Color.WHITE.lerp(color, 0.35)
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
	strength *= shake_scale()
	if strength <= 0.0 or not is_instance_valid(node):
		return
	# El origen se guarda la primera vez: un segundo temblor a medias no debe moverlo de sitio.
	if not node.has_meta("_shake_origin"):
		node.set_meta("_shake_origin", node.position)
	var origin: Vector2 = node.get_meta("_shake_origin")
	var old: Tween = node.get_meta("_shake_tween") if node.has_meta("_shake_tween") else null
	if old != null and old.is_valid():
		old.kill()
	var tw := node.create_tween()
	node.set_meta("_shake_tween", tw)
	var steps := int(duration / 0.03)
	for i in range(steps):
		var s := strength * (1.0 - float(i) / steps)
		tw.tween_property(node, "position", origin + Vector2(randf_range(-s, s), randf_range(-s, s)), 0.03)
	tw.tween_property(node, "position", origin, 0.03)
	tw.tween_callback(func(): node.remove_meta("_shake_origin"))

## Ráfaga de chispas en `at` (coordenadas locales de `host`).
static func sparks(host: CanvasItem, at: Vector2, color: Color = Color(1.0, 0.85, 0.4), amount: int = 24) -> void:
	if _reduced():
		return
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
static var _stop_until := 0
static var _time_token := 0   # la última pausa (o cámara lenta) es la que devuelve la velocidad normal

static func hit_stop(tree: SceneTree, duration: float = 0.09) -> void:
	if _reduced() or duration <= 0.0:
		return
	duration = minf(duration, MAX_HIT_STOP)
	var until := Time.get_ticks_msec() + int(duration * 1000.0)
	if Engine.time_scale < 1.0 and until <= _stop_until:
		return   # ya hay una pausa más larga en curso
	_stop_until = until
	_time_token += 1
	var token := _time_token
	Engine.time_scale = HIT_STOP_SCALE
	await tree.create_timer(duration, true, false, true).timeout
	if token == _time_token:
		Engine.time_scale = 1.0

## Cámara lenta breve (el golpe final de un duelo). No bloquea la entrada.
static func slow_mo(tree: SceneTree, duration: float = 0.6) -> void:
	if _reduced():
		return
	_time_token += 1
	var token := _time_token
	Engine.time_scale = SLOW_MO_SCALE
	await tree.create_timer(duration, true, false, true).timeout
	if token == _time_token:
		Engine.time_scale = 1.0

## Embestida: el nodo avanza hacia `direction` y vuelve (el que ataca).
static func lunge(node: Control, direction: Vector2, distance: float = 22.0) -> void:
	if not is_instance_valid(node) or _reduced():
		return
	if not node.has_meta("_lunge_origin"):
		node.set_meta("_lunge_origin", node.position)
	var origin: Vector2 = node.get_meta("_lunge_origin")
	var tw := node.create_tween()
	tw.tween_property(node, "position", origin + direction.normalized() * distance, LUNGE_TIME * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position", origin, LUNGE_TIME * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): node.remove_meta("_lunge_origin"))

## Aplastamiento al encajar un golpe (squash & stretch), sin mover el diseño.
static func squash(node: Control, strength: float = 0.12) -> void:
	if not is_instance_valid(node):
		return
	node.pivot_offset = Vector2(node.size.x / 2, node.size.y)
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2(1.0 + strength, 1.0 - strength), 0.06)
	tw.tween_property(node, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Cartel grande en el centro de `host` que aparece con un golpe y se desvanece.
## `area` (global) es la zona sobre la que se centra; por defecto, todo `host`. `host` no debe ser un contenedor.
static func banner(host: Control, text: String, color: Color = CRIT_COLOR, font_size: int = 40, duration: float = BANNER_TIME, area: Rect2 = Rect2()) -> void:
	if not is_instance_valid(host):
		return
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 10)
	label.z_index = 110
	host.add_child(label)
	label.reset_size()
	if area.size == Vector2.ZERO:
		area = host.get_global_rect()
	label.global_position = area.get_center() - label.size / 2 - Vector2(0, area.size.y * 0.12)
	label.pivot_offset = label.size / 2
	label.scale = Vector2.ONE * (1.0 if _reduced() else 1.8)
	label.modulate.a = 0.0
	var tw := label.create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(duration)
	tw.tween_property(label, "modulate:a", 0.0, 0.4)
	tw.tween_callback(label.queue_free)
