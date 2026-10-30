extends SceneTree
# Abre el castillo en varias situaciones y lista los controles visibles que se salen de la ventana.
# Uso (con ventana, para capturas): godot --path . --script overflow_probe.gd

const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"

func _initialize() -> void:
	_run.call_deferred()

func _check(tag: String) -> void:
	await create_timer(0.6).timeout
	await process_frame
	var vp: Rect2 = root.get_visible_rect()
	var bad := 0
	var scene: Node = current_scene
	for n in _all(scene):
		var c := n as Control
		if c == null or not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		if r.size.x <= 1 or r.size.y <= 1:
			continue
		# Dentro de un ScrollContainer el desborde es normal.
		var inside_scroll := false
		var p: Node = c.get_parent()
		while p != null and p != scene:
			if p is ScrollContainer:
				inside_scroll = true
				break
			p = p.get_parent()
		if inside_scroll:
			continue
		if r.end.x > vp.end.x + 2 or r.end.y > vp.end.y + 2 or r.position.x < -2 or r.position.y < -2:
			bad += 1
			if bad <= 12:
				print("  [%s] SE SALE %s (%s) rect=%s" % [tag, scene.get_path_to(c), c.get_class(), r])
	print("[%s] controles fuera de la ventana: %d  (ventana %s)" % [tag, bad, vp.size])
	root.get_texture().get_image().save_png("%s/ovf_%s.png" % [OUT, tag])

func _all(n: Node) -> Array:
	var out := [n]
	for ch in n.get_children():
		out.append_array(_all(ch))
	return out

func _enter(castle) -> void:
	var GM = root.get_node("GameManager")
	var travel = root.get_node_or_null("TravelData")
	if travel != null:
		travel.location_id = castle.castle_id
	GM.current_castle = castle
	change_scene_to_file("res://scenes/castle_interior/castle_interior.tscn")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	for role in [CH.Role.CAMPESINO, CH.Role.SOLDADO, CH.Role.CABALLERO, CH.Role.NOBLEZA_BAJA, CH.Role.NOBLEZA_ALTA, CH.Role.DUQUE, CH.Role.REGENTE, CH.Role.CAPITAN, CH.Role.CONDOTIERO]:
		var p = CL.make_test_character("Sir Bartolomé de Valdemora y Castelbianco", role)
		GM.start_new_game(p, MD.castles[0].castle_id)
		await process_frame
		var home = MD.get_castle_by_id(GM.home_castle_id)
		_enter(home)
		await _check("casa_%s" % CH.role_name_for(role).replace(" ", "_"))
		# Mensaje largo en el panel de resultados.
		var sc = current_scene
		if sc.has_method("_show_feedback"):
			sc._show_feedback("Resultado muy largo. ".repeat(40))
		elif "action_feedback_label" in sc:
			sc.action_feedback_label.text = "Resultado muy largo. ".repeat(40)
		await _check("casa_%s_msg" % CH.role_name_for(role).replace(" ", "_"))
		_enter(MD.castles[2])
		await _check("ajeno_%s" % CH.role_name_for(role).replace(" ", "_"))
	quit()
