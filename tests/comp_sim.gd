extends SceneTree
# Batalla ajena (invitado): 0–3 compañeros propios y duelos entre jefes a mitad de batalla.
# Todos los pelotones del atacante los mueve la IA (competencia igual a la enemiga) para medir solo la estructura.

var N := 300
var BM
var CL
var CH

func _initialize() -> void:
	_run.call_deferred()

func _cmd(name: String, s: int = 8, l: int = 8) -> Character:
	var c: Character = CL.make_test_character(name, CH.Role.NOBLEZA_ALTA)
	c.strategy = s
	c.leadership = l
	return c

func _sim(label: String, companions: int, duels_on: bool) -> void:
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 42)
	var wins := 0
	var duel_count := 0
	var duel_att_wins := 0
	var levy_total := 0
	var reasons := {}
	var gen_comp := 0
	for i in N:
		var b = BM.new()
		b.player_side = BattleEnums.Side.ATACANTE
		if "ally_competence_override" in b:
			b.ally_competence_override = 1.0
		b.player_leader = _cmd("Tú")
		var comps: Array[Character] = []
		for k in companions:
			comps.append(_cmd("Compañero %d" % k))
		var levy: int = (int(OS.get_environment("LEVY")) if OS.get_environment("LEVY") != "" else 20) + (0 if OS.get_environment("FIXEDLEVY") == "1" else 8 * companions)   # 8 soldados por cada compañero
		levy_total += levy
		b.ally_soldiers = 100
		var holder := [-1]
		b.battle_ended.connect(func(w: int, r: Dictionary):
			holder[0] = w
			var key: String = str(w) + " " + str(r.reason).left(40)
			reasons[key] = reasons.get(key, 0) + 1)
		b.challenge_offered.connect(func(_c, _t): b.answer_challenge(false))
		var counter := [0, 0]
		b.log_message.connect(func(t: String):
			if t.begins_with("Duelo singular:"):
				counter[0] += 1)
		b.challenge_resolved.connect(func(t: String):
			if "Tu bando" in t or "tu bando" in t:
				counter[1] += 1)
		if not duels_on:
			b.set("AI_CHALLENGE_CHANCE", 0.0)
		b.start_battle(100 + levy, 120, false, _cmd("Anfitrión"), _cmd("Enemigo"), "X", comps)
		if b.general_of(BattleEnums.Side.ATACANTE) in comps or b.general_of(BattleEnums.Side.ATACANTE) == b.player_leader:
			gen_comp += 1
		for u in b.units:
			if u.side == BattleEnums.Side.ATACANTE:
				u.ally = true
		var guard := 0
		while not b.is_over and guard < 60:
			guard += 1
			if b.pending_retreat:
				b.answer_retreat(false)
			b.end_player_turn()
		if holder[0] == BattleEnums.Side.ATACANTE:
			wins += 1
		duel_count += counter[0]
		duel_att_wins += counter[1]
	print("%-38s atacante gana %5.1f%% | leva media %d | duelos por batalla %.2f | general propio %d" % [label, 100.0 * wins / N, levy_total / N, float(duel_count) / N, gen_comp])
	for k in reasons:
		print("      ", reasons[k], "  ", k)

func _run() -> void:
	BM = load(OS.get_environment("BMPATH") if OS.get_environment("BMPATH") != "" else "res://scripts/resources/battle_manager.gd")
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	if OS.get_environment("N") != "":
		N = int(OS.get_environment("N"))
	for k in 4:
		_sim("invitado con %d compañeros" % k, k, true)
	quit()
