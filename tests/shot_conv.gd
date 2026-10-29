extends SceneTree
# Captura el panel de conversación sobre Relaciones: antes de elegir (args[0]) y tras la respuesta (args[1]).

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var c = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	c.charisma = 10
	root.get_node("GameManager").start_new_game(c, root.get_node("MapData").castles[0].castle_id)
	change_scene_to_file("res://scenes/relations/relations.tscn")
	await create_timer(0.8).timeout
	var RD = root.get_node("RelationsData")
	var rel = null
	for r in RD.people_in_area():
		if RD.romance_possible(r) and r.kind == 2:
			rel = r
			break
	if rel == null:
		rel = RD.people_in_area()[0]
	rel.affection = 62
	var panel = load("res://scripts/ui/conversation_panel.gd").open(current_scene, rel)
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png(args[0])
	panel._speak("franco")
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png(args[1])
	quit()
