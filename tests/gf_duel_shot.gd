extends SceneTree
const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"
func _initialize() -> void:
	_run.call_deferred()
func _w(t: float) -> void:
	await create_timer(t, true, false, true).timeout
func _run() -> void:
	var CS = root.get_node("CombatSetup")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	CS.clear()
	CS.player_character = CL.make_test_character("Sir Bartolomé", CH.Role.CABALLERO)
	CS.enemy_character = CL.make_test_character("Lord Hermann", CH.Role.CABALLERO)
	change_scene_to_file("res://scenes/combat/combat.tscn")
	await _w(2.5)
	var d = current_scene
	var before: Vector2 = d.portrait_enemy.position
	var sm_before: Vector2 = d.screen_margin.position
	root.get_texture().get_image().save_png("%s/gf_01a_duelo_antes.png" % OUT)
	for i in 3:   # tres golpes seguidos: no debe quedar nada desplazado
		d._on_combat_event("crit", d.player_character, d.enemy_character, 18)
		await _w(0.05)
	await _w(0.08)
	root.get_texture().get_image().save_png("%s/gf_01_duelo_critico.png" % OUT)
	await _w(1.5)
	print("retrato desplazado: ", d.portrait_enemy.position - before, " · pantalla desplazada: ", d.screen_margin.position - sm_before, " · time_scale ", Engine.time_scale)
	quit()
