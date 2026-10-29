extends SceneTree
# Captura cada pantalla del juego. Uso: --script shots.gd -- <carpeta_salida> [prefijo]

var out_dir := ""
var prefix := ""
var only := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0]
	prefix = args[1] if args.size() > 1 else ""
	only = args[2] if args.size() > 2 else ""
	_run.call_deferred()

func _shot(scene: String, name: String, wait: float = 0.8) -> void:
	if only != "" and not Array(only.split(",")).any(func(o): return name.contains(o)):
		return
	change_scene_to_file(scene)
	await create_timer(wait).timeout
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png("%s/%s%s.png" % [out_dir, prefix, name])

func _run() -> void:
	await _shot("res://scenes/main_menu/main_menu.tscn", "01_main_menu")
	if only.contains("options"):
		change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
		await create_timer(0.8).timeout
		load("res://scripts/ui/options_panel.gd").open(current_scene)
		await create_timer(0.5).timeout
		root.get_texture().get_image().save_png("%s/%s01b_options.png" % [out_dir, prefix])
	await _shot("res://scenes/new_game/new_game.tscn", "02_new_game")
	await _shot("res://scenes/character_creation/character_creation.tscn", "03_character_creation")
	await _shot("res://scenes/fighter_select/fighter_select.tscn", "04_fighter_select")
	await _shot("res://scenes/combat/combat.tscn", "05_combat")
	# Partida de prueba
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var c = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	var castle_id: String = root.get_node("MapData").castles[0].castle_id
	root.get_node("GameManager").start_new_game(c, castle_id)
	await _shot("res://scenes/map/map.tscn", "06_map", 1.2)
	await _shot("res://scenes/castle_interior/castle_interior.tscn", "07_castle")
	var RD = root.get_node("RelationsData")
	var court = RD.courtiers()
	if court.size() > 1:
		court[0].affection = 55
		court[1].affection = 25
	if only.contains("court"):
		change_scene_to_file("res://scenes/relations/relations.tscn")
		await create_timer(0.8).timeout
		current_scene.get_node("%Tabs").current_tab = 2
		await create_timer(0.5).timeout
		root.get_texture().get_image().save_png("%s/%s08b_court.png" % [out_dir, prefix])
	await _shot("res://scenes/relations/relations.tscn", "08_relations")
	await _shot("res://scenes/character_summary/character_summary.tscn", "09_character_summary")
	await _shot("res://scenes/save_slots/save_slots.tscn", "10_save_slots")
	# Batalla pendiente contra un castillo de otro reino
	var ad = root.get_node("ArmyData")
	var md = root.get_node("MapData")
	var target = null
	for k in md.castles:
		if k.kingdom != md.castles[0].kingdom:
			target = k
			break
	var army = ad.create_army(c.full_name(), md.castles[0].kingdom, 120, target.castle_id)
	army.pending_battle = true
	ad.active_battle_army = army
	await _shot("res://scenes/battle/battle.tscn", "11_battle")
	quit()
