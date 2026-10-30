extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var GM = root.get_node("GameManager")
	var MI = root.get_node("MissionData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var p = CL.make_test_character("Sir Prueba", CH.Role.CABALLERO)
	GM.start_new_game(p, "hielo")
	await process_frame
	MI.accept({"id": "escolta", "title": "Escolta", "type": "risk", "chance": 0.5, "stat": "strategy", "months": 2, "text": "t",
		"reward": {"gold": 10}, "penalty": {"honor": -1}, "fail_effects": {}, "giver": "x", "uid": "a", "progress": 0})
	change_scene_to_file("res://scenes/castle_interior/castle_interior.tscn")
	await create_timer(0.5).timeout
	var panel = load("res://scripts/ui/missions_panel.gd").open(current_scene)
	await create_timer(0.3).timeout
	print("panel ok: ", panel.get_child_count() > 0, " | acción: ", MI.action_label(MI.active[0]))
	quit()
