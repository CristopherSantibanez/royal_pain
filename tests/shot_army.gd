extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var c = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	var MD = root.get_node("MapData")
	var AD = root.get_node("ArmyData")
	var home = MD.castles[3]
	root.get_node("GameManager").start_new_game(c, home.castle_id)
	AD.create_army(c.full_name(), home.kingdom, 60, home.castle_id)
	for k in MD.castles:
		if k.kingdom != home.kingdom and home.connected_castle_ids.has(k.castle_id):
			AD.create_army(k.owner_name, k.kingdom, 80, home.castle_id)
			break
	change_scene_to_file("res://scenes/map/map.tscn")
	await create_timer(1.0).timeout
	var cam = current_scene.get_node("Camera2D")
	cam.position = home.position_on_map
	cam.zoom = Vector2(1.6, 1.6)
	await create_timer(0.4).timeout
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
