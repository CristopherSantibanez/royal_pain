extends SceneTree
# Captura de la pantalla del combate RPG con un grupo de 4 (retratos propios) contra enemigos genéricos.

const OUT := "res://tests/_shots/rpg_combate.png"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var CS = root.get_node("CombatSetup")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var p = CL.make_test_character("Sir Bartolomé", CH.Role.CABALLERO)
	GM.start_new_game(p, MD.castles[0].castle_id)
	await process_frame
	# Tres compañeros con retrato propio en el séquito.
	var added := 0
	for r in RD.relations:
		if added >= 3:
			break
		if r.character != null and r.character.portrait != null and r.kind == r.Kind.CORTESANO:
			RD.retinue.append(r.person_name)
			added += 1
	var fight := {"type": "duel", "no_rival": true, "foe": {"name": "Capitán de bandidos", "role": CH.Role.SOLDADO, "power": 1, "personality": "CRUEL"}}
	CS.tag_fight(fight, "camino") if CS.has_method("tag_fight") else null
	var scene_path: String = CS.begin_event_fight(fight, "Emboscada en el camino")
	change_scene_to_file(scene_path)
	await create_timer(1.5).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_shots"))
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT))
	print("captura: ", OUT)
	quit()
