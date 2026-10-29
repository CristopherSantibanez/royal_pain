extends SceneTree
# Capturas: panel de Obras del castillo, mapa con lugares y panel de un lugar.
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var EX = root.get_node("ExplorationData")
	var c = load("res://scripts/resources/character_loader.gd").make_test_character("Don Rodrigo", load("res://scripts/resources/character.gd").Role.NOBLEZA_BAJA)
	c.gold = 400
	GM.start_new_game(c, MD.castles[0].castle_id)
	GM.pending_event = {}
	root.get_node("WorldEvents").notifications.clear()
	var home = MD.get_castle_by_id(GM.home_castle_id)
	home.gold = 600
	home.buildings = {"mercado": 2, "murallas": 1}
	home.start_construction("herreria")
	c.gain_xp(260)
	GM.current_castle = home
	change_scene_to_file("res://scenes/castle_interior/castle_interior.tscn")
	await create_timer(0.8).timeout
	root.get_texture().get_image().save_png(out + "/build_castle.png")
	load("res://scripts/ui/works_panel.gd").open(current_scene, home)
	await create_timer(0.5).timeout
	root.get_texture().get_image().save_png(out + "/build_works.png")
	EX.reset()
	EX.spawn_site("torre_negra", home.castle_id)
	EX.spawn_site("ruinas", home.castle_id)
	var near = MD.get_castle_by_id(home.connected_castle_ids[0]) if not home.connected_castle_ids.is_empty() else home
	EX.spawn_site("campamento_bandido", near.castle_id)
	root.get_node("WorldEvents").notifications.clear()
	change_scene_to_file("res://scenes/map/map.tscn")
	await create_timer(1.0).timeout
	root.get_texture().get_image().save_png(out + "/build_map.png")
	current_scene._show_site(EX.sites[0].uid)
	await create_timer(0.5).timeout
	root.get_texture().get_image().save_png(out + "/build_site.png")
	quit()
