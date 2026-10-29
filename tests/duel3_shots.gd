extends SceneTree
# Capturas del duelo v3: postura Desesperada (botones apagados) con aviso de lectura, y la ventana de Nivel.

var out_dir := ""

func _initialize() -> void:
	out_dir = OS.get_cmdline_user_args()[0]
	_run.call_deferred()

func _save(name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])

func _run() -> void:
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var CE = load("res://scripts/resources/combat_enums.gd")
	var GM = root.get_node("GameManager")
	var CS = root.get_node("CombatSetup")
	var MD = root.get_node("MapData")
	var c = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	c.strategy = 18
	c.fighter_type = CharacterEnums.FighterType.ESTRATEGA
	GM.start_new_game(c, MD.castles[0].castle_id)
	var foe = CL.make_test_character("Sir Godofredo", CH.Role.CABALLERO)
	foe.strategy = 2
	CS.start_campaign_duel(c, foe)
	CS.return_scene = "res://scenes/map/map.tscn"
	change_scene_to_file("res://scenes/combat/combat.tscn")
	await create_timer(0.8).timeout
	var scene = current_scene
	# Cierra la ventana de campeón si aparece.
	for n in scene.get_children():
		if n is ColorRect and n.z_index == 70:
			var btns = n.find_children("*", "Button", true, false)
			if not btns.is_empty():
				btns[0].pressed.emit()
	await create_timer(0.6).timeout
	scene = current_scene
	var guard := 0
	while (scene.duel == null or not scene.player_turn) and guard < 10:
		await create_timer(0.5).timeout
		guard += 1
	# Fuerza un aviso de lectura para la captura (la probabilidad ya es alta con Estrategia 18 vs 2).
	if scene._enemy_intent.is_empty():
		scene._enemy_intent = DuelAI.choose(scene.duel, scene.enemy_character, c)
		scene.turn_log_buffer += "\n👁 " + DuelManager.intent_text(scene._enemy_intent)
		scene.log_label.text = scene.turn_log_buffer
	scene._player_posture(CE.Posture.DESESPERADA)
	scene._hovered_order = "Esquivar"
	scene.hint_label.text = scene._order_hint("Esquivar")
	scene._refresh_ui()
	await create_timer(0.4).timeout
	await _save("d3_01_duelo_desesperada_lectura")
	# Ventana de Nivel con la afinidad del tipo de luchador.
	c.gain_xp(650)
	change_scene_to_file("res://scenes/map/map.tscn")
	await create_timer(0.9).timeout
	root.get_node("WorldEvents").notifications.clear()
	var p = load("res://scripts/ui/level_up_panel.gd").open(current_scene.get_node("UILayer"))
	await create_timer(0.5).timeout
	await _save("d3_02_nivel")
	quit()
