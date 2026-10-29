extends SceneTree
func _initialize() -> void:
	for p in ["res://scenes/battle/battle.gd", "res://scenes/combat/combat.gd", "res://scripts/ui/prisoners_panel.gd", "res://scenes/relations/relations.gd", "res://scenes/castle_interior/castle_interior.gd", "res://scenes/map/map.gd", "res://scripts/resources/battle_manager.gd", "res://scripts/resources/dialogue_catalog.gd"]:
		var s = load(p)
		print(p, " ok=", s != null and s.can_instantiate())
	quit()
