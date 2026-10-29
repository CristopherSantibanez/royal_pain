extends SceneTree
const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"
func _initialize() -> void:
	_run.call_deferred()
func _shot(n: String) -> void:
	await create_timer(0.8).timeout
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, n])
func _run() -> void:
	change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	await _shot("ui_menu")
	change_scene_to_file("res://scenes/new_game/new_game.tscn")
	await _shot("ui_nueva")
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var p = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	GM.start_new_game(p, MD.castles[0].castle_id)
	await process_frame
	GM.current_castle = MD.get_castle_by_id(GM.home_castle_id)
	change_scene_to_file("res://scenes/castle_interior/castle_interior.tscn")
	await create_timer(0.6).timeout
	var bs = current_scene.action_buttons()
	if bs.size() > 2:
		bs[2].grab_focus()
	await _shot("ui_castillo")
	quit()
