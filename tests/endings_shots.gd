extends SceneTree
# Capturas: Nueva Partida (hazañas destacadas), panel «Tu destino», libro de hazañas y pantalla final.

const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots/"

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await create_timer(0.7).timeout
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(OUT + name)
		print("    captura ", name)

func _change(path: String) -> Node:
	change_scene_to_file(path)
	for i in 4:
		await process_frame
	return current_scene

func _run() -> void:
	seed(5)
	DirAccess.make_dir_recursive_absolute(OUT)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var AD = root.get_node("AchievementData")
	var WE = root.get_node("WorldEvents")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var scene = await _change("res://scenes/new_game/new_game.tscn")
	await _shot("end_01_nueva_partida.png")

	var player = CL.make_test_character("Sir Alaric", CH.Role.SOLDADO)
	GM.start_new_game(player, MD.castles[0].castle_id)
	player.duels_won = 3
	player.fame = 18
	player.gold = 420
	AD.check_all()
	while WE.has_notifications():
		WE.pop_notification()
	scene = await _change("res://scenes/map/map.tscn")
	while WE.has_notifications():
		WE.pop_notification()
	if scene.event_overlay.visible:
		scene.event_overlay.visible = false
	await _shot("end_02_mapa_destino.png")

	var panel = load("res://scripts/ui/achievements_panel.gd").open(scene.get_node("UILayer"))
	await _shot("end_03_libro_hazanas.png")
	panel.queue_free()

	for c in MD.castles:
		if c.kingdom != KingdomEnums.Kingdom.NEUTRAL:
			c.kingdom = GM.player_kingdom
	var ending: Dictionary = AD.check_endings()
	load("res://scripts/ui/ending_panel.gd").open(scene.get_node("UILayer"), ending)
	await _shot("end_04_final.png")
	print("hecho")
	quit()
