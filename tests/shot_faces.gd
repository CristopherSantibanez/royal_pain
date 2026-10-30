extends SceneTree
# Capturas de las caras: mapa (jugador y ejércitos), relaciones y batalla con un pelotón seleccionado.

func _initialize() -> void:
	_run.call_deferred()

func _save(name: String) -> void:
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "/" + name + ".png")

func _run() -> void:
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var c = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	var MD = root.get_node("MapData")
	var AD = root.get_node("ArmyData")
	root.get_node("GameManager").start_new_game(c, MD.castles[0].castle_id)
	AD.create_army(c.full_name(), MD.castles[0].kingdom, 60, MD.castles[0].castle_id)
	var enemy_castle = null
	for k in MD.castles:
		if k.kingdom != MD.castles[0].kingdom:
			enemy_castle = k
			break
	AD.create_army(enemy_castle.owner_name, enemy_castle.kingdom, 80, enemy_castle.castle_id)
	change_scene_to_file("res://scenes/map/map.tscn")
	await create_timer(1.2).timeout
	_save("faces_map")
	change_scene_to_file("res://scenes/relations/relations.tscn")
	await create_timer(0.8).timeout
	_save("faces_relations")
	var army = AD.create_army(c.full_name(), MD.castles[0].kingdom, 120, enemy_castle.castle_id)
	army.pending_battle = true
	AD.active_battle_army = army
	change_scene_to_file("res://scenes/battle/battle.tscn")
	await create_timer(1.0).timeout
	var scene = current_scene
	for u in scene.battle.units:
		if scene.battle.is_player_unit(u):
			scene._on_cell_clicked(u.cell)
			break
	await create_timer(0.5).timeout
	_save("faces_battle")
	quit()
