extends SceneTree
const OUT := "C:/Users/admin/AppData/Local/Temp/claude/c--otros/adc3634b-a099-4bb1-a246-6e7fe13b8a60/scratchpad/shots"

func _initialize() -> void:
	_run.call_deferred()

func _shot(n: String) -> void:
	await create_timer(0.9).timeout
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, n])

func _run() -> void:
	seed(3)
	DirAccess.make_dir_recursive_absolute(OUT)
	var GM = root.get_node("GameManager"); var MD = root.get_node("MapData"); var RD = root.get_node("RelationsData")
	var AD = root.get_node("AmbitionData"); var WE = root.get_node("WorldEvents")
	var CL = load("res://scripts/resources/character_loader.gd"); var CH = load("res://scripts/resources/character.gd")
	var p = CL.make_test_character("Sir Alaric", CH.Role.NOBLEZA_BAJA)
	GM.start_new_game(p, MD.castles[0].castle_id)
	await process_frame
	# Un señor de tu reino que conspira contra otro.
	var plotter: Relationship = null
	var victim := ""
	for l in RD.lords():
		if l.kingdom == GM.player_kingdom and l.character != null:
			for o in RD.lords():
				if o != l and o.kingdom == l.kingdom and not RD.castles_of(o.person_name).is_empty():
					plotter = l
					victim = o.person_name
	if plotter == null:
		plotter = Relationship.new()
		plotter.person_name = "Lord Ermengol de Valldaura"
		plotter.kind = Relationship.Kind.SENOR
		plotter.kingdom = GM.player_kingdom
		plotter.character = CL.make_test_character(plotter.person_name, CH.Role.NOBLEZA_ALTA)
		plotter.character.personality = CH.Personality.ASTUTO
		RD.relations.append(plotter)
		victim = MD.castles[0].owner_name if MD.castles[0].owner_name != p.full_name() else RD.lords()[0].person_name
	var a := {"id": "usurpar", "kind": "poder", "progress": 1.0, "rate": 0.1, "target": victim, "held": 0, "involve": true}
	AD.ambitions[plotter.person_name] = a
	GM.queue_event(AD._player_event(plotter, a))
	# Unas cuantas noticias entre PNJ para la crónica.
	for r in RD.courtiers().slice(0, 6):
		AD._npc_outcome(r, {"id": ["casarse", "fe", "rivalidad"].pick_random(), "target": ""})
	change_scene_to_file("res://scenes/map/map.tscn")
	await _shot("amb_01_conjura")
	var ids: Array[String] = []
	for c in MD.castles:
		ids.append(c.castle_id)
	load("res://scripts/ui/chronicle_panel.gd").open(current_scene, ids)
	await _shot("amb_02_cronica")
	quit()
