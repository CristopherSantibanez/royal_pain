extends SceneTree
# Sonda de desbordes: abre pantallas y paneles y lista controles que se salen de la ventana.
# Ignora lo que está dentro de un ScrollContainer y los controles del mundo del mapa (hijos de Node2D).

const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"
var total_bad := 0

func _initialize() -> void:
	_run.call_deferred()

func _all(n: Node) -> Array:
	var out := [n]
	for ch in n.get_children():
		out.append_array(_all(ch))
	return out

func _ignored(c: Control) -> bool:
	var p: Node = c.get_parent()
	while p != null and p != root:
		if p is ScrollContainer or p is Node2D:
			return true
		p = p.get_parent()
	return false

func _check(tag: String, shot := true) -> void:
	await create_timer(0.6).timeout
	await process_frame
	var vp: Rect2 = root.get_visible_rect()
	var worst: Array = []
	for n in _all(root):
		var c := n as Control
		if c == null or not c.is_visible_in_tree() or _ignored(c):
			continue
		var r := c.get_global_rect()
		if r.size.x <= 1 or r.size.y <= 1:
			continue
		var over: float = maxf(maxf(r.end.x - vp.end.x, r.end.y - vp.end.y), maxf(-r.position.x, -r.position.y))
		if over > 2.0:
			worst.append([over, str(root.get_path_to(c)).right(90), c.get_class(), r])
	worst.sort_custom(func(a, b): return a[0] > b[0])
	# Solo los "más externos" interesan: se listan los 4 de mayor desborde.
	print("[%s] fuera: %d" % [tag, worst.size()])
	for w in worst.slice(0, 4):
		print("    %.0fpx %s (%s) %s" % w)
	total_bad += 1 if not worst.is_empty() else 0
	if shot and not worst.is_empty():
		root.get_texture().get_image().save_png("%s/ovf_%s.png" % [OUT, tag])

func _scene(path: String) -> void:
	change_scene_to_file(path)
	await create_timer(0.5).timeout

func _close_popups(host: Node, keep: int) -> void:
	while host.get_child_count() > keep:
		var ch := host.get_child(host.get_child_count() - 1)
		host.remove_child(ch)
		ch.queue_free()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")

	await _scene("res://scenes/main_menu/main_menu.tscn"); await _check("menu")
	await _scene("res://scenes/new_game/new_game.tscn"); await _check("nueva_partida")
	await _scene("res://scenes/glossary/glossary.tscn"); await _check("glosario")
	await _scene("res://scenes/character_manager/character_manager.tscn"); await _check("personajes")

	for role in [CH.Role.CAMPESINO, CH.Role.CABALLERO, CH.Role.NOBLEZA_BAJA, CH.Role.DUQUE, CH.Role.CAPITAN]:
		var rn: String = CH.role_name_for(role).replace(" ", "_").replace("á", "a")
		var p = CL.make_test_character("Sir Bartolomé de Valdemora y Castelbianco", role)
		GM.start_new_game(p, MD.castles[0].castle_id)
		await process_frame
		p.gold = 99999
		await _scene("res://scenes/map/map.tscn"); await _check("mapa_" + rn)
		await _scene("res://scenes/relations/relations.tscn"); await _check("relaciones_" + rn)
		var home = MD.get_castle_by_id(GM.home_castle_id)
		GM.current_castle = home
		await _scene("res://scenes/castle_interior/castle_interior.tscn"); await _check("castillo_" + rn)
		var host: Node = current_scene
		var keep := host.get_child_count()
		var some_rel = null
		for r in RD.relations:
			if r.character != null:
				some_rel = r
				break
		var panels := [
			["logros", func(): load("res://scripts/ui/achievements_panel.gd").open(host)],
			["nivel", func(): load("res://scripts/ui/level_up_panel.gd").open(host)],
			["encargos", func(): load("res://scripts/ui/missions_panel.gd").open(host)],
			["opciones", func(): load("res://scripts/ui/options_panel.gd").open(host)],
			["tienda", func(): load("res://scripts/ui/shop_panel.gd").open(host)],
			["obras", func(): load("res://scripts/ui/works_panel.gd").open(host, home)],
			["consejo", func(): load("res://scripts/ui/war_council_panel.gd").open(host)],
			["audiencia", func(): load("res://scripts/ui/audience_panel.gd").open(host, MD.castles[2])],
			["grupo", func(): load("res://scripts/ui/party_panel.gd").open(host)],
		]
		if some_rel != null:
			panels.append(["perfil", func(): load("res://scripts/ui/character_profile.gd").open(host, some_rel)])
			panels.append(["conversar", func(): load("res://scripts/ui/conversation_panel.gd").open(host, some_rel)])
			panels.append(["gestionar", func(): load("res://scripts/ui/companion_panel.gd").open(host, some_rel)])
		for entry in panels:
			var ok := true
			entry[1].call()
			await _check("%s_%s" % [entry[0], rn])
			_close_popups(host, keep)
	print("PANTALLAS CON DESBORDE: ", total_bad)
	quit()
