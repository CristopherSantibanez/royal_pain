extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# --- Duelo ---
	var combat: Control = load("res://scenes/combat/combat.tscn").instantiate()
	root.add_child(combat)
	await process_frame
	var events := []
	combat.duel.combat_event.connect(func(k, a, t, n): events.append(k))
	var actions := [CombatEnums.ActionType.ATACAR, CombatEnums.ActionType.DEFENDER, CombatEnums.ActionType.ESQUIVAR,
		CombatEnums.ActionType.CONTRAATACAR, CombatEnums.ActionType.DESARMAR, CombatEnums.ActionType.EMPUJAR]
	var i := 0
	while not combat.duel.is_over and i < 6:
		combat._player_action(actions[i % actions.size()])
		await create_timer(1.5).timeout
		i += 1
	await create_timer(1.0).timeout
	print("DUEL over=", combat.duel.is_over, " turns=", i, " events=", events)
	print("time_scale=", Engine.time_scale, " children=", combat.get_child_count())
	combat.queue_free()

	# --- Batalla ---
	var board = load("res://scenes/battle/battle_board.gd").new()
	root.add_child(board)
	var bm := BattleManager.new()
	var counts := {"attack": 0, "rout": 0}
	bm.unit_attacked.connect(func(a, t, c, k, r): counts.attack += 1)
	bm.unit_routed.connect(func(u, ann): counts.rout += 1)
	board.setup(bm)
	bm.start_battle(120, 80, true, null, null, "Prueba")
	var t := 0
	while not bm.is_over and t < 30:
		bm.end_player_turn()
		print("turn ", t, " queued fx=", board._fx.size(), " remaining=%.2f" % board.fx_remaining())
		await create_timer(board.fx_remaining() + 0.1).timeout
		t += 1
	print("BATTLE over=", bm.is_over, " counts=", counts, " fx left=", board._fx.size())
	quit()
