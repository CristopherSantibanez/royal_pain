extends SceneTree
# Balance de batallas: atacante (jugado por la IA del bando del jugador) contra defensor.
# BMPATH elige el BattleManager (para comparar con la versión anterior).

var N := 200
var ONLY := ""
var BM
var CL
var CH

func _initialize() -> void:
	_run.call_deferred()

func _cmd(strategy: int = 8, leadership: int = 8) -> Character:
	var c: Character = CL.make_test_character("Cmd", CH.Role.NOBLEZA_ALTA)
	c.leadership = leadership
	c.strategy = strategy
	return c

func _sim(label: String, att: int, defn: int, walls: bool, a_cmd_fn: Callable, d_cmd_fn: Callable, ally_c: float = -2.0) -> void:
	if not ONLY.is_empty() and not label.begins_with(ONLY):
		return
	var draws := 0
	var diffs: Array = []
	var wins := 0
	var general_falls := 0
	var turns := 0
	var reasons := {}
	var blunders := 0
	# Cada escenario arranca de la misma semilla: las parejas (con y sin torpeza) se comparan con el mismo azar.
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 42)
	for i in N:
		var b = BM.new()
		b.player_side = BattleEnums.Side.ATACANTE
		# Competencia aliada: por defecto igual que el enemigo (ALLYC=1), para medir el equilibrio simétrico.
		if "ally_competence_override" in b:
			var env_c: String = OS.get_environment("ALLYC")
			b.ally_competence_override = ally_c if ally_c > -2.0 else (float(env_c) if env_c != "" else 1.0)
		var holder := [-1, ""]
		b.battle_ended.connect(func(w: int, r: Dictionary):
			holder[0] = w
			holder[1] = r.reason)
		if b.has_signal("challenge_offered"):
			b.challenge_offered.connect(func(_c, _t): b.answer_challenge(false))
		b.start_battle(att, defn, walls, a_cmd_fn.call(), d_cmd_fn.call(), "X")
		for u in b.units:
			if u.side == BattleEnums.Side.ATACANTE:
				u.ally = true   # la IA aliada mueve el bando atacante
		var guard := 0
		while not b.is_over and guard < 60:
			guard += 1
			if "pending_retreat" in b and b.pending_retreat:
				b.answer_retreat(false)
			b.end_player_turn()
		if holder[0] == BattleEnums.Side.ATACANTE:
			wins += 1
		elif holder[0] != BattleEnums.Side.DEFENSOR:
			draws += 1
		if "general" in str(holder[1]):
			general_falls += 1
		turns += b.turn
		if "ally_blunders" in b:
			blunders += b.ally_blunders
		if "noche" in str(holder[1]) or "tablas" in str(holder[1]).to_lower():
			var d: float = b._strength_ratio(BattleEnums.Side.ATACANTE) - b._strength_ratio(BattleEnums.Side.DEFENSOR)
			diffs.append(d)
		var key: String = str(holder[0]) + " " + str(holder[1]).left(38)
		reasons[key] = reasons.get(key, 0) + 1
	print("%-46s atacante gana %5.1f%% | tablas %4.1f%% | por caída del general %4.1f%% | turnos %.1f | errores aliados %.1f" % [
		label, 100.0 * wins / N, 100.0 * draws / N, 100.0 * general_falls / N, float(turns) / N, float(blunders) / N])
	if not diffs.is_empty():
		diffs.sort()
		var q := func(f: float): return diffs[clampi(int(f * diffs.size()), 0, diffs.size() - 1)]
		print("      al caer la noche (%d): diferencia de fuerza A−D  p10 %.2f  p25 %.2f  p50 %.2f  p75 %.2f  p90 %.2f" % [diffs.size(), q.call(0.1), q.call(0.25), q.call(0.5), q.call(0.75), q.call(0.9)])
	if OS.get_environment("REASONS") == "1":
		for k in reasons:
			print("      ", reasons[k], "  ", k)

func _run() -> void:
	var path := OS.get_environment("BMPATH")
	BM = load(path if not path.is_empty() else "res://scripts/resources/battle_manager.gd")
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 42)
	if OS.get_environment("N") != "":
		N = int(OS.get_environment("N"))
	ONLY = OS.get_environment("ONLY")
	var base := func(): return _cmd()
	_sim("asedio 135 vs 90", 135, 90, true, base, base)
	_sim("campo abierto 120 vs 100", 120, 100, false, base, base)
	_sim("campo abierto 100 vs 100", 100, 100, false, base, base)
	if not BM.new().has_method("general_of"):
		return
	var master := func():
		var c: Character = _cmd()
		var mf: String = OS.get_environment("MFAM") if OS.get_environment("MFAM") != "" else "2"
		c.mastery_xp = {mf: int(OS.get_environment("MXP")) if OS.get_environment("MXP") != "" else 600, "seeded": 1}   # una familia a nivel 6
		return c
	_sim("campo 100 vs 100, atacante con mando alto", 100, 100, false, master, base)
	var strat := func(): return _cmd(16)
	_sim("campo 100 vs 100, defensor Estrategia 16", 100, 100, false, base, strat)
	_sim("asedio 135 vs 90, defensor Estrategia 16", 135, 90, true, base, strat)
	# IA aliada: el bando atacante lo mueve la IA aliada de tu anfitrión.
	var avg := func(): return _cmd(8, 8)      # Liderazgo + Estrategia 16
	var good := func(): return _cmd(15, 15)   # 30: por encima de ALLY_SKILL_FULL
	_sim("aliado medio, igual que el enemigo (campo)", 100, 100, false, avg, base, 1.0)
	_sim("aliado medio, competencia real (campo)", 100, 100, false, avg, base, -1.0)
	_sim("aliado hábil, igual que el enemigo (campo)", 100, 100, false, good, base, 1.0)
	_sim("aliado hábil, competencia real (campo)", 100, 100, false, good, base, -1.0)
	var mid := func(): return _cmd(11, 11)    # 22: a medio camino
	_sim("aliado intermedio, competencia real (campo)", 100, 100, false, mid, base, -1.0)
	_sim("aliado intermedio, igual que el enemigo (campo)", 100, 100, false, mid, base, 1.0)
	_sim("aliado medio, igual que el enemigo (asedio)", 135, 90, true, avg, base, 1.0)
	_sim("aliado medio, competencia real (asedio)", 135, 90, true, avg, base, -1.0)
	_sim("aliado hábil, competencia real (asedio)", 135, 90, true, good, base, -1.0)
	quit()
