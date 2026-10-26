class_name UiAnim
extends RefCounted
# Pequeñas animaciones de interfaz (entradas de pantalla, avisos).

## Aparición suave de un nodo.
static func fade_in(node: CanvasItem, duration: float = 0.35, delay: float = 0.0) -> void:
	node.modulate.a = 0.0
	node.create_tween().tween_property(node, "modulate:a", 1.0, duration).set_delay(delay)

## Los hijos visibles de un contenedor aparecen uno tras otro.
static func stagger_in(container: Control, step: float = 0.05, start_delay: float = 0.1) -> void:
	var i := 0
	for child in container.get_children():
		if child is CanvasItem and child.visible:
			fade_in(child, 0.3, start_delay + i * step)
			i += 1

## Hace latir un control para llamar la atención (por ejemplo, el botón de avanzar turno).
static func pulse(node: CanvasItem, color: Color = Color(1.25, 1.15, 0.9)) -> Tween:
	var tw := node.create_tween().set_loops()
	tw.tween_property(node, "modulate", color, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)
	return tw
