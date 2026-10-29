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
	var kinds := {}
	var male := 0
	var female := 0
	var no_portrait := 0
	for r in RD.relations:
		kinds[r.kind] = kinds.get(r.kind, 0) + 1
		if r.character != null:
			if r.character.gender == CharacterEnums.Gender.MASCULINO: male += 1
			else: female += 1
			if r.character.portrait == null: no_portrait += 1
	var neutral := 0
	for c in MD.castles:
		if c.kingdom == KingdomEnums.Kingdom.NEUTRAL: neutral += 1
	print("castillos: %d (neutrales %d)" % [MD.castles.size(), neutral])
	print("personajes: %d · por tipo: %s" % [RD.relations.size(), kinds])
	print("hombres %d · mujeres %d · sin retrato propio %d · retratos usados %d" % [male, female, no_portrait, RD.used_portraits.size()])
	quit()
