extends SceneTree
# Mide cuánto tarda cada receptor de game_started al empezar partida.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var t0 := Time.get_ticks_msec()
	MD.new_world()
	print("new_world: %d ms" % (Time.get_ticks_msec() - t0))
	var p = CL.make_test_character("Sir Prueba", CH.Role.CABALLERO)
	# Cronometrar cada conexión de game_started por separado.
	var conns: Array = GM.game_started.get_connections()
	for c in conns:
		GM.game_started.disconnect(c.callable)
	t0 = Time.get_ticks_msec()
	GM.start_new_game(p, MD.castles[0].castle_id)
	print("start_new_game (sin receptores): %d ms" % (Time.get_ticks_msec() - t0))
	for c in conns:
		var t := Time.get_ticks_msec()
		c.callable.call(p)
		var dt := Time.get_ticks_msec() - t
		var obj = c.callable.get_object()
		print("  %5d ms  %s.%s" % [dt, obj.name if obj is Node else str(obj), c.callable.get_method()])
		GM.game_started.connect(c.callable)
	quit()
