extends SceneTree
# Capturas de cada pestaña de la creación de personaje (con ventana).

const OUT := "res://tests/_shots"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://scenes/character_creation/character_creation.tscn")
	await create_timer(1.0).timeout
	var tabs: TabContainer = current_scene.pages_tab
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		await create_timer(0.5).timeout
		var name := tabs.get_tab_title(i)
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/creacion_%d.png" % [OUT, i]))
		print("pestaña %d: %s" % [i, name])
	quit()
