extends SceneTree
const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"

func _initialize() -> void:
	_run.call_deferred()

func _all(n: Node) -> Array:
	var out := [n]
	for ch in n.get_children():
		out.append_array(_all(ch))
	return out

func _run() -> void:
	var GM = root.get_node("GameManager")
	var CS = root.get_node("CombatSetup")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var EC = load("res://scripts/resources/event_catalog.gd")
	var p = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	GM.start_new_game(p, MD.castles[0].castle_id)
	MD.get_castle_by_id(GM.home_castle_id).garrison_size = 120
	var added := 0
	for r in RD.relations:
		if r.character != null and r.kind == Relationship.Kind.CORTESANO and added < 2:
			RD.retinue.append(r.person_name)
			added += 1
	var bandits: Dictionary = {}
	for e in EC.EVENTS:
		if e.id == "bandidos":
			bandits = e
	var fight: Dictionary = bandits.options.filter(func(o): return o.has("fight") and o.fight.type == "battle")[0].fight
	change_scene_to_file(CS.begin_event_fight(fight, bandits.title))
	await create_timer(1.0).timeout
	var vp: Rect2 = root.get_visible_rect()
	var bad := 0
	for n in _all(current_scene):
		var c := n as Control
		if c == null or not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		if r.size.x > 1 and r.size.y > 1 and (r.end.x > vp.end.x + 2 or r.end.y > vp.end.y + 2 or r.position.x < -2 or r.position.y < -2):
			bad += 1
	print("filas de reparto: %d · fuera de la ventana: %d" % [current_scene._alloc_rows.size(), bad])
	root.get_texture().get_image().save_png("%s/alloc_consejo.png" % OUT)
	quit()
