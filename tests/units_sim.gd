extends SceneTree
# Balance de batallas: atacante (jugado por la IA del bando del jugador) contra defensor.
# BMPATH elige el BattleManager (para comparar con la versión anterior).

const N := 200
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

func _sim(label: String, att: int, defn: int, walls: bool, a_cmd_fn: Callable, d_cmd_fn: Callable) -> void:
	var wins := 0
	var general_falls := 0
	var turns := 0
	var reasons := {}
	for i in N:
		var b = BM.new()
		b.player_side = BattleEnums.Side.ATACANTE
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
		if "general" in str(holder[1]):
			general_falls += 1
		turns += b.turn
		var key: String = str(holder[0]) + " " + str(holder[1]).left(38)
		reasons[key] = reasons.get(key, 0) + 1
	print("%-46s atacante gana %5.1f%% | por caída del general %4.1f%% | turnos %.1f" % [
		label, 100.0 * wins / N, 100.0 * general_falls / N, float(turns) / N])
	if OS.get_environment("REASONS") == "1":
		for k in reasons:
			print("      ", reasons[k], "  ", k)

func _run() -> void:
	var path := OS.get_environment("BMPATH")
	BM = load(path if not path.is_empty() else "res://scripts/resources/battle_manager.gd")
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	seed(42)
	var base := func(): return _cmd()
	_sim("asedio 135 vs 90", 135, 90, true, base, base)
	_sim("campo abierto 120 vs 100", 120, 100, false, base, base)
	_sim("campo abierto 100 vs 100", 100, 100, false, base, base)
	if not BM.new().has_method("general_of"):
		return
	var master := func():
		var c: Character = _cmd()
		c.mastery_xp = {"2": 400, "0": 200, "seeded": 1}   # caballería 6, infantería 4
		return c
	_sim("campo 100 vs 100, atacante con mando alto", 100, 100, false, master, base)
	var strat := func(): return _cmd(16)
	_sim("campo 100 vs 100, defensor Estrategia 16", 100, 100, false, base, strat)
	_sim("asedio 135 vs 90, defensor Estrategia 16", 135, 90, true, base, strat)
	quit()
