extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var GM = root.get_node("GameManager")
	var c = load("res://scripts/resources/character_loader.gd").make_test_character("Sir Alaric", load("res://scripts/resources/character.gd").Role.CABALLERO)
	c.gold = 400
	GM.start_new_game(c, root.get_node("MapData").castles[0].castle_id)
	for m in 6:
		GM.pending_event = {}
		GM.advance_turn()
	GM.pending_event = {}
	root.get_node("WorldEvents").notifications.clear()
	GM.current_castle = root.get_node("MapData").castles[0]
	change_scene_to_file("res://scenes/castle_interior/castle_interior.tscn")
	await create_timer(0.8).timeout
	load("res://scripts/ui/shop_panel.gd").open(current_scene)
	await create_timer(0.5).timeout
	root.get_texture().get_image().save_png(out + "/shop.png")
	change_scene_to_file("res://scenes/map/map.tscn")
	await create_timer(0.8).timeout
	load("res://scripts/ui/chronicle_panel.gd").open(current_scene.get_node("UILayer"), current_scene.visible_castle_ids)
	await create_timer(0.5).timeout
	root.get_texture().get_image().save_png(out + "/chronicle.png")
	quit()
