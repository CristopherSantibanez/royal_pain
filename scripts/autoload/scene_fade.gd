extends CanvasLayer
# Autoload — registrar como "SceneFade"
# Cada pantalla nueva aparece con un fundido corto desde negro, en vez de un corte seco.

const FADE_TIME := 0.3

var _rect: ColorRect
var _tween: Tween

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color("0d0906")
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.modulate.a = 0.0
	add_child(_rect)
	get_tree().scene_changed.connect(_on_scene_changed)

func _on_scene_changed() -> void:
	if _tween:
		_tween.kill()
	_rect.modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", 0.0, FADE_TIME).set_trans(Tween.TRANS_SINE)
