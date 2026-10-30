extends SceneTree
# Simula batallas tácticas con BattleManager real.
# El bando del jugador se controla con: "ai" (la propia IA de BattleManager), "wait" (solo pasar turno),
# "archers_only" (solo atacan los arqueros si tienen blanco; nadie se mueve).

const N := 400
var BM
var BE
var CL
var CH
var KAI

func _initialize() -> void:
	_run.call_deferred()

func _cmd(l: int = 5, s: int = 5, skill: String = "") -> Character:
	var c: Character = CL.make_test_character("Cmd", CH.Role.NOBLEZA_ALTA)
	c.leadership = l
	c.strategy = s
	if skill != "":
		var sk = load("res://scripts/resources/skill.gd").new()
		sk.skill_name = skill
		c.battle_skills.append(sk)
	return c

func one(att: int, defn: int, player_side: int, strat: String, acmd: Character, dcmd: Character) -> Dictionary:
	var b = BM.new()
	b.player_side = player_side
	b.start_battle(att, defn, true, acmd, dcmd, "X")
	var guard := 0
	while not b.is_over and guard < 50:
		guard += 1
		match strat:
			"ai":
				b._run_ai(player_side)
			"wait":
				pass
			"archers_only":
				for u in b.active_units(player_side):
					if u.type == BE.UnitType.ARQUEROS:
						var ts = b.targets_in_range(u)
						if not ts.is_empty():
							b.attack(u, b._ai_best_target(u, ts))
		if b.is_over: break
		b.end_player_turn()
	var att_won: bool = b.active_units(BE.Side.DEFENSOR).is_empty() and not b.active_units(BE.Side.ATACANTE).is_empty()
	return {"att_won": att_won, "turns": b.turn, "att_left": b.total_soldiers(BE.Side.ATACANTE), "def_left": b.total_soldiers(BE.Side.DEFENSOR)}

func sim(att: int, defn: int, player_side: int, strat: String, acmd: Character, dcmd: Character) -> String:
	var aw := 0
	var turns := 0.0
	var timeouts := 0
	var al := 0.0
	var dl := 0.0
	for i in range(N):
		var r := one(att, defn, player_side, strat, acmd, dcmd)
		if r.att_won: aw += 1
		turns += r.turns
		if r.turns > 12: timeouts += 1
		al += r.att_left
		dl += r.def_left
	return "att %d vs def %d | attacker win %.0f%% | avg turns %.1f | timeouts(12) %.0f%% | att left %.0f | def left %.0f" % [
		att, defn, 100.0 * aw / N, turns / N, 100.0 * timeouts / N, al / N, dl / N]

func auto(att: int, defn: int) -> String:
	var aw := 0
	for i in range(4000):
		if KAI.auto_resolve(att, defn).attacker_won: aw += 1
	return "auto_resolve att %d vs def %d: attacker win %.0f%%" % [att, defn, 100.0 * aw / 4000]

func _run() -> void:
	BM = load("res://scripts/resources/battle_manager.gd")
	BE = load("res://scripts/resources/battle_enums.gd")
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	KAI = load("res://scripts/resources/kingdom_ai.gd")
	seed(777)
	var c := _cmd()
	var A: int = BE.Side.ATACANTE
	var D: int = BE.Side.DEFENSOR
	print("=== Player ATTACKS (player uses BattleManager AI), defender AI waits behind walls ===")
	for pair in [[27, 90], [40, 90], [60, 90], [90, 90], [120, 90], [135, 90], [180, 90], [60, 20], [30, 20], [120, 150], [120, 200]]:
		print(sim(pair[0], pair[1], A, "ai", c, c))
	print("=== Player ATTACKS, archers-only (no movement) ===")
	for pair in [[60, 90], [120, 90]]:
		print(sim(pair[0], pair[1], A, "archers_only", c, c))
	print("=== Player DEFENDS: uses AI vs just waiting ===")
	for pair in [[36, 90], [60, 90], [90, 90], [120, 90], [150, 90]]:
		print("ai   ", sim(pair[0], pair[1], D, "ai", c, c))
		print("wait ", sim(pair[0], pair[1], D, "wait", c, c))
		print("     ", auto(pair[0], pair[1]))
	print("=== auto_resolve reference ===")
	for pair in [[27, 90], [60, 90], [120, 90], [135, 90], [150, 90], [36, 20], [24, 20]]:
		print(auto(pair[0], pair[1]))
	print("=== Commander quality (attacker 120 vs 90) ===")
	print("L5S5   ", sim(120, 90, A, "ai", _cmd(5, 5), c))
	print("L15S15 ", sim(120, 90, A, "ai", _cmd(15, 15), c))
	print("Carga Letal ", sim(120, 90, A, "ai", _cmd(5, 5, "Carga Letal"), c))
	print("Grito de Guerra ", sim(120, 90, A, "ai", _cmd(5, 5, "Grito de Guerra"), c))
	print("Def Tactica Defensiva ", sim(120, 90, A, "ai", c, _cmd(5, 5, "Táctica Defensiva")))
	quit()
