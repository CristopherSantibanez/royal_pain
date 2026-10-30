extends SceneTree
# Capturas del frente de contenido: pestañas de creación de personaje.

func _initialize() -> void:
	_run.call_deferred()

func _save(name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png("C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots/%s.png" % name)

func _run() -> void:
	change_scene_to_file("res://scenes/character_creation/character_creation.tscn")
	await create_timer(1.0).timeout
	var scene = current_scene
	scene._randomize_all()
	for tab in [1, 2, 3, 4]:
		scene.get_node("%PagesTab").current_tab = tab
		await create_timer(0.4).timeout
		await _save("c_creation_tab%d" % tab)
	quit()
