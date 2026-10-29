extends SceneTree
# Pasa el ratón (simulado) por cada orden del duelo y mide cuánto se mueven los demás controles.

const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"

func _initialize() -> void:
	_run.call_deferred()

func _all(n: Node) -> Array:
	var out := [n]
	for ch in n.get_children():
		out.append_array(_all(ch))
	return out

func _snapshot(scene: Node) -> Dictionary:
	var d := {}
	for n in _all(scene):
		if n is Button or n is ProgressBar or (n is Label and n.name != "HintLabel"):
			if (n as Control).is_visible_in_tree():
				d[scene.get_path_to(n)] = (n as Control).get_global_rect()
	return d

func _run() -> void:
	var CS = root.get_node("CombatSetup")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	CS.clear()
	CS.player_character = CL.make_test_character("Sir Bartolomé de Valdemora", CH.Role.CABALLERO)
	CS.enemy_character = CL.make_test_character("Lord Hermann von Hohenstein", CH.Role.CABALLERO)
	change_scene_to_file("res://scenes/combat/combat.tscn")
	await create_timer(1.0).timeout
	var sc = current_scene
	# Estado de media pelea: ventaja activa, rival en guardia de contra, previsible y desequilibrado.
	var me = sc.player_character
	var foe = sc.enemy_character
	sc.duel.advantage[me] = DuelManager.ADV_CONTRA
	sc.duel.advantage[foe] = DuelManager.ADV_CONTRA
	sc.duel.countering[foe] = true
	sc.duel.unbalanced[me] = true
	if "attack_streak" in sc.duel:
		sc.duel.attack_streak[me] = 2
	var base := _snapshot(sc)
	var worst := 0.0
	var worst_name := ""
	var buttons: Array = _all(sc).filter(func(n): return n is Button and n.is_visible_in_tree())
	for b: Button in buttons:
		b.mouse_entered.emit()
		await process_frame
		await process_frame
		var snap := _snapshot(sc)
		for k in base:
			if snap.has(k):
				var mv: float = (snap[k].position - base[k].position).length() + absf(snap[k].size.y - base[k].size.y)
				if mv > worst:
					worst = mv
					worst_name = "%s al pasar por «%s» (hint: %d car.)" % [k, b.text, sc.hint_label.text.length()]
		b.mouse_exited.emit()
		await process_frame
		if b.text.begins_with("Atacar"):
			b.mouse_entered.emit()
			await create_timer(0.3).timeout
			root.get_texture().get_image().save_png("%s/duel_hover.png" % OUT)
			b.mouse_exited.emit()
	print("MAYOR DESPLAZAMIENTO: %.1f px — %s" % [worst, worst_name])
	quit()
