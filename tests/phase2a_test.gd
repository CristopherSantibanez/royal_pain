extends SceneTree
# Fase 2A: varios cónyuges (tope por rango), amantes y herederos de segunda línea, migración del
# cónyuge antiguo, lealtad (causas, aviso antes de traición, traición) y acciones con presos/siervos.

var fails := 0

func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok  ", what)
	else:
		fails += 1
		print("  FALLA ", what)

func _initialize() -> void:
	_run.call_deferred()

func _free_courtier(RD, gender: int, exclude: Array):
	for r in RD.relations:
		if RD.sociable(r) and r.character != null and r.character.gender == gender and not r.person_name in exclude \
				and r.kind != r.Kind.CONYUGE and RD.presence_blocker(r).is_empty():
			return r
	return null

func _run() -> void:
	seed(7)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var DD = root.get_node("DynastyData")
	var LD = root.get_node("LoyaltyData")
	var KD = root.get_node("CaptureData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var player = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	player.gold = 5000
	player.honor = 70
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame
	GM.pending_event = {}
	var fem: int = 1 - player.gender if player.gender <= 1 else 0
	fem = CharacterEnums.Gender.FEMENINO

	print("[tope de cónyuges por rango]")
	check(RD.max_spouses(player) == RD.WIVES_BASE, "Caballero: 1")
	var used: Array = []
	var a = _free_courtier(RD, fem, used); used.append(a.person_name)
	a.romance = true; a.affection = 95
	GM.actions_remaining = 20
	var t := ""
	for i in 30:
		t = RD.propose_love(a)
		if a.kind == a.Kind.CONYUGE:
			break
		a.affection = 95; a.last_courted_month = -1
	check(RD.is_married() and RD.spouse_name == a.person_name and RD.spouses.size() == 1, "primera boda: " + t.left(40))
	var b = _free_courtier(RD, fem, used); used.append(b.person_name)
	b.romance = true; b.affection = 95
	check(not RD.can_propose_love(b).is_empty(), "Caballero no puede segunda boda: " + RD.can_propose_love(b))
	player.role = CH.Role.NOBLEZA_BAJA
	check(RD.max_spouses(player) == RD.WIVES_NOBLE and RD.can_propose_love(b).is_empty(), "Nobleza Baja: 2")
	for i in 30:
		RD.propose_love(b)
		if b.kind == b.Kind.CONYUGE:
			break
		b.affection = 95
		GM.actions_remaining = 20
	check(RD.spouses.size() == 2 and RD.spouse_name == a.person_name, "dos cónyuges, el principal sigue")
	var c = _free_courtier(RD, fem, used); used.append(c.person_name)
	c.romance = true; c.affection = 95
	check(not RD.can_propose_love(c).is_empty(), "tercera bloqueada en Nobleza")
	player.role = CH.Role.DUQUE
	check(RD.max_spouses(player) == RD.WIVES_DUKE and RD.can_propose_love(c).is_empty(), "Duque: 3")
	player.role = CH.Role.NOBLEZA_BAJA

	print("[amantes y herederos de segunda línea]")
	var lover = c
	lover.affection = 10
	check(not RD.can_take_concubine(lover).is_empty(), "amante requiere intimidad")
	lover.affection = 80
	RD.take_concubine(lover)
	check(RD.is_concubine(lover.person_name) and RD.spouses.size() == 2, "amante no cuenta para el tope")
	var natural = DD._add_child(player, lover, true)
	natural.age = 20
	check(DD.adult_children() == [natural], "sin legítimos adultos hereda el bastardo")
	var legit = DD._add_child(player, a, false)
	legit.age = 5
	check(DD.adult_children() == [natural], "legítimo menor: sigue el bastardo")
	legit.age = 18
	check(DD.adult_children() == [legit], "legítimo adulto pasa delante")

	print("[viudez por cónyuge]")
	RD.on_character_died(a.person_name, "fiebres")
	check(RD.spouses.size() == 1 and RD.spouse_name == b.person_name, "muere la principal: la siguiente ocupa su lugar")

	print("[migración del cónyuge antiguo]")
	var saved_name: String = RD.spouse_name
	RD.spouses.clear()
	RD.load_state({})
	check(RD.spouses.size() == 1 and RD.spouses[0].name == saved_name, "spouse_name antiguo pasa a la lista")
	RD.load_state(RD.save_state())
	check(RD.spouses.size() == 1, "guardado ida y vuelta")

	print("[lealtad: causas]")
	var m = _free_courtier(RD, CharacterEnums.Gender.MASCULINO, used)
	used.append(m.person_name)
	RD.retinue.append(m.person_name)
	m.character.personality = CH.Personality.VALIENTE
	LD.loyalty[m.person_name] = 50
	LD.note(m.person_name, "paid"); check(LD.loyalty_of(m.person_name) == 51, "paga +1")
	LD.note(m.person_name, "unpaid"); check(LD.loyalty_of(m.person_name) == 43, "sin paga −8")
	LD.note(m.person_name, "victory"); check(LD.loyalty_of(m.person_name) == 47, "victoria +4")
	LD.note(m.person_name, "defeat"); check(LD.loyalty_of(m.person_name) == 42, "derrota −5")
	LD.note(m.person_name, "gift"); check(LD.loyalty_of(m.person_name) == 47, "regalo +5")
	m.character.personality = CH.Personality.HONORABLE
	LD.note(m.person_name, "dishonor"); check(LD.loyalty_of(m.person_name) == 37, "honorable: deshonra ×2")
	m.character.personality = CH.Personality.CRUEL
	LD.on_mistreatment(-1); check(LD.loyalty_of(m.person_name) == 37, "cruel tolera la crueldad")
	m.character.personality = CH.Personality.LEAL
	LD.note(m.person_name, "unpaid"); check(LD.loyalty_of(m.person_name) == 33, "leal: cambia despacio")
	m.character.personality = CH.Personality.AMBICIOSO
	LD.note(m.person_name, "unpaid"); check(LD.loyalty_of(m.person_name) == 20, "ambicioso: cambia deprisa")
	check(m.person_name in LD.dependents() and LD.vassals().is_empty(), "séquito es dependiente")

	print("[aviso antes de la traición]")
	m.character.personality = CH.Personality.VALIENTE
	m.affection = 0
	LD.loyalty[m.person_name] = 5
	GM.pending_event = {}
	GM.event_queue.clear()
	var gold_before: int = player.gold
	LD._warnings_and_betrayals([m.person_name])
	check(LD.is_warned(m.person_name) and m.person_name in RD.retinue, "primero llega el aviso, sin traición")
	check(str(GM.pending_event.get("id", "")) == "lealtad_aviso", "evento de aviso en cola")
	LD._warnings_and_betrayals([m.person_name])
	check(m.person_name in RD.retinue, "no traiciona el mismo mes del aviso")
	LD.warned[m.person_name] = GM.months_elapsed() - LD.WARN_MIN_MONTHS
	var betrayed := false
	for i in 40:
		LD.loyalty[m.person_name] = 5
		if not LD.is_warned(m.person_name):
			LD.warned[m.person_name] = GM.months_elapsed() - LD.WARN_MIN_MONTHS
		LD._warnings_and_betrayals([m.person_name])
		if not m.person_name in RD.retinue or player.gold < gold_before:
			betrayed = true
			break
	check(betrayed, "con lealtad baja tras el aviso llega la traición (oro %d -> %d)" % [gold_before, player.gold])
	# remedio: pagar
	var k = _free_courtier(RD, CharacterEnums.Gender.MASCULINO, used)
	used.append(k.person_name)
	RD.retinue.append(k.person_name)
	LD.loyalty[k.person_name] = 25
	var ev: Dictionary = LD.warning_event(k.person_name)
	GM.pending_event = ev
	GM.resolve_pending_event(1)
	check(LD.loyalty_of(k.person_name) > 25, "remedio Pagar sube la lealtad: %d" % LD.loyalty_of(k.person_name))
	LD.month_tick()
	check(LD.loyalty.has(k.person_name), "tick mensual sin errores")
	LD.load_state(LD.save_state())
	check(LD.loyalty.has(k.person_name), "guardado de lealtad")

	print("[presos y siervos]")
	var p_rel = _free_courtier(RD, CharacterEnums.Gender.MASCULINO, used)
	used.append(p_rel.person_name)
	KD.capture(p_rel.character, player, true)
	var p = KD._find(p_rel.person_name)
	check(p != null, "preso capturado")
	GM.actions_remaining = 20
	var it: String = KD.interrogate(p)
	check(p.interrogated and not KD.interrogate_blocker(p).is_empty(), "interrogar (una vez): " + it.left(50))
	var ev2: Dictionary = KD.captive_event(p, "plea")
	check(ev2.options.size() == 2, "evento súplica")
	GM.pending_event = KD.captive_event(p, "escape")
	GM.resolve_pending_event(1)
	check(KD._find(p_rel.person_name) == null, "fuga: dejarle ir lo libera")
	KD.capture(p_rel.character, player, true)
	p = KD._find(p_rel.person_name)
	KD.enslave(p)
	check(KD.is_serf(p_rel.person_name), "esclavizado")
	check(KD.assign_work(p_rel.person_name, "campo").contains("Campo"), "asignar trabajo")
	var home = MD.get_castle_by_id(GM.home_castle_id)
	var food: int = home.food
	KD._work_month(p_rel.person_name)
	check(home.food == food + KD.WORK_FIELD_FOOD, "trabajo de campo da comida")
	var xp: int = p_rel.character.xp + p_rel.character.level * 1000
	var tr: String = KD.train_serf(p_rel.person_name)
	check(p_rel.character.xp + p_rel.character.level * 1000 > xp and not KD.train_blocker(p_rel.person_name).is_empty(), "adiestrar: " + tr.left(40))
	KD.load_state(KD.save_state())
	check(KD.serf_work.get(p_rel.person_name, "") == "campo", "guardado de trabajos")

	print("FALLA total: %d" % fails if fails > 0 else "TODO OK")
	quit()
