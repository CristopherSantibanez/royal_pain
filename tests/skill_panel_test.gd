extends SceneTree
# Panel del árbol de habilidades: abre para jugador y PNJ, 3 árboles × 3 ramas, aprender gasta puntos, bloqueados no.

var fails := 0

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _char(lvl: int) -> Character:
	var c := Character.new()
	c.first_name = "S%d" % randi()
	c.fighter_type = 1
	c.personality = 2
	c.alignment = 0
	c.level = lvl
	return c

func _cols(panel: Control, tab: int) -> Array:
	var page: Control = panel._tabs.get_child(tab)
	return page.get_child(0).get_node("Ramas").get_children()

func _run() -> void:
	var S := SkillTreeCatalog
	var Panel = load("res://scripts/ui/skill_tree_panel.gd")
	var CL = load("res://scripts/resources/character_loader.gd")
	var player: Character = CL.make_test_character("Jugador", Character.Role.CABALLERO)
	player.level = 10
	var npc := _char(9)
	for c: Character in [player, npc]:
		var p: Control = Panel.open(root, c)
		await process_frame
		check(p._tabs.get_tab_count() == 3, "3 pestañas")
		var ok := true
		for t in 3:
			var cols := _cols(p, t)
			ok = ok and cols.size() == 3 and cols.all(func(col: Node) -> bool: return col.get_child_count() >= 4)
		check(ok, "3 árboles × 3 ramas con nodos")
		p.queue_free()
		await process_frame

	var p2: Control = Panel.open(root, npc)
	await process_frame
	S.grant_points(npc, 5, "prueba")
	var t0: String = S.trees_for(npc)[0]
	S.learn(npc, S.basic_nodes(t0, 0)[0])   # básico gratis: abre los de pago
	p2._rebuild()
	var free0: int = S.points_free(npc)
	var paid := ""
	var locked := ""
	for t: String in S.trees_for(npc):
		for nd: Dictionary in S.nodes_of_tree(t):
			var id: String = nd.id
			if paid == "" and S.can_learn(npc, id) and S.cost_for(npc, id) > 0:
				paid = id
			if locked == "" and not S.can_learn(npc, id) and not S.knows(npc, id):
				locked = id
	check(paid != "" and locked != "", "hay nodo de pago (%s) y bloqueado (%s)" % [paid, locked])
	var cost: int = S.cost_for(npc, paid)
	p2.request_learn(paid)
	check(p2._confirm_row.visible, "pide confirmación")
	check(p2.confirm_learn(), "aprende al confirmar")
	check(S.knows(npc, paid) and S.points_free(npc) == free0 - cost, "gasta %d punto(s)" % cost)
	check(p2.node_state(paid) == "aprendida" and p2._points.text.ends_with(str(free0 - cost)), "estado y cabecera actualizados")
	var before := npc.learned_skills.size()
	p2.request_learn(locked)
	check(not p2._confirm_row.visible and not p2.confirm_learn() and npc.learned_skills.size() == before, "bloqueado se rechaza")
	p2.queue_free()
	await process_frame
	print("FALLOS: ", fails)
	quit(1 if fails > 0 else 0)
