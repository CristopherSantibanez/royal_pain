extends SceneTree
# Capturas de los efectos de «sensación de golpe».
const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"

func _initialize() -> void:
	_run.call_deferred()

func _real_wait(t: float) -> void:
	await create_timer(t, true, false, true).timeout

func _shot(n: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, n])
	print("captura ", n)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var CS = root.get_node("CombatSetup")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var EC = load("res://scripts/resources/event_catalog.gd")

	# 1. Duelo: crítico con su pausa, embestida, cifras y aplastamiento.
	CS.clear()
	CS.player_character = CL.make_test_character("Sir Bartolomé", CH.Role.CABALLERO)
	CS.enemy_character = CL.make_test_character("Lord Hermann", CH.Role.CABALLERO)
	change_scene_to_file("res://scenes/combat/combat.tscn")
	await _real_wait(1.0)
	var duel = current_scene
	duel._on_combat_event("crit", duel.player_character, duel.enemy_character, 18)
	await _real_wait(0.16)
	await _shot("gf_01_duelo_critico")
	duel.duel.advantage[duel.player_character] = "contra"
	duel._on_combat_event("advantage", duel.player_character, duel.enemy_character, 0)
	await _real_wait(0.7)
	await _shot("gf_02_duelo_ventaja")
	Engine.time_scale = 1.0

	# 2. Batalla: carga de caballería con estela y sacudida; luego cae el general.
	var p = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	GM.start_new_game(p, MD.castles[0].castle_id)
	MD.get_castle_by_id(GM.home_castle_id).garrison_size = 120
	var bandits: Dictionary = {}
	for e in EC.EVENTS:
		if e.id == "bandidos":
			bandits = e
	var fight: Dictionary = bandits.options.filter(func(o): return o.has("fight") and o.fight.type == "battle")[0].fight
	change_scene_to_file(CS.begin_event_fight(fight, bandits.title))
	await _real_wait(0.8)
	var bs = current_scene
	var b = bs.battle
	var mine: Array = b.units.filter(func(u): return b.is_player_unit(u))
	var foes: Array = b.units.filter(func(u): return not b.is_player_unit(u))
	var cav = mine[0]
	cav.type = BattleEnums.UnitType.CABALLERIA_PESADA if "CABALLERIA_PESADA" in BattleEnums.UnitType else BattleEnums.UnitType.CABALLERIA
	bs.board.play_attack(cav, foes[0], 34, 6, false)
	await _real_wait(0.12)
	await _shot("gf_03_batalla_carga")
	await _real_wait(0.8)
	bs._announce_general_fall("Cae Lord Hermann, general de los bandidos: su bando se rinde.")
	await _real_wait(0.75)
	await _shot("gf_04_cae_el_general")
	Engine.time_scale = 1.0

	# 3. Mapa: cambio de mes y estallido de conquista; latido del castillo.
	change_scene_to_file("res://scenes/map/map.tscn")
	await _real_wait(1.0)
	var m = current_scene
	var target = MD.castles[1]
	var MapJuice = load("res://scenes/map/map_juice.gd")
	m._on_castle_clicked(MD.castles[0])
	MapJuice.burst(m.castles_container, target.position_on_map, KingdomEnums.kingdom_color(target.kingdom))
	MapJuice.month_turn(m.get_node("UILayer"), GM.get_date_string())
	await _real_wait(0.3)
	await _shot("gf_05_mapa_conquista_mes")

	# 4. Opciones con las nuevas filas de accesibilidad.
	var OP = load("res://scripts/ui/options_panel.gd")
	OP.open(m.get_node("UILayer"))
	await _real_wait(0.4)
	await _shot("gf_06_opciones")
	quit()
