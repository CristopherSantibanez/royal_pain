extends SceneTree
# Duelo v3: posturas que bloquean acciones (gestor, IA, interfaz), leer al rival (Estrategia),
# experiencia por fuente y tipo de luchador, entrenamiento, contenido nuevo y guardado.

var DM
var CE
var AI
var CL
var CH
var XR
var GD
var fails := 0
var passes := 0

func _initialize() -> void:
	_run.call_deferred()

func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("FALLA ", label)

func _knight(n: String) -> Character:
	var c: Character = CL.make_test_character(n, CH.Role.CABALLERO)
	c.combat = 8
	c.defense = 6
	c.strategy = 5
	c.general_skills.clear()
	c.combat_skills.clear()
	c.battle_skills.clear()
	c.advantages.clear()
	c.disadvantages.clear()
	c.equipment.clear()
	return c

func _skill(name: String) -> Skill:
	for list in [GD.general_skills, GD.combat_skills, GD.battle_skills]:
		for s: Skill in list:
			if s.skill_name == name:
				return s
	return null

func _trait(name: String) -> CharacterTrait:
	for list in [GD.advantages, GD.disadvantages]:
		for t: CharacterTrait in list:
			if t.trait_name == name:
				return t
	return null

func _item(name: String) -> Equipment:
	for e: Equipment in GD.equipment_catalog:
		if e.equipment_name == name:
			return e
	return null

func _run() -> void:
	DM = load("res://scripts/resources/duel_manager.gd")
	CE = load("res://scripts/resources/combat_enums.gd")
	AI = load("res://scripts/resources/duel_ai.gd")
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	XR = load("res://scripts/resources/xp_rules.gd")
	GD = root.get_node("GameData")
	seed(11)
	_blocks()
	_ai()
	_reading()
	_xp()
	_content()
	await _ui()
	await _embedded()
	_training()
	_save()
	print("duel3_test: %d ok, %d fallos" % [passes, fails])
	print("RESULTADO: %d FALLAS" % fails)
	quit()

func _blocks() -> void:
	print("[bloqueos por postura]")
	var expected := {
		CE.Posture.OFENSIVA: [CE.ActionType.DEFENDER, CE.ActionType.ESQUIVAR],
		CE.Posture.DEFENSIVA: [CE.ActionType.EMPUJAR],
		CE.Posture.ESGRIMA: [CE.ActionType.EMPUJAR],
		CE.Posture.MURO: [CE.ActionType.EMPUJAR],   # obsoleta: igual que Defensiva
		CE.Posture.DESESPERADA: [CE.ActionType.DEFENDER, CE.ActionType.ESQUIVAR, CE.ActionType.DESARMAR, CE.ActionType.CONTRAATACAR, CE.ActionType.FINTA],
	}
	for p in expected:
		for a in CE.ActionType.values():
			var should: bool = a in expected[p]
			check(CE.is_blocked(p, a) == should, "%s/%s bloqueada=%s" % [CE.posture_name(p), CE.action_name(a), should])
		check(not CE.is_blocked(p, CE.ActionType.RENDIRSE) and not CE.is_blocked(p, CE.ActionType.RETIRARSE), "%s deja rendirse y huir" % CE.posture_name(p))
	var a := _knight("A")
	var b := _knight("B")
	var d = DM.new()
	d.start_duel(a, b)
	d.set_posture(a, CE.Posture.OFENSIVA)
	var stamina := a.current_stamina
	check(d.take_turn(a, CE.ActionType.DEFENDER) == false, "el gestor rechaza Defender en Ofensiva")
	check(not d.defending[a] and a.current_stamina == stamina and d.last_actions[a].is_empty(), "rechazar no gasta el turno")
	check(d.take_turn(a, CE.ActionType.ATACAR) == true, "Atacar en Ofensiva sí")
	check(not CE.block_reason(CE.Posture.DEFENSIVA, CE.ActionType.EMPUJAR).is_empty(), "hay motivo para la interfaz")
	# Esgrima desarma mejor.
	d.set_posture(b, CE.Posture.DEFENSIVA)
	var base: float = d.disarm_chance(b, a)
	d.set_posture(b, CE.Posture.ESGRIMA)
	check(is_equal_approx(d.disarm_chance(b, a), minf(0.9, base + DM.ESGRIMA_DISARM_BONUS)), "Esgrima: +10 puntos al desarmar")

func _ai() -> void:
	print("[IA]")
	var blocked := 0
	var total := 0
	var postures := {}
	for personality in CH.Personality.values():
		for i in 120:
			var me := _knight("IA")
			me.personality = personality
			var foe := _knight("Rival")
			var d = DM.new()
			d.start_duel(me, foe)
			for t in 12:
				if d.is_over:
					break
				var choice: Dictionary = AI.choose(d, me, foe)
				total += 1
				postures[choice.posture] = postures.get(choice.posture, 0) + 1
				if CE.is_blocked(choice.posture, choice.action):
					blocked += 1
				d.set_posture(me, choice.posture)
				d.take_turn(me, choice.action)
				if d.is_over:
					break
				var fc: Dictionary = AI.choose(d, foe, me)
				d.set_posture(foe, fc.posture)
				d.take_turn(foe, fc.action)
	check(blocked == 0, "la IA nunca elige una acción bloqueada (%d de %d)" % [blocked, total])
	check(postures.size() == 4 and not postures.has(CE.Posture.MURO), "la IA usa las 4 posturas (%s)" % str(postures))
	# Desarmado y en Desesperada: no puede atacar ni desarmar → debe elegir algo válido.
	var me2 := _knight("Arrinconado")
	me2.personality = CH.Personality.VALIENTE
	me2.current_health = 5
	var foe2 := _knight("Rival")
	var d2 = DM.new()
	d2.start_duel(me2, foe2)
	d2.statuses[me2].append(CE.Status.DESARMADO)
	me2.current_stamina = 5
	var ok := true
	for i in 50:
		var c: Dictionary = AI.choose(d2, me2, foe2)
		if CE.is_blocked(c.posture, c.action):
			ok = false
	check(ok, "IA desarmada y sin aliento: siempre una acción válida")

func _reading() -> void:
	print("[leer al rival]")
	var a := _knight("Lector")
	var b := _knight("Rival")
	var d = DM.new()
	d.start_duel(a, b)
	check(is_equal_approx(d.read_chance(a, b), DM.READ_BASE), "misma Estrategia: probabilidad base")
	a.strategy = 10
	var hi: float = d.read_chance(a, b)
	check(is_equal_approx(hi, DM.READ_BASE + 5 * DM.READ_PER_POINT), "más Estrategia, más lectura (%.2f)" % hi)
	a.strategy = 20
	b.strategy = 1
	check(is_equal_approx(d.read_chance(a, b), DM.READ_MAX), "tope de lectura")
	a.strategy = 1
	b.strategy = 15
	check(d.read_chance(a, b) == 0.0, "sin Estrategia no se lee a un estratega")
	a.strategy = 5
	b.strategy = 5
	a.combat_skills.append(_skill("Lectura del Rival"))
	check(is_equal_approx(d.read_chance(a, b), DM.READ_BASE + 0.15), "Lectura del Rival +15 puntos")
	b.combat_skills.append(_skill("Rostro de Piedra"))
	check(is_equal_approx(d.read_chance(a, b), DM.READ_BASE + 0.15 - 0.2), "Rostro de Piedra −20 puntos")
	b.combat_skills.clear()
	b.disadvantages.append(_trait("Previsible"))
	check(is_equal_approx(d.read_chance(a, b), DM.READ_BASE + 0.15 + 0.15), "Previsible: se te lee más")
	var text: String = DM.intent_text({"posture": CE.Posture.OFENSIVA, "action": CE.ActionType.DESARMAR})
	check(text == "Parece que va a desarmarte (postura Ofensiva).", "texto del aviso: %s" % text)
	# Frecuencia simulada de avisos según Estrategia.
	for pair in [[5, 5], [10, 5], [15, 5]]:
		var r := _knight("R")
		var e := _knight("E")
		r.strategy = pair[0]
		e.strategy = pair[1]
		var dd = DM.new()
		dd.start_duel(r, e)
		var hits := 0
		for i in 2000:
			if randf() < dd.read_chance(r, e):
				hits += 1
		print("  Estrategia %d vs %d: avisos en %.0f%% de los turnos" % [pair[0], pair[1], hits / 20.0])

func _xp() -> void:
	print("[experiencia]")
	var expect := {
		CharacterEnums.FighterType.DUELISTA: [XR.SOURCE_DUEL, 1.3],
		CharacterEnums.FighterType.ESTRATEGA: [XR.SOURCE_STUDY, 1.35],
		CharacterEnums.FighterType.TANQUE: [XR.SOURCE_TRAINING, 1.25],
		CharacterEnums.FighterType.BERSERKER: [XR.SOURCE_STUDY, 0.75],
		CharacterEnums.FighterType.DEFENSOR: [XR.SOURCE_BATTLE, 1.2],
		CharacterEnums.FighterType.ASESINO: [XR.SOURCE_MISSION, 1.2],
	}
	for ft in expect:
		var c := _knight("X")
		c.fighter_type = ft
		c.gain_xp(50, expect[ft][0])
		check(c.last_xp_gained == roundi(50 * expect[ft][1]) and c.xp == c.last_xp_gained, "%s en %s: ×%.2f (%d)" % [
			CharacterEnums.fighter_type_name(ft), expect[ft][0], expect[ft][1], c.last_xp_gained])
	var plain := _knight("Sin fuente")
	plain.fighter_type = CharacterEnums.FighterType.DUELISTA
	plain.gain_xp(50)
	check(plain.xp == 50, "sin fuente no hay multiplicador (compatible)")
	var dis := _knight("Disciplinado")
	dis.fighter_type = CharacterEnums.FighterType.ASESINO
	dis.advantages.append(_trait("Disciplinado"))
	dis.gain_xp(40, XR.SOURCE_TRAINING)
	check(dis.last_xp_gained == 50, "Disciplinado: +25%% al entrenar (%d)" % dis.last_xp_gained)
	var lv := _knight("Nivel")
	lv.fighter_type = CharacterEnums.FighterType.DUELISTA
	check(lv.gain_xp(100, XR.SOURCE_DUEL) == 1 and lv.level == 2 and lv.xp == 30, "el multiplicador sube de nivel (nivel %d, xp %d)" % [lv.level, lv.xp])
	check(not XR.affinity_text(CharacterEnums.FighterType.ESTRATEGA).is_empty(), "texto de afinidad para la ficha")

func _content() -> void:
	print("[contenido nuevo]")
	for n in ["Lectura del Rival", "Rostro de Piedra", "Maestro de Esgrima", "Muro de Acero", "Furia Desatada"]:
		check(_skill(n) != null, "habilidad %s" % n)
	for n in ["Disciplinado", "Instinto de Duelista", "Mente Analítica", "Previsible", "Impaciente"]:
		check(_trait(n) != null, "rasgo %s" % n)
	for n in ["Estoque de Duelo", "Hacha de Berserker", "Pavés", "Capa Sombría", "Manual de Esgrima"]:
		check(_item(n) != null, "equipo %s" % n)
	var a := _knight("A")
	var b := _knight("B")
	var d = DM.new()
	d.start_duel(a, b)
	d.set_posture(a, CE.Posture.DESESPERADA)
	var before: Vector2i = d.preview_damage(a, b)
	a.combat_skills.append(_skill("Furia Desatada"))
	var after: Vector2i = d.preview_damage(a, b)
	check(after.y > before.y, "Furia Desatada en Desesperada: más daño (%d → %d)" % [before.y, after.y])
	d.set_posture(a, CE.Posture.OFENSIVA)
	var off_with: Vector2i = d.preview_damage(a, b)
	a.combat_skills.clear()
	check(d.preview_damage(a, b) == off_with, "Furia Desatada no cuenta fuera de Desesperada")
	# Muro de Acero: Defender en Muro reduce más el golpe.
	var hits := {false: 0, true: 0}
	for with_skill in [false, true]:
		for i in 400:
			var x := _knight("X")
			var y := _knight("Y")
			if with_skill:
				x.combat_skills.append(_skill("Muro de Acero"))
			var dm = DM.new()
			dm.start_duel(x, y)
			dm.set_posture(x, CE.Posture.DEFENSIVA)
			dm.take_turn(x, CE.ActionType.DEFENDER)
			dm.set_posture(y, CE.Posture.OFENSIVA)
			var hp := x.current_health
			dm.take_turn(y, CE.ActionType.ATACAR)
			hits[with_skill] += hp - x.current_health
	check(hits[true] < hits[false], "Muro de Acero: menos daño defendiendo en Muro (%d vs %d)" % [hits[true], hits[false]])
	# Maestro de Esgrima.
	d.set_posture(a, CE.Posture.ESGRIMA)
	var dc: float = d.disarm_chance(a, b)
	a.combat_skills.append(_skill("Maestro de Esgrima"))
	check(d.disarm_chance(a, b) > dc, "Maestro de Esgrima desarma mejor en Esgrima")

func _ui() -> void:
	print("[interfaz]")
	var CS = root.get_node("CombatSetup")
	CS.clear()
	CS.player_character = _knight("Jugador")
	CS.enemy_character = _knight("Enemigo")
	CS.player_character.strategy = 20
	CS.enemy_character.strategy = 1
	change_scene_to_file("res://scenes/combat/combat.tscn")
	await create_timer(0.6).timeout
	var scene = current_scene
	if not scene.player_turn:
		await create_timer(2.0).timeout
	scene._player_posture(CE.Posture.DESESPERADA)
	var disabled := {}
	for b: Button in scene._action_buttons:
		disabled[b.get_meta("action")] = b.disabled
	check(disabled[CE.ActionType.DEFENDER] and disabled[CE.ActionType.DESARMAR] and disabled[CE.ActionType.CONTRAATACAR] and disabled[CE.ActionType.FINTA], "Desesperada apaga 4 botones")
	check(not disabled[CE.ActionType.ATACAR] and not disabled[CE.ActionType.EMPUJAR] and not disabled[-1], "Atacar/Empujar/Abandonar siguen")
	var btn: Button = scene._action_buttons.filter(func(b): return b.get_meta("action") == CE.ActionType.DEFENDER)[0]
	check("✖" in btn.tooltip_text, "la ayuda explica el bloqueo")
	scene._player_posture(CE.Posture.DEFENSIVA)
	check(not btn.disabled, "al cambiar de postura se reactiva")
	# Tecla de una acción bloqueada: no gasta el turno.
	scene._player_posture(CE.Posture.OFENSIVA)
	scene._player_action(CE.ActionType.ESQUIVAR)
	check(scene.player_turn and "Ofensiva" in scene.hint_label.text, "acción bloqueada por teclado: aviso sin gastar turno")
	# Lectura: con Estrategia 20 vs 1 la mayoría de turnos hay aviso.
	var reads := 0
	var turns := 0
	for t in 8:
		if scene.duel.is_over:
			break
		if scene.player_turn:
			turns += 1
			if not scene._enemy_intent.is_empty():
				reads += 1
				var intent: Dictionary = scene._enemy_intent
				var enemy: Character = scene.enemy_character
				scene._player_posture(CE.Posture.DEFENSIVA)
				await scene._player_action(CE.ActionType.DEFENDER)
				if scene.duel.is_over:
					break
				var last: Array = scene.duel.last_actions[enemy]
				check(last.back() == intent.action or CE.Status.DESARMADO in scene.duel.statuses[enemy], "el rival cumple la jugada adivinada")
				continue
			scene._player_posture(CE.Posture.DEFENSIVA)
			await scene._player_action(CE.ActionType.DEFENDER)
		else:
			await create_timer(1.5).timeout
	print("  avisos en %d de %d turnos (Estrategia 20 vs 1)" % [reads, turns])
	check(reads > 0, "aparecen avisos de lectura")

func _embedded() -> void:
	print("[duelo singular en batalla]")
	var fighter := _knight("Capitán")
	fighter.fighter_type = CharacterEnums.FighterType.DUELISTA
	var foe := _knight("Jefe enemigo")
	var scene = load("res://scenes/combat/combat.tscn").instantiate()
	scene.player_character = fighter
	scene.enemy_character = foe
	scene.embedded = true
	root.add_child(scene)
	await create_timer(0.5).timeout
	var xp_before := fighter.xp
	foe.current_health = 1
	var guard := 0
	while not scene.duel.is_over and guard < 20:
		if scene.player_turn:
			scene._player_posture(CE.Posture.OFENSIVA)
			scene._player_action(CE.ActionType.ATACAR)
		await create_timer(1.4).timeout
		guard += 1
	check(scene.duel.is_over, "el duelo singular termina")
	var won: bool = scene._embedded_winner == fighter
	var expected: int = roundi((XR.BATTLE_DUEL_WIN if won else XR.BATTLE_DUEL_LOSS) * 1.3)
	check(fighter.xp - xp_before == expected or fighter.level > 1, "experiencia del duelo singular (%d, esperado %d)" % [fighter.xp - xp_before, expected])
	scene.queue_free()

func _training() -> void:
	print("[entrenar]")
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var player: Character = CL.make_test_character("Sir Entreno", CH.Role.SOLDADO)
	player.fighter_type = CharacterEnums.FighterType.TANQUE
	player.gold = 500
	GM.start_new_game(player, MD.castles[0].castle_id)
	var CI = load("res://scenes/castle_interior/castle_interior.gd")
	var ci = CI.new()
	ci.character = player
	var action: Dictionary = ci._entrenar_action()
	check(action.unavailable.is_empty() and "Entrenar" in action.label, "acción «Entrenar» disponible (%s)" % action.label)
	print("  ", action.tooltip)
	ci.free()
	# La lógica se prueba directamente (sin la escena del castillo).
	var sessions := 0
	for i in 3:
		if player.last_training_month == GM.months_elapsed() and player.training_sessions_month >= XR.TRAINING_PER_MONTH:
			break
		player.training_sessions_month = (player.training_sessions_month if player.last_training_month == GM.months_elapsed() else 0) + 1
		player.last_training_month = GM.months_elapsed()
		player.gain_xp(XR.TRAINING, XR.SOURCE_TRAINING)
		sessions += 1
	check(sessions == XR.TRAINING_PER_MONTH, "tope de %d sesiones al mes" % XR.TRAINING_PER_MONTH)
	check(player.last_xp_gained == roundi(XR.TRAINING * 1.25), "Tanque entrena ×1,25 (%d)" % player.last_xp_gained)
	var ci2 = CI.new()
	ci2.character = player
	check(not ci2._entrenar_unavailable_reason().is_empty(), "tras el tope, «Entrenar» no está disponible")
	ci2.free()

func _save() -> void:
	print("[guardado]")
	var DC = load("res://scripts/resources/data_codec.gd")
	var c := _knight("Guardado")
	c.training_sessions_month = 2
	c.last_training_month = 7
	c.combat_skills.append(_skill("Lectura del Rival"))
	c.equipment.append(_item("Manual de Esgrima"))
	var back = DC.decode(JSON.parse_string(JSON.stringify(DC.encode(c))))
	check(back != null and back.training_sessions_month == 2 and back.last_training_month == 7, "se guardan las sesiones de entrenamiento")
	check(back != null and back.combat_skills.any(func(s): return s.skill_name == "Lectura del Rival"), "se guarda la habilidad nueva")
	check(back != null and is_equal_approx(SkillEffects.fx(back, "read"), 0.15 + 0.08), "sus efectos siguen tras cargar")
	var old := {}
	var enc: Dictionary = DC.encode(_knight("Viejo"))
	for k in enc:
		old[k] = enc[k]
	if old.has("training_sessions_month"):
		old.erase("training_sessions_month")
	var old_back = DC.decode(old)
	check(old_back != null and old_back.training_sessions_month == 0, "partidas antiguas: 0 sesiones")
