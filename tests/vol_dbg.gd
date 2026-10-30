extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var GM = root.get_node("GameManager"); var MD = root.get_node("MapData"); var RD = root.get_node("RelationsData")
	var CL = load("res://scripts/resources/character_loader.gd"); var CH = load("res://scripts/resources/character.gd")
	var p = CL.make_test_character("Juan", CH.Role.INAFILIADO)
	GM.start_new_game(p, MD.castles[0].castle_id)
	await process_frame
	var far = MD.get_castle_by_id(MD.castles[0].connected_castle_ids[0])
	for id in far.connected_castle_ids:
		var c = MD.get_castle_by_id(id)
		print(id, " k=", c.kingdom, " far.k=", far.kingdom, " owner=", c.owner_name)
	var lord = RD.get_relation(far.owner_name)
	print("lord ", lord != null, " at_war ", lord.at_war if lord else null, " hostile ", lord.is_hostile() if lord else null)
	for id in far.connected_castle_ids:
		var c = MD.get_castle_by_id(id)
		if c.kingdom != far.kingdom:
			print("declare ", KingdomDiplomacy.declare_war(RD.kingdom_wars, RD.kingdom_alliances, far.kingdom, c.kingdom, 0), " at_war ", KingdomDiplomacy.at_war(RD.kingdom_wars, far.kingdom, c.kingdom), " defended ", root.get_node("ArmyData").is_player_defended(c))
			break
	print("ev ", root.get_node("ArmyData").volunteer_event(far).keys())
	quit()
