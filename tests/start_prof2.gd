extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var p = CL.make_test_character("Sir Prueba", CH.Role.CABALLERO)
	GM.start_new_game(p, MD.castles[0].castle_id)
	print("personas: ", RD.relations.size())
	var N := 50
	var t := Time.get_ticks_usec()
	for i in N:
		CL.make_random_character(CH.Role.CABALLERO, 0, "", "", "", 2)
	print("make_random_character (sin retrato): %.1f ms c/u" % ((Time.get_ticks_usec() - t) / 1000.0 / N))
	var pool = RD.PortraitPool.new([]) if "PortraitPool" in RD else null
	t = Time.get_ticks_usec()
	for i in N:
		RD.take_free_portrait(0)
	print("take_free_portrait: %.1f ms c/u" % ((Time.get_ticks_usec() - t) / 1000.0 / N))
	t = Time.get_ticks_usec()
	for i in N:
		RD.get_relation("Nadie %d" % i)
	print("get_relation: %.2f ms c/u" % ((Time.get_ticks_usec() - t) / 1000.0 / N))
	t = Time.get_ticks_usec()
	for i in N:
		CL.random_first_name(0, 2)
		CL.random_last_name(2, 0, 2)
	print("nombres: %.2f ms c/u" % ((Time.get_ticks_usec() - t) / 1000.0 / N))
	quit()
