extends SceneTree
# Capturas de los roles nuevos: Nueva Partida (rol mercenario), castillo ajeno con «Ofrecer tus servicios»,
# panel de contratos, y castillo del Duque.

const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"

func _initialize() -> void:
	_run.call_deferred()

func _save(name: String) -> void:
	await create_timer(0.7).timeout
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	change_scene_to_file("res://scenes/new_game/new_game.tscn")
	await create_timer(0.6).timeout
	var ng = current_scene
	ng.role_option.select(ng.role_option.get_item_index(load("res://scripts/resources/character.gd").Role.CONDOTIERO))
	ng._refresh_info()
	await _save("roles_01_nueva_partida")

	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var p = CL.make_test_character("Sir Alaric", CH.Role.CAPITAN)
	GM.start_new_game(p, MD.castles[0].castle_id)
	await process_frame
	await process_frame
	GM.actions_remaining = 3
	var foreign = MD.castles[2]
	var travel = root.get_node_or_null("TravelData")
	if travel != null:
		travel.location_id = foreign.castle_id
	GM.current_castle = foreign
	change_scene_to_file("res://scenes/castle_interior/castle_interior.tscn")
	await _save("roles_02_castillo_ajeno_capitan")
	var lord = RD.get_relation(foreign.owner_name)
	load("res://scripts/ui/contracts_panel.gd").open(current_scene, lord)
	await _save("roles_03_contratos")

	p.role = CH.Role.DUQUE
	GM.refresh_actions_for_role_change()
	if travel != null:
		travel.location_id = GM.home_castle_id
	GM.current_castle = MD.get_castle_by_id(GM.home_castle_id)
	change_scene_to_file("res://scenes/castle_interior/castle_interior.tscn")
	await _save("roles_04_duque")
	quit()
