extends SceneTree
# Capturas del combate nuevo: aviso de duelo a muerte, ventaja en el duelo y batallas con clima y mapa.

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
	var BE = load("res://scripts/resources/battle_enums.gd")
	var GM = root.get_node("GameManager")
	var CS = root.get_node("CombatSetup")
	var MD = root.get_node("MapData")
	var c = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	GM.start_new_game(c, MD.castles[0].castle_id)
	# Duelo a muerte: primero el aviso, luego el duelo con una ventaja activa.
	CS.start_campaign_duel(c, CL.make_test_character("Caballero Negro", CH.Role.CABALLERO))
	CS.duel_to_death = true
	CS.return_scene = "res://scenes/map/map.tscn"
	change_scene_to_file("res://scenes/combat/combat.tscn")
	await create_timer(0.8).timeout
	await _save("c2_01_a_muerte_aviso")
	for n in current_scene.get_children():
		if n is ColorRect and n.z_index == 70:
			for b in n.find_children("*", "Button", true, false):
				b.pressed.emit()
	await create_timer(0.6).timeout
	var scene = current_scene
	if scene.duel != null:
		scene.duel.advantage[scene.player_character] = "contra"
		scene.duel.unbalanced[scene.enemy_character] = true
		scene._refresh_ui()
		scene._hovered_order = "Atacar"
		scene.hint_label.text = scene._order_hint("Atacar")
		scene._update_turn_indicator()
	await create_timer(0.3).timeout
	await _save("c2_02_duelo_ventaja")
	CS.clear()
	# Batallas: un asedio por reino con clima distinto.
	var ad = root.get_node("ArmyData")
	var shots := [[1, BE.Weather.LLUVIA, BE.TimeOfDay.DIA], [8, BE.Weather.DESPEJADO, BE.TimeOfDay.ATARDECER],
		[0, BE.Weather.NIEVE, BE.TimeOfDay.NOCHE], [4, BE.Weather.NIEBLA, BE.TimeOfDay.DIA]]
	var i := 0
	for spec in shots:
		var target = null
		for k in MD.castles:
			if k.kingdom == spec[0] and k.kingdom != MD.castles[0].kingdom:
				target = k
				break
		if target == null:
			for k in MD.castles:
				if k.kingdom != MD.castles[0].kingdom:
					target = k
					break
		var army = ad.create_army(c.full_name(), MD.castles[0].kingdom, 120, target.castle_id)
		army.pending_battle = true
		ad.active_battle_army = army
		change_scene_to_file("res://scenes/battle/battle.tscn")
		await create_timer(0.7).timeout
		var bs = current_scene
		bs.battle.weather = spec[1]
		bs.battle.time_of_day = spec[2]
		bs._show_banner("%s\n%s" % [bs.battle.conditions_text(), "El campo: " + bs.battle.map_feature])
		for u in bs.battle.units:
			if bs.battle.is_player_unit(u):
				bs.selected = u
				bs.battle.set_order(u, BE.Order.MANTENER if i % 2 == 0 else BE.Order.CARGAR)
				break
		bs._refresh()
		await create_timer(0.4).timeout
		await _save("c2_1%d_batalla_%s" % [i, BE.weather_name(spec[1]).to_lower()])
		i += 1
	quit()
