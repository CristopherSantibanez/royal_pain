extends SceneTree
# Fase 3: árboles de habilidades (luchador, personalidad, alineamiento): estructura, costes, efectos
# implementados, básicos, puntos por nivel, puntos raros y aprendizaje automático de los PNJ.

var fails := 0

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _char(ft: int, p: int, al: int, lvl: int) -> Character:
	var c := Character.new()
	c.first_name = "S%d" % randi()
	c.fighter_type = ft
	c.personality = p
	c.alignment = al
	c.level = lvl
	for k in ["combat", "defense", "strategy", "leadership", "charisma"]:
		c.set(k, 6)
	return c

func _run() -> void:
	var S := SkillTreeCatalog
	var src: String = FileAccess.get_file_as_string("res://scripts/resources/rpg_battle_manager.gd") \
		+ FileAccess.get_file_as_string("res://scripts/resources/rpg_stats.gd")
	print("[estructura]")
	var ids: Array = S.tree_ids()
	check(ids.size() == 24, "24 árboles (%d)" % ids.size())
	var bad := []
	var total := 0
	for tid: String in ids:
		var t: Dictionary = S.tree(tid)
		var n_nodes: int = S.nodes_of_tree(tid).size()
		total += n_nodes
		if t.is_empty() or t.branches.size() != 3 or n_nodes < 10 or n_nodes > 15:
			bad.append(tid)
			continue
		for b in 3:
			var basics: Array = S.basic_nodes(tid, b)
			if basics.size() < 1 or not basics.all(func(id: String) -> bool: return S.node(id).tier == 1):
				bad.append("%s/%d" % [tid, b])
	check(bad.is_empty(), "3 ramas, 10–15 nodos y básicos por rama %s" % [bad])
	check(total >= 280 and total <= 330, "≈300 nodos (%d)" % total)
	print("[nodos]")
	var bad_req := []
	var bad_fx := []
	var known_keys := ["crit", "acc", "pierce", "exec", "scale_missing", "vs_status", "per_ally", "cover", "advance",
		"cleanse", "revive", "pt_drain", "morale", "self_st", "agi", "estr", "haste", "pt_give"]
	for n: Dictionary in S.all_nodes():
		if n.tree == S.TREE_BOSS:
			continue
		var cost_ok: bool = int(n.cost) == [0, 1, 1, 2, 3][n.tier]
		var req_ok: bool = n.tier == 1 or (n.req.size() + n.req_any.size() > 0)
		for r in n.req + n.req_any:
			var rn := S.node(r)
			req_ok = req_ok and not rn.is_empty() and rn.tree == n.tree and rn.tier < n.tier
		if not (cost_ok and req_ok):
			bad_req.append(n.id)
		var fx: Dictionary = n.get("fx", {})
		var ok := true
		for k in fx:
			var key: String = k
			if n.kind == "act":
				ok = ok and key in known_keys
			elif key.begins_with("dmg_t"):
				ok = ok and src.contains("\"dmg_t%d\"")
			else:
				ok = ok and (src.contains("\"%s\"" % key))
		for st in n.get("st", []) + fx.get("self_st", []):
			ok = ok and RpgBattleManager.STATUS_NAMES.has(st[0])
		if n.kind == "act":
			ok = ok and (float(n.pow) > 0 or not n.get("st", []).is_empty() or n.has("heal") or not fx.is_empty())
		else:
			ok = ok and not fx.is_empty()
		if not ok:
			bad_fx.append(n.id)
	check(bad_req.is_empty(), "costes 1/1/2/3 y requisitos válidos %s" % [bad_req])
	check(bad_fx.is_empty(), "cada nodo tiene un efecto implementado %s" % [bad_fx])
	check(S.node("due_brecha").fx.get("brecha", 0) > 0 and S.node("ase_brecha").tier == 3
		and S.node("ber_furia").tree == "berserker" and S.node("due_guardia").tree == "duelista"
		and S.node("tan_muro").tree == "tanque" and S.node("def_muro").tree == "defensor", "brecha, Furia, Guardia de esgrima y Muro de escudos en su sitio")
	check(S.node("com_grito").id == "plea_animo" and not S.node("com_proy2").is_empty() and not S.node("ene_virote").is_empty(), "ids antiguos y de enemigos se resuelven")
	print("[API]")
	var P := Character.Personality
	var A := CharacterEnums.Alignment
	var F := CharacterEnums.FighterType
	var c := _char(F.TANQUE, P.ASTUTO, A.TIRANO, 1)
	check(Array(S.trees_for(c)) == ["tanque", "p_astuto", "a_tirano"], "trees_for: luchador, personalidad, alineamiento")
	check(S.points_for_level(1) == 0 and S.points_for_level(3) == 1 and S.points_for_level(20) == 6, "points_for_level: 1 cada 3 niveles")
	check(S.points_free(c) == 0, "nivel 1: sin puntos")
	var b0: Array = S.basic_nodes("p_astuto", 0)
	check(S.cost_for(c, b0[0]) == 0 and S.learn(c, b0[0]), "primer básico de la rama gratis")
	check(not S.can_learn(c, b0[1]), "segundo básico de la misma rama cuesta 1 punto")
	check(not S.can_learn(c, "due_estocada"), "no aprende fuera de sus árboles")
	check(S.grant_points(c, 1, "maestro:x") and not S.grant_points(c, 1, "maestro:x") and not S.grant_points(c, 1, "nivel"), "grant_points: una vez por motivo; los de nivel van solos")
	check(S.points_free(c) == 1 and S.learn(c, b0[1]) and S.points_free(c) == 0, "un punto raro compra el segundo básico")
	c.level = 6
	var t2: String = S.tree("p_astuto").branches[0].nodes[2]
	check(S.learn(c, t2) and S.points_free(c) == 1, "escalón 2 con un punto (nivel 6 → 2 puntos)")
	var t3: String = S.tree("p_astuto").branches[0].nodes[3]
	check(not S.can_learn(c, t3), "escalón 3 cuesta 2")
	c.level = 9
	check(S.learn(c, t3) and S.points_free(c) == 0, "escalón 3 a nivel 9")
	print("[PNJ]")
	var npc := _char(F.ESTRATEGA, P.PIADOSO, A.PACIFISTA, 12)
	S.auto_learn(npc)
	var basics_ok := true
	for tid: String in S.trees_for(npc):
		for b in 3:
			basics_ok = basics_ok and S.basic_nodes(tid, b).any(func(id: String) -> bool: return S.knows(npc, id))
	check(basics_ok and S.points_free(npc) == 0, "auto_learn: un básico por rama y gasta los puntos (%d nodos)" % S.known_ids(npc).size())
	check(S.available_techniques(npc).size() >= 4 and not S.passive_fx(npc).is_empty(), "auto_learn deja técnicas y pasivas")
	var old := _char(F.BERSERKER, P.CRUEL, A.CONQUISTADOR, 4)
	old.learned_skills.append("com_grito")
	S.ensure_kit(old)
	check("plea_animo" in old.learned_skills and S.knows(old, "ber_furia") and S.points_spent(old) == 0, "ensure_kit: ids antiguos y kit base gratis")
	print("FALLAS: %d" % fails if fails else "TODO OK")
	quit()
