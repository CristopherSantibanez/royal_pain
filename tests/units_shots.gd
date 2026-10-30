extends SceneTree
# Capturas: consejo antes de la batalla (negociar tropa), tablero con tropas nuevas, general e intenciones,
# y el Consejo de guerra.

const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"

func _initialize() -> void:
	_run.call_deferred()

func _save(name: String, wait: float = 0.7) -> void:
	await create_timer(wait).timeout
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	print("captura ", name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	seed(8)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var CS = root.get_node("CombatSetup")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var IC = load("res://scripts/resources/invitation_catalog.gd")
	var p = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	p.strategy = 13
	p.charisma = 12
	p.fame = 30
	p.mastery_xp = {"3": 200, "2": 60}   # piqueros 4, caballería 2
	GM.start_new_game(p, MD.castles[0].castle_id)
	await process_frame
	var home = MD.get_castle_by_id(GM.home_castle_id)
	home.garrison_size = 120
	var lord: Character = RD.character_of(home.owner_name)
	if lord != null:
		lord.mastery_xp = {"0": 1200, "1": 900, "seeded": 1}   # veterano: sus capitanes llevan tropa avanzada
	var enemy = null
	for id in home.connected_castle_ids:
		var c = MD.get_castle_by_id(id)
		if c.kingdom != home.kingdom:
			enemy = c
	if enemy == null:
		enemy = MD.get_castle_by_id(home.connected_castle_ids[0])
	var fe: Dictionary = IC.field_event(home, enemy, home.owner_name, home.owner_name, true)
	change_scene_to_file(CS.begin_event_fight(fe.options[0].fight, fe.title))
	await create_timer(1.0).timeout
	await _save("u_01_consejo_negociar", 0.5)
	var scene = current_scene
	var b = scene.battle
	scene._close_council()
	b.weather = BattleEnums.Weather.NIEBLA
	b.time_of_day = BattleEnums.TimeOfDay.DIA
	# Acerca un enemigo para que se vea la lectura de intenciones.
	var mine = b.player_unit()
	var foes = b.active_units(b._other_side(b.player_side))
	for i in mini(2, foes.size()):
		var target_cell: Vector2i = mine.cell + Vector2i(3 if b.player_side == BattleEnums.Side.ATACANTE else -3, i)
		if b.in_bounds(target_cell) and b.unit_at(target_cell) == null:
			foes[i].cell = target_cell
	scene.selected = mine
	scene._refresh()
	await _save("u_02_tablero_general_intenciones", 0.8)
	p.role = CH.Role.NOBLEZA_BAJA
	var WCP = load("res://scripts/ui/war_council_panel.gd")
	WCP.open(scene)
	await _save("u_03_consejo_de_guerra", 0.8)
	quit()
