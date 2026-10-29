extends SceneTree
func _initialize() -> void:
	for p in ["res://scenes/battle/battle.gd", "res://scenes/battle/battle_board.gd", "res://scenes/combat/combat.gd", "res://scripts/autoload/army_data.gd", "res://scripts/autoload/combat_setup.gd", "res://scripts/resources/event_catalog.gd", "res://scripts/resources/invitation_catalog.gd"]:
		print(p, " ", load(p) != null)
	quit()
