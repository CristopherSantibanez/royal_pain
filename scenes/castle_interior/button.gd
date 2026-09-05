extends Button


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func _on_exit_interior_pressed() -> void:
	# Placeholder: la interfaz específica por rol (ciudad, barracas, etc.) se construye más adelante.
	get_tree().change_scene_to_file("res://scenes/map/map.tscn")
