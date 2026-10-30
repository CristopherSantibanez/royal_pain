extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var MD = root.get_node("MapData")
	var NC = load("res://scripts/resources/name_catalog.gd")
	for s in [11, 222]:
		MD.new_world(s)
		print("--- mundo ", s)
		for c in MD.castles:
			print("  %s [%s] · %s" % [c.castle_name, NC.culture_name(c.culture), c.owner_name])
	for cu in NC.CULTURE_COUNT:
		var line := []
		for i in 4:
			line.append(NC.full_name(cu, CharacterEnums.Gender.MASCULINO, [0, 1, 2, 4][i]))
			line.append(NC.full_name(cu, CharacterEnums.Gender.FEMENINO, [0, 2, 3, 4][i]))
		print(NC.culture_name(cu), ": ", ", ".join(line))
	quit()
