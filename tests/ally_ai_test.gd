extends SceneTree
# IA aliada: errores solo en pelotones aliados, según el jefe; tus pelotones y el enemigo nunca.

var fails := 0

func check(c: bool, w: String) -> void:
	print(("  ok  " if c else "  FALLA ") + w)
	if not c:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _rate(b, u, n := 4000) -> float:
	var hits := 0
	for i in n:
		if b._ally_blunder(u):
			hits += 1
	return float(hits) / n

func _run() -> void:
	seed(5)
	var BM = load("res://scripts/resources/battle_manager.gd")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	for case in [[8, 8], [11, 11], [15, 15]]:
		var b = BM.new()
		b.player_side = BattleEnums.Side.ATACANTE
		b.player_leader = CL.make_test_character("Tú", CH.Role.CABALLERO)
		b.ally_soldiers = 100
		var host: Character = CL.make_test_character("Anfitrión", CH.Role.NOBLEZA_ALTA)
		host.leadership = case[0]
		host.strategy = case[1]
		b.start_battle(130, 120, false, host, CL.make_test_character("Enemigo", CH.Role.NOBLEZA_ALTA), "X")
		var own = null
		var ally = null
		var foe = null
		for u in b.units:
			if u.side == b.player_side and not u.ally and own == null:
				own = u
			elif u.side == b.player_side and u.ally and ally == null:
				ally = u
			elif u.side != b.player_side and foe == null:
				foe = u
		var skill: int = case[0] + case[1]
		var r_ally := _rate(b, ally)
		print("jefe aliado con Liderazgo+Estrategia %d: competencia %.2f, errores por decisión %.3f" % [skill, b.ally_competence(), r_ally])
		check(_rate(b, own) == 0.0, "tu pelotón nunca se equivoca (L+E %d)" % skill)
		check(_rate(b, foe) == 0.0, "el enemigo nunca se equivoca (L+E %d)" % skill)
		if skill >= b.ALLY_SKILL_FULL:
			check(r_ally == 0.0, "un jefe hábil (%d) juega como el enemigo" % skill)
		else:
			var expected: float = b.ALLY_MAX_BLUNDER * (1.0 - b.ally_competence())
			check(absf(r_ally - expected) < 0.03, "errores %.3f ≈ %.3f esperados" % [r_ally, expected])
	# Sin aliados (tu propio ejército): ninguna decisión pasa por la torpeza aliada.
	var solo = BM.new()
	solo.player_side = BattleEnums.Side.ATACANTE
	solo.player_leader = CL.make_test_character("Tú", CH.Role.NOBLEZA_ALTA)
	solo.start_battle(100, 100, false, solo.player_leader, CL.make_test_character("Enemigo", CH.Role.NOBLEZA_ALTA), "X")
	check(not solo.has_allies(), "batalla propia: no hay pelotones aliados")
	print("FALLAS: ", fails)
	quit(fails)
