extends SceneTree
# Gestor de grupo (PartyData): relleno por defecto, máximo 4 contigo dentro, cambios, bajas y guardado.

var fails := 0

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(7)
	var GM = root.get_node("GameManager")
	var RD = root.get_node("RelationsData")
	var MD = root.get_node("MapData")
	var PD = root.get_node("PartyData")
	var CD = root.get_node("CaptureData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var SS = load("res://scripts/resources/save_system.gd")
	var player = CL.make_test_character("Juan Grupo", CH.Role.CABALLERO)
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame
	check(PD.active() == [player] and PD.reserve().is_empty(), "sin séquito: solo tú")
	var people: Array = RD.relations.filter(func(r): return r.character != null and r.character.role != CH.Role.CAMPESINO and not RD.is_spouse(r.person_name)).slice(0, 5)
	for i in people.size():
		people[i].character.level = 1 + i   # el último es el más fuerte
		RD.retinue.append(people[i].person_name)
	var act: Array = PD.active()
	check(act.size() == 4 and act[0] == player, "activos: 4 contigo primero (%d)" % act.size())
	check(people[4].character in act and people[3].character in act and not people[0].character in act, "por defecto, los 3 más fuertes")
	check(PD.reserve().size() == 2, "2 en reserva")
	print("[cambios]")
	var low = people[0].character
	var top = people[4].character
	PD.swap(top, low)
	check(PD.is_active(low) and not PD.is_active(top), "swap activo<->reserva")
	PD.swap(player, top)
	check(PD.is_active(player), "nunca sales del grupo con swap")
	check(not PD.to_reserve(player), "no puedes reservarte")
	PD.set_active([people[0].character, people[1].character, people[2].character, people[3].character, people[4].character])
	act = PD.active()
	check(act.size() == 4 and player in act and not people[3].character in act, "set_active recorta a 4 y te incluye")
	check(PD.to_reserve(people[1].character) and PD.activate(people[4].character), "reservar y activar")
	PD.move(people[4].character, -1)
	check(PD.active().find(people[4].character) == 2, "subir un puesto")
	print("[bajas]")
	people[4].character.current_health = 0
	check(not people[4].character in PD.members() and not PD.is_active(people[4].character), "quien muere sale del grupo")
	people[4].character.current_health = 50
	PD.activate(people[4].character)
	RD.dismiss_from_retinue(people[2])
	check(not PD.is_active(people[2].character) and not people[2].character in PD.reserve(), "quien se va sale del grupo")
	CD.capture(people[0].character, null, false)
	if CD.is_prisoner(people[0].person_name):
		check(not PD.is_active(people[0].character), "quien cae preso sale del grupo")
	print("[guardado]")
	var before: Array = PD.active().map(func(c): return c.full_name())
	check(SS.save_game() == OK, "guardar")
	PD.reset()
	check(SS.load_game(), "cargar")
	var after: Array = PD.active().map(func(c): return c.full_name())
	check(after == before, "el orden del grupo se conserva (%s → %s)" % [", ".join(before), ", ".join(after)])
	print("[panel]")
	var panel = load("res://scripts/ui/party_panel.gd").open(root)
	await process_frame
	check(panel.is_inside_tree(), "el panel se abre")
	panel.queue_free()
	print("FALLOS: %d" % fails)
	quit(1 if fails > 0 else 0)
