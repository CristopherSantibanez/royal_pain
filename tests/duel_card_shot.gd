extends SceneTree
const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var CS = root.get_node("CombatSetup")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var SC = load("res://scripts/resources/site_catalog.gd")
	var p = CL.make_test_character("Sir Bartolomé de Valdemora", CH.Role.CABALLERO)
	GM.start_new_game(p, MD.castles[0].castle_id)
	await process_frame
	# Texto de recompensa de la torre (combate ganado).
	var fight: Dictionary = SC.SITES.torre_negra.options[0].fight if "SITES" in SC else {}
	if fight.is_empty():
		for k in SC.get_script_constant_map():
			pass
	CS.begin_event_fight(fight, "Torre del Desafío")
	var text: String = CS.apply_outcome(true)
	print("--- RECOMPENSA ---\n", text, "\n------------------")
	# Tarjeta del duelo con varios estados a la vez.
	CS.clear()
	CS.player_character = CL.make_test_character("Sir Bartolomé de Valdemora", CH.Role.CABALLERO)
	CS.enemy_character = CL.make_test_character("Lord Hermann von Hohenstein", CH.Role.CABALLERO)
	change_scene_to_file("res://scenes/combat/combat.tscn")
	await create_timer(1.0).timeout
	var sc = current_scene
	var me = sc.player_character
	var foe = sc.enemy_character
	sc.duel.advantage[me] = DuelManager.ADV_CONTRA
	sc.duel.countering[foe] = true
	sc.duel.unbalanced[foe] = true
	sc._refresh_ui()
	await create_timer(0.4).timeout
	root.get_texture().get_image().save_png("%s/duel_card.png" % OUT)
	quit()
