extends SceneTree
# Capturas: un paso de historia en el mapa, el panel de Encargos con «Historias» y el aviso de viaje.
const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"

func _initialize() -> void:
	_run.call_deferred()

func _shot(n: String) -> void:
	await create_timer(0.9).timeout
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, n])

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var SD = root.get_node("StoryData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var p = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	GM.start_new_game(p, MD.castles[0].castle_id)
	GM.pending_event = {}
	GM.event_queue.clear()
	SD.start("herejia")
	# Primer paso resuelto («Escucharlo») para que el segundo muestre la opción que recuerda la marca.
	GM.resolve_pending_event(0)
	SD.active.due = GM.months_elapsed()
	SD._tick()
	change_scene_to_file("res://scenes/map/map.tscn")
	await _shot("story_01_paso")
	GM.pending_event = {}
	change_scene_to_file("res://scenes/map/map.tscn")
	await create_timer(0.6).timeout
	load("res://scripts/ui/missions_panel.gd").open(current_scene)
	await _shot("story_02_historias")
	# Aviso de viaje en «Tu destino».
	SD.reset()
	SD.start("reliquia")
	GM.resolve_pending_event(0)
	GM.pending_event = {}
	change_scene_to_file("res://scenes/map/map.tscn")
	await _shot("story_03_viaje")
	quit()
