extends SceneTree
# Prueba del tutorial y el glosario: carga ambas escenas, juega lecciones y captura pantallas.
# Uso: --script t_test.gd -- <carpeta_capturas> (sin carpeta: no captura)

var out := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else ""
	_run.call_deferred()

func _shot(name: String) -> void:
	if out.is_empty():
		return
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])

func _run() -> void:
	change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	await create_timer(0.8).timeout
	await _shot("t_menu")

	change_scene_to_file("res://scenes/tutorial/tutorial.tscn")
	await create_timer(0.6).timeout
	var tut = current_scene
	# Lecciones del combate RPG: la tabla y un combate de prueba incrustado (la IA juega por ti).
	var RS = load("res://scenes/rpg_battle/rpg_battle.gd")
	RS.test_auto = true
	RS.test_delay = 0.0
	for lesson in [0, 1, 2]:
		tut.start_lesson(lesson)
		for s in tut._steps().size():
			await create_timer(0.3).timeout
			var step: Dictionary = tut._steps()[tut._step]
			if step.get("demo", "") == "fight":
				tut.arena.find_children("*", "Button", true, false)[0].pressed.emit()
				await create_timer(0.3).timeout
				if lesson == 0:
					await _shot("t_tutorial_rpg")
				var sc = tut._rpg_layer.get_child(0)
				var t := 0.0
				while not sc._ended and t < 30.0:
					await create_timer(0.1).timeout
					t += 0.1
				sc._on_back_pressed()
				await create_timer(0.2).timeout
			elif lesson == 1:
				await _shot("t_tutorial_table")
			print("R%d paso %d -> %s" % [lesson + 1, tut._step + 1, tut.result_label.text if tut.result_panel.visible else "(sin resultado)"])
			if tut._step + 1 < tut._steps().size():
				tut._on_next()
	RS.test_auto = false
	# Batallas
	for lesson in [3, 4]:
		tut.start_lesson(lesson)
		for s in tut._steps().size():
			await create_timer(0.3).timeout
			var btn: Button = tut.arena.find_children("*", "Button", true, false)[0]
			btn.pressed.emit()
			await create_timer(0.6).timeout
			print("B%d paso %d -> %s" % [lesson + 1, tut._step + 1, tut.result_label.text.replace("\n", " | ")])
			if lesson == 3 and s == 0:
				await _shot("t_tutorial_battle")
			if tut._step + 1 < tut._steps().size():
				tut._on_next()

	load("res://scripts/resources/glossary_data.gd").open(self, "res://scenes/main_menu/main_menu.tscn", "Duelo")
	await create_timer(0.8).timeout
	await _shot("t_glossary")
	var g = current_scene
	g.search_edit.text = "parada"
	g._on_search("parada")
	await create_timer(0.3).timeout
	print("Glosario búsqueda «parada»: ", g.category_title.text)
	g._show_category("Habilidades")
	await create_timer(0.2).timeout
	print("Habilidades: %d entradas" % g.entries_box.get_child_count())
	await _shot("t_glossary_skills")
	quit()
