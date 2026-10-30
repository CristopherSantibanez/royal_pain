extends SceneTree
# Capturas y sonda de desbordes de lo nuevo: pestaña Prisioneros, evento de cautiverio,
# elección de compañeros antes de la batalla y batalla con sus pelotones. Se ejecuta con ventana.

const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"
var GM
var CS
var MD
var AD
var RD
var TD
var KD
var bad := 0

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

func _shot(name: String) -> void:
	await create_timer(0.7).timeout
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
			worst.append([over, str(root.get_path_to(c)).right(80), c.get_class()])
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("[%s] fuera: %d" % [name, worst.size()])
	for w in worst.slice(0, 4):
		print("    %.0fpx %s (%s)" % w)
	bad += 1 if not worst.is_empty() else 0
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])

func _courtier(skip_kingdom: int):
	for r in RD.courtiers(-1):
		if r.character != null and r.kingdom != skip_kingdom and not r.person_name in RD.retinue:
			return r
	return null

func _run() -> void:
	seed(21)
	DirAccess.make_dir_recursive_absolute(OUT)
	GM = root.get_node("GameManager")
	CS = root.get_node("CombatSetup")
	MD = root.get_node("MapData")
	AD = root.get_node("ArmyData")
	RD = root.get_node("RelationsData")
	TD = root.get_node("TravelData")
	KD = root.get_node("CaptureData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var player = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	player.gold = 900
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame
	GM.pending_event = {}

	# Batalla ajena con dos compañeros: el consejo pregunta quién te acompaña.
	var mates: Array = []
	for r in RD.courtiers(GM.player_kingdom):
		if r.character != null and not r.person_name in RD.retinue and not KD.is_prisoner(r.person_name) and mates.size() < 2:
			mates.append(r)
	if OS.get_environment("NO_MATES") == "1":
		mates.clear()
	for r in mates:
		r.character.role = CH.Role.SOLDADO
		r.character.wound_months = 0
		r.affection = 90
		RD.retinue.append(r.person_name)
	var front := []
	for t in MD.castles:
		if not front.is_empty():
			break
		if t.castle_id == GM.home_castle_id:
			continue
		for id in t.connected_castle_ids:
			var e = MD.get_castle_by_id(id)
			if e != null and e.kingdom != t.kingdom and e.castle_id != GM.home_castle_id and RD.get_relation(e.owner_name) != null and RD.get_relation(t.owner_name) != null:
				front = [t, e]
				break
	var target = front[0]
	var enemy = front[1]
	TD.location_id = target.castle_id
	var a = AD.create_army(enemy.owner_name, enemy.kingdom, 70, enemy.castle_id)
	a.origin_castle_id = enemy.castle_id
	a.current_castle_id = target.castle_id
	a.destination_castle_id = ""
	a.pending_battle = true
	target.garrison_size = 80
	var fight := {"type": "invited", "kind": "army", "army_id": a.army_id, "side": BattleEnums.Side.DEFENSOR,
		"lord": target.owner_name, "inviter": target.owner_name, "castle_id": target.castle_id}
	change_scene_to_file(CS.begin_event_fight(fight, "Llamada a filas"))
	await create_timer(1.0).timeout
	await _shot("ovf_council_%d" % mates.size())
	var scene = current_scene
	scene._close_council()
	await _shot("ovf_battle_%d" % mates.size())
	var side = scene.get_node("ScreenMargin/RootVBox/MainHBox/SidePanel")
	print("side min=", side.get_combined_minimum_size(), " main=", scene.get_node("ScreenMargin/RootVBox/MainHBox").get_combined_minimum_size(), " root=", scene.get_node("ScreenMargin").get_combined_minimum_size())
	for ch in scene.get_node("ScreenMargin/RootVBox/MainHBox").get_children():
		print("  ", ch.name, " ", ch.get_combined_minimum_size())
	for ch in side.get_children():
		print("    side ", ch.name, " ", ch.get_combined_minimum_size())
	# Cartel de resultado con mucho texto: debe caber (el texto se desplaza dentro).
	scene.result_title.text = "¡Victoria!"
	scene.result_label.text = "\n".join(Array(range(30)).map(func(i): return "Línea de resultado %d con un texto bastante largo para ocupar varias líneas en el cartel." % i))
	scene.result_overlay.visible = true
	await _shot("ovf_result")
	print("PANTALLAS CON DESBORDE: ", bad)
	quit()
