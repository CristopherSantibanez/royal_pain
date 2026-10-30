extends SceneTree
# Capturas del séquito v2: pestaña Séquito con plazas de íntimos, panel de gestión y duelo de práctica.

const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"

func _initialize() -> void:
	_run.call_deferred()

func _save(name: String) -> void:
	await create_timer(0.8).timeout
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var CS = root.get_node("CombatSetup")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var OR = load("res://scripts/resources/occupation_rules.gd")
	var p = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	p.gender = CharacterEnums.Gender.MASCULINO
	p.fame = 40
	p.honor = 70
	GM.start_new_game(p, MD.castles[0].castle_id)
	await process_frame
	var area: Array = RD.people_in_area().filter(func(r): return r.character != null and r.character.role != CH.Role.CAMPESINO)
	area.append_array(RD.people_in_area().filter(func(r): return r.character != null and r.character.role == CH.Role.CAMPESINO))
	area[0].affection = 88
	area[1].affection = 84
	area[2].affection = 62
	for r in area.slice(0, 3):
		GM.actions_remaining = 5
		RD.invite_to_retinue(r)
	RD._add_spouse_relation("Inés", "de Lara", 0, CharacterEnums.Gender.FEMENINO)
	RD.spouse_name = RD.relations.back().person_name
	RD.set_occupation(area[0], OR.ENTRENAR)
	RD.set_occupation(area[1], OR.ADMINISTRAR)
	RD.set_occupation(RD.relations.back(), OR.ESTUDIAR)
	RD.designated_champion = area[0].person_name
	GM.actions_remaining = 3
	RD.requested_tab = "sequito"
	change_scene_to_file("res://scenes/relations/relations.tscn")
	await _save("ret_01_sequito")

	var CompanionPanel = load("res://scripts/ui/companion_panel.gd")
	var sword: Equipment = null
	for e in root.get_node("GameData").equipment_catalog:
		if e.slot == "Arma" and e.tier == 2:
			sword = e.duplicate()
			break
	if sword != null:
		area[0].character.equip(sword)
	CompanionPanel.open(current_scene, area[0])
	await _save("ret_02_gestionar")

	RD.start_practice(area[0])
	CS.start_campaign_duel(p, area[0].character)
	CS.return_scene = "res://scenes/relations/relations.tscn"
	change_scene_to_file("res://scenes/combat/combat.tscn")
	await create_timer(0.8).timeout
	current_scene._player_action(0)
	await create_timer(2.5).timeout
	await _save("ret_03_practica")
	quit()
