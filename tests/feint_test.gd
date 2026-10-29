extends SceneTree
# Finta: contra la guardia de contraataque, contra nadie, bloqueos de postura y uso por la IA.

var fails := 0

func check(c: bool, w: String) -> void:
	print(("  ok  " if c else "  FALLA ") + w)
	if not c:
		fails += 1

func _initialize() -> void:
	var DM = load("res://scripts/resources/duel_manager.gd")
	var AI = load("res://scripts/resources/duel_ai.gd")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var A = CombatEnums.ActionType
	var P = CombatEnums.Posture
	seed(5)

	# 1) Finta contra quien espera para parar.
	var d = DM.new()
	var a = CL.make_test_character("Atacante", CH.Role.CABALLERO)
	var b = CL.make_test_character("Defensor", CH.Role.CABALLERO)
	d.start_duel(a, b)
	d.set_posture(a, P.OFENSIVA)
	d.countering[b] = true
	var hp_before: int = b.current_health
	var st_before: int = a.current_stamina
	d._current_adv = ""
	var txt: String = d._do_feint(a, b)
	check(not d.countering[b], "la parada del rival se pierde")
	check(d.advantage.get(a, "") == d.ADV_ABIERTO, "queda la guardia abierta")
	check(b.current_health == hp_before, "la finta no hace daño cuando engaña")
	check(a.current_stamina == st_before - d.COST_FEINT, "cuesta %d de aliento" % d.COST_FEINT)
	print("    ", txt)
	# El siguiente ataque no se puede parar y hace +25%.
	var dmg_open := 0
	var dmg_plain := 0
	for i in 200:
		b.current_health = b.max_health
		d.countering[b] = true
		d._current_adv = d.ADV_ABIERTO
		var h0: int = b.current_health
		var r: String = d._do_attack(a, b)
		check(not r.contains("para el golpe"), "ataque tras finta no se puede parar") if i == 0 else null
		dmg_open += h0 - b.current_health
		b.current_health = b.max_health
		d._current_adv = ""
		d.countering[b] = false
		d.dodging[b] = false
		d.defending[b] = false
		h0 = b.current_health
		d._do_attack(a, b)
		dmg_plain += h0 - b.current_health
	var ratio: float = float(dmg_open) / maxf(1.0, dmg_plain)
	check(ratio > 1.12 and ratio < 1.4, "daño tras finta ≈ +25%% (×%.2f)" % ratio)

	# 2) Finta contra quien no espera: golpe flojo.
	d.advantage[a] = ""
	var weak := 0
	var normal := 0
	for i in 200:
		b.current_health = b.max_health
		d.countering[b] = false
		d.dodging[b] = false
		d.defending[b] = false
		d._current_adv = ""
		a.current_stamina = a.max_stamina
		var h1: int = b.current_health
		d._do_feint(a, b)
		weak += h1 - b.current_health
		b.current_health = b.max_health
		h1 = b.current_health
		d._do_attack(a, b)
		normal += h1 - b.current_health
	var wr: float = float(weak) / maxf(1.0, normal)
	check(wr > 0.35 and wr < 0.65, "sin guardia: golpe flojo ≈ −50%% (×%.2f)" % wr)
	check(d.advantage.get(a, "") != d.ADV_ABIERTO, "sin guardia no abre nada")

	# 3) Bloqueos de postura.
	check(CombatEnums.is_blocked(P.DESESPERADA, A.FINTA), "Desesperada bloquea la Finta")
	check(not CombatEnums.is_blocked(P.OFENSIVA, A.FINTA) and not CombatEnums.is_blocked(P.DEFENSIVA, A.FINTA) and not CombatEnums.is_blocked(P.ESGRIMA, A.FINTA), "Ofensiva, Defensiva y Esgrima la permiten")
	d.set_posture(a, P.DESESPERADA)
	check(not d.take_turn(a, A.FINTA), "en Desesperada no se puede fintar (no gasta turno)")

	# 4) La IA finta contra quien contraataca y respeta los bloqueos.
	var feints := 0
	var blocked_picks := 0
	for i in 400:
		var d2 = DM.new()
		var me = CL.make_test_character("IA", CH.Role.NOBLEZA_ALTA)
		var foe = CL.make_test_character("Jugador", CH.Role.CABALLERO)
		d2.start_duel(foe, me)
		d2.countering[foe] = true
		d2.last_actions[foe] = [A.CONTRAATACAR, A.CONTRAATACAR, A.ATACAR]
		var c: Dictionary = AI.choose(d2, me, foe)
		if c.action == A.FINTA:
			feints += 1
		if CombatEnums.is_blocked(c.posture, c.action):
			blocked_picks += 1
	print("    la IA finta en %d de 400 turnos contra un contraatacante" % feints)
	check(feints > 40, "la IA finta contra quien contraataca")
	check(blocked_picks == 0, "la IA nunca elige una acción bloqueada")
	var calm := 0
	for i in 400:
		var d3 = DM.new()
		var me3 = CL.make_test_character("IA", CH.Role.NOBLEZA_ALTA)
		var foe3 = CL.make_test_character("Jugador", CH.Role.CABALLERO)
		d3.start_duel(foe3, me3)
		if AI.choose(d3, me3, foe3).action == A.FINTA:
			calm += 1
	check(calm < feints / 3, "sin contraataque casi no finta (%d de 400)" % calm)
	check(DM.INTENT_TEXT.has(A.FINTA), "la lectura del rival puede anunciar «va a fintar»")
	print("FALLAS: ", fails)
	quit(fails)
