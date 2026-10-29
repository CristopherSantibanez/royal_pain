extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	for i in 60:
		var t := Time.get_ticks_msec()
		var p = CL.make_test_character("Sir Prueba", CH.Role.CABALLERO)
		GM.start_new_game(p, MD.castles[0].castle_id)
		var t2 := Time.get_ticks_msec()
		for m in 3:
			GM.pending_event = {}
			GM.advance_turn()
		print("partida %d: inicio %d ms, 3 meses %d ms" % [i, t2 - t, Time.get_ticks_msec() - t2])
	quit()
