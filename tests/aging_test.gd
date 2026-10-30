extends SceneTree
var fails := 0
func check(c: bool, w: String) -> void:
	print(("  ok  " if c else "  FALLA ") + w)
	if not c: fails += 1
func _initialize() -> void:
	_run.call_deferred()
func _january(GM) -> void:
	GM.current_month = 12
	GM.advance_turn()
	await process_frame
	if GM.has_pending_event():
		GM.pending_event = {}
func _run() -> void:
	seed(3)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var DD = root.get_node("DynastyData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var player = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	DD.aging_enabled = false
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame
	check(DD.aging_enabled == false, "la opción sobrevive al reset de nueva partida")
	player.age = 80
	var child = CL.make_child(player, player, "Alaric")
	DD._children.append(child)
	for i in 5:
		await _january(GM)
	check(player.age == 80, "el jugador no envejece (tiene %d)" % player.age)
	check(not DD.needs_succession(), "no muere de viejo a los 80 en 5 años")
	check(child.age == 5, "el hijo sí crece (tiene %d)" % child.age)
	var st: Dictionary = DD.save_state()
	DD.aging_enabled = true
	DD.load_state(st)
	check(DD.aging_enabled == false, "se guarda y carga la opción")
	DD.load_state({"children": []})
	check(DD.aging_enabled == true, "partidas antiguas: envejecen por defecto")
	print("FALLAS: ", fails)
	quit(fails)
