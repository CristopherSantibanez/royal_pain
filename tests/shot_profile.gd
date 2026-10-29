extends SceneTree
# Captura la ficha de un personaje abierta sobre la pantalla de relaciones (sin guardar nada en disco).

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var c = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	root.get_node("GameManager").start_new_game(c, root.get_node("MapData").castles[0].castle_id)
	change_scene_to_file("res://scenes/relations/relations.tscn")
	await create_timer(0.8).timeout
	var rel = root.get_node("RelationsData").people_in_area()[0]
	rel.affection = 45
	load("res://scripts/ui/character_profile.gd").open(current_scene, rel)
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png(out)
	quit()
