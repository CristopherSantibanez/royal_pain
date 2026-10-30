extends SceneTree
# Duelo simplificado: 4 posturas, 7 acciones (Guardia une Defender+Esquivar, Abandonar pregunta).

var fails := 0
func check(c: bool, w: String) -> void:
	print(("  ok  " if c else "  FALLA ") + w)
	if not c: fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _knight(n: String) -> Character:
	var CL = load("res://scripts/resources/character_loader.gd")
	var c: Character = CL.make_test_character(n, Character.Role.CABALLERO)
	c.combat = 10
	c.defense = 10
	return c

func _run() -> void:
	var P := CombatEnums.Posture
	var A := CombatEnums.ActionType
	# Bloqueos
	check(CombatEnums.is_blocked(P.OFENSIVA, A.DEFENDER), "Ofensiva bloquea la Guardia")
	check(CombatEnums.is_blocked(P.DEFENSIVA, A.EMPUJAR) and CombatEnums.is_blocked(P.ESGRIMA, A.EMPUJAR), "Defensiva y Esgrima bloquean Empujar")
	var desp: Array = CombatEnums.allowed_actions(P.DESESPERADA).filter(func(a): return a in CombatEnums.ACTIONS_SHOWN)
	check(desp == [A.ATACAR, A.EMPUJAR, A.RENDIRSE, A.RETIRARSE], "Desesperada: solo Atacar, Empujar y Abandonar (%s)" % [desp])
	check(CombatEnums.canon_posture(P.MURO) == P.DEFENSIVA and CombatEnums.canon_action(A.ESQUIVAR) == A.DEFENDER, "Muro/Esquivar se tratan como Defensiva/Guardia")

	# Guardia: reduce y a veces evita; Esgrima evita más.
	var d := DuelManager.new()
	var a := _knight("Atacante")
	var b := _knight("Defensor")
	d.start_duel(a, b)
	d.set_posture(b, P.MURO)
	check(d.posture[b] == P.DEFENSIVA, "elegir Muro (partida antigua) deja Defensiva")
	d.set_posture(b, P.DEFENSIVA)
	var dd := d.guard_dodge_chance(a, b)
	d.set_posture(b, P.ESGRIMA)
	var de := d.guard_dodge_chance(a, b)
	check(de > dd and dd > 0.0, "la Guardia esquiva más en Esgrima (%.2f) que en Defensiva (%.2f)" % [de, dd])
	var dodged := 0
	var reduced := 0
	for i in 400:
		var x := _knight("X")
		var y := _knight("Y")
		var m := DuelManager.new()
		m.start_duel(x, y)
		m.set_posture(x, P.OFENSIVA)
		m.set_posture(y, P.ESGRIMA)
		m.take_turn(y, A.ESQUIVAR)   # acción antigua: debe actuar como Guardia
		var hp := y.current_health
		m.take_turn(x, A.ATACAR)
		if y.current_health == hp:
			dodged += 1
		else:
			reduced += 1
	check(dodged > 80 and reduced > 80, "Guardia (vía Esquivar antiguo): %d esquivas y %d golpes reducidos de 400" % [dodged, reduced])

	# La IA nunca usa acciones ni posturas ocultas.
	var hidden := 0
	for i in 600:
		var x := _knight("IA")
		x.personality = Character.Personality.values()[i % Character.Personality.size()]
		var y := _knight("Rival")
		var m := DuelManager.new()
		m.start_duel(x, y)
		x.current_health = [100, 30, 10][i % 3]
		var ch: Dictionary = DuelAI.choose(m, x, y)
		if ch.posture == P.MURO or ch.action == A.ESQUIVAR or CombatEnums.is_blocked(ch.posture, ch.action):
			hidden += 1
	check(hidden == 0, "la IA no elige Muro, Esquivar ni acciones bloqueadas (%d)" % hidden)

	# Pantalla: 4 posturas + 7 acciones; Abandonar pregunta.
	var CS = root.get_node("CombatSetup")
	CS.clear()
	CS.player_character = _knight("Jugador")
	CS.enemy_character = _knight("Enemigo")
	change_scene_to_file("res://scenes/combat/combat.tscn")
	await create_timer(0.8).timeout
	var sc = current_scene
	check(sc._posture_buttons.size() == 4 and sc._action_buttons.size() == 7, "11 botones: %d posturas, %d acciones" % [sc._posture_buttons.size(), sc._action_buttons.size()])
	sc.player_turn = true
	sc._on_action_pressed(sc.ACTION_ABANDON)
	await process_frame
	var dlg_found := sc.get_children().any(func(n): return n is ConfirmationDialog)
	check(dlg_found and not sc.duel.is_over, "Abandonar abre la pregunta sin terminar el duelo")
	print("FALLAS: ", fails)
	quit(fails)
