extends SceneTree
# El combate usa el fondo del bioma del lugar donde está el jugador.

var fails := 0

func check(c: bool, what: String) -> void:
	print(("  ok  " if c else "  FALLA ") + what)
	if not c:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var BB = load("res://scripts/resources/biome_backgrounds.gd")
	for k in KingdomEnums.Kingdom.values():
		var b: String = BB.biome_of_kingdom(k)
		check(BB.texture_for(b) != null, "reino %d → %s con fondo" % [k, b])
	check(BB.texture_for("torneo").resource_path.ends_with("Trining_Ground.png"), "torneo → patio de armas")
	# En partida: el fondo sigue al castillo donde está el jugador.
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var TD = root.get_node("TravelData")
	var CS = root.get_node("CombatSetup")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	GM.start_new_game(CL.make_test_character("Sir Prueba", CH.Role.CABALLERO), MD.castles[0].castle_id)
	await process_frame
	for c in MD.castles:
		TD.location_id = c.castle_id
		check(BB.current_biome() == BB.biome_of_kingdom(c.kingdom), "en %s → %s" % [c.castle_name, BB.current_biome()])
	var fight := {"type": "duel", "no_rival": true, "foe": {"name": "Salteador", "role": CH.Role.SOLDADO, "power": 1, "personality": "CRUEL"}}
	change_scene_to_file(CS.begin_event_fight(fight, "Prueba de fondo"))
	await create_timer(1.0).timeout
	var expected: Texture2D = BB.texture_for(BB.current_biome())
	check(current_scene.background.texture != null and current_scene.background.texture.resource_path == expected.resource_path, "la pantalla de combate usa el fondo del bioma (%s)" % expected.resource_path.get_file())
	print("FALLAS: ", fails)
	quit()
