class_name LogView
extends RefCounted
## Registros de texto de altura fija: la etiqueta vive dentro de un ScrollContainer
## de alto constante, se recortan las líneas viejas y se baja solo al final.
## Así un registro largo nunca empuja ni agranda el resto de la pantalla.

const MAX_LINES := 60
const SCROLL_META := &"log_scroll"

## Mete `label` en un ScrollContainer de alto fijo, en el mismo sitio del árbol.
static func wrap(label: Label, height: float) -> ScrollContainer:
	if label.has_meta(SCROLL_META):
		return label.get_meta(SCROLL_META)
	var parent := label.get_parent()
	var index := label.get_index()
	var label_owner := label.owner
	var scroll := ScrollContainer.new()
	scroll.name = label.name + "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(label.custom_minimum_size.x, height)
	scroll.size_flags_horizontal = label.size_flags_horizontal
	scroll.size_flags_vertical = label.size_flags_vertical
	parent.remove_child(label)
	parent.add_child(scroll)
	parent.move_child(scroll, index)
	scroll.add_child(label)
	label.owner = label_owner
	label.custom_minimum_size.y = 0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.clip_text = false
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.set_meta(SCROLL_META, scroll)
	# Siempre pegado a la última línea cuando crece el contenido.
	var bar := scroll.get_v_scroll_bar()
	bar.changed.connect(func() -> void: scroll.scroll_vertical = int(bar.max_value))
	return scroll

## Deja sólo las últimas `max_lines` líneas del texto.
static func cap(text: String, max_lines: int = MAX_LINES) -> String:
	var lines := text.split("\n")
	if lines.size() <= max_lines:
		return text
	return "\n".join(lines.slice(lines.size() - max_lines))

## Pone el texto (recortado) y baja el scroll hasta la última línea.
static func show(label: Label, text: String, max_lines: int = MAX_LINES) -> void:
	label.text = cap(text, max_lines)
