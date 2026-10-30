extends SceneTree
# Capturas del mundo 2: nueva partida con nombres de reino, mapa, relaciones (señores aquí / por carta),
# armería con forja de pieza única y ficha con pieza única. Sin --headless guarda PNG.

const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots/"

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await create_timer(0.6).timeout
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(OUT + name)
		print("    captura ", name)

func _change(path: String) -> Node:
	change_scene_to_file(path)
	for i in 4:
		await process_frame
	return current_scene

func _run() -> void:
	seed(9)
	DirAccess.make_dir_recursive_absolute(OUT)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var UI = load("res://scripts/resources/unique_items.gd")
	await _change("res://scenes/new_game/new_game.tscn")
	await _shot("w2_01_nueva_partida.png")

	var player = CL.make_test_character("Sir Alaric", CH.Role.NOBLEZA_BAJA)
	player.gold = 3000
	player.honor = 60
	var home = null
	for c in MD.castles:
		if c.owner_name != RD.NO_LORD and c.kingdom != KingdomEnums.Kingdom.NEUTRAL:
			home = c
			break
	GM.start_new_game(player, home.castle_id)
	GM.current_month = 5
	GM.actions_remaining = 6
	GM.actions_per_turn = 6
	await _change("res://scenes/map/map.tscn")
	await _shot("w2_02_mapa.png")

	RD.requested_tab = "senores"
	await _change("res://scenes/relations/relations.tscn")
	await _shot("w2_03_senores_carta.png")

	home.buildings["herreria"] = 3
	GM.current_castle = home
	var shop = load("res://scripts/ui/shop_panel.gd").open(current_scene)
	await _shot("w2_04_forja.png")
	shop.queue_free()

	UI.grant(player, "Durandal")
	var someone: Relationship = RD.people_in_area()[0]
	UI.grant(someone.character, "Oriflama de San Dionisio")
	RD.requested_tab = "lugar"
	await _change("res://scenes/relations/relations.tscn")
	load("res://scripts/ui/character_profile.gd").open(current_scene, someone)
	await _shot("w2_05_ficha_unica.png")
	quit()
