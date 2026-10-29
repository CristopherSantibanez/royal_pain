extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var combat: Control = load("res://scenes/combat/combat.tscn").instantiate()
	root.add_child(combat)
	await create_timer(0.5).timeout
	combat._on_combat_event("hit", combat.player_character, combat.enemy_character, 7)
	await create_timer(0.15).timeout
	combat._on_combat_event("crit", combat.enemy_character, combat.player_character, 18)
	await create_timer(1.2).timeout
	combat.queue_free()
	var board = load("res://scenes/battle/battle_board.gd").new()
	board.position = Vector2(40, 40)
	root.add_child(board)
	var bm := BattleManager.new()
	board.setup(bm)
	bm.start_battle(120, 80, true, null, null, "Prueba")
	for i in 3:
		bm.end_player_turn()
	await create_timer(3.0).timeout
	quit()
