extends SceneTree
func _initialize() -> void:
	for p in ["res://scripts/resources/duel_manager.gd", "res://scripts/resources/duel_ai.gd", "res://scenes/combat/combat.gd",
			"res://scripts/autoload/combat_setup.gd", "res://scripts/resources/battle_manager.gd", "res://scenes/battle/battle.gd",
			"res://scenes/battle/battle_board.gd", "res://scripts/resources/battle_unit.gd", "res://scripts/resources/battle_enums.gd", "res://scenes/tutorial/tutorial.gd"]:
		var s = load(p)
		print(p, " -> ", "OK" if s != null and s.can_instantiate() else "FAIL")
	quit()
