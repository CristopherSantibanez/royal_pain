extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	seed(7)
	var out: String = OS.get_cmdline_user_args()[0]
	var GM = root.get_node("GameManager")
	var RD = root.get_node("RelationsData")
	var DD = root.get_node("DynastyData")
	var c = load("res://scripts/resources/character_loader.gd").make_test_character("Sir Alaric", load("res://scripts/resources/character.gd").Role.CABALLERO)
	c.gender = CharacterEnums.Gender.MASCULINO
	GM.start_new_game(c, root.get_node("MapData").castles[0].castle_id)
	for r in RD.relations:
		if r.character != null and r.character.gender == CharacterEnums.Gender.FEMENINO and r.kind != Relationship.Kind.SENOR:
			r.kind = Relationship.Kind.CONYUGE
			r.character.age = 22
			RD.spouse_name = r.person_name
			break
	for y in 20:
		GM.current_month = 12
		GM.advance_turn()
		GM.pending_event = {}
	root.get_node("WorldEvents").notifications.clear()
	c.gain_xp(650)
	change_scene_to_file("res://scenes/map/map.tscn")
	await create_timer(0.8).timeout
	root.get_node("WorldEvents").notifications.clear()
	var p = load("res://scripts/ui/level_up_panel.gd").open(current_scene.get_node("UILayer"))
	await create_timer(0.3).timeout
	p._change("combat", 1)
	p._change("leadership", 1)
	await create_timer(0.4).timeout
	root.get_texture().get_image().save_png(out + "/levelup.png")
	p._tabs.current_tab = 1
	await create_timer(0.4).timeout
	root.get_texture().get_image().save_png(out + "/family.png")
	p.queue_free()
	DD.on_player_died("de vejez, a los %d años" % c.age)
	await create_timer(1.2).timeout
	root.get_texture().get_image().save_png(out + "/succession.png")
	quit()
