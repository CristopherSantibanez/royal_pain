extends SceneTree
# Simula duelos con DuelManager real. Jugador (A) usa una estrategia fija; el enemigo (B)
# replica la IA de combat.gd::_enemy_turn. Mide turnos, % victorias, vida final del ganador.

const N := 1000
const CAP := 400   # medio-turnos máximos

var CE
var DM
var CL
var CH

func _initialize() -> void:
	_run.call_deferred()

func _mk(combat: int, defense: int, skill: String = "") -> Character:
	var c: Character = CL.make_test_character("X", CH.Role.CABALLERO)
	c.combat = combat
	c.defense = defense
	if skill != "":
		var s = load("res://scripts/resources/skill.gd").new()
		s.skill_name = skill
		c.combat_skills.append(s)
	return c

func _enemy_ai(d, e: Character) -> void:
	var p: int = CE.Posture.OFENSIVA
	if CE.Status.HERIDO in d.statuses[e]:
		p = CE.Posture.DEFENSIVA
	d.set_posture(e, p)
	var act: int = CE.ActionType.ATACAR
	if CE.Status.HERIDO in d.statuses[e] and randf() < 0.5:
		act = CE.ActionType.DEFENDER
	d.take_turn(e, act)

# strategy: [posture, action-picker callable(d, me, foe, turn) -> action]
func _player(d, me: Character, foe: Character, strat: String, t: int) -> void:
	var p: int = CE.Posture.OFENSIVA
	var a: int = CE.ActionType.ATACAR
	match strat:
		"ofensiva_atacar": pass
		"defensiva_atacar": p = CE.Posture.DEFENSIVA
		"esgrima_atacar": p = CE.Posture.ESGRIMA
		"muro_atacar": p = CE.Posture.MURO
		"desesperada_atacar": p = CE.Posture.DESESPERADA
		"muro_contra_atacar":
			p = CE.Posture.MURO
			a = CE.ActionType.CONTRAATACAR if t % 2 == 0 else CE.ActionType.ATACAR
		"muro_contraatacar_siempre":
			p = CE.Posture.MURO
			a = CE.ActionType.CONTRAATACAR
		"ofensiva_desarmar_atacar":
			a = CE.ActionType.DESARMAR if not (CE.Status.DESARMADO in d.statuses[foe]) else CE.ActionType.ATACAR
		"muro_desarmar_atacar":
			p = CE.Posture.MURO
			a = CE.ActionType.DESARMAR if not (CE.Status.DESARMADO in d.statuses[foe]) else CE.ActionType.ATACAR
		"ofensiva_esquivar_atacar":
			a = CE.ActionType.ESQUIVAR if t % 2 == 0 else CE.ActionType.ATACAR
		"ofensiva_defender_atacar":
			a = CE.ActionType.DEFENDER if t % 2 == 0 else CE.ActionType.ATACAR
		"ofensiva_empujar_atacar":
			a = CE.ActionType.EMPUJAR if t % 2 == 0 else CE.ActionType.ATACAR
	d.set_posture(me, p)
	d.take_turn(me, a)

func sim(strat: String, ac: int, ad: int, bc: int, bd: int, askill := "", bskill := "") -> Dictionary:
	var wins := 0; var losses := 0; var unfinished := 0
	var turns: Array = []
	var hp_left_win: Array = []
	var wounded_after_win := 0
	for i in range(N):
		var a := _mk(ac, ad, askill)
		var b := _mk(bc, bd, bskill)
		var d = DM.new()
		d.start_duel(a, b)
		var t := 0
		while not d.is_over and t < CAP:
			_player(d, a, b, strat, t)
			t += 1
			if d.is_over: break
			_enemy_ai(d, b)
			t += 1
		if not d.is_over:
			unfinished += 1
			continue
		turns.append(t)
		if a.is_alive() and not b.is_alive():
			wins += 1
			hp_left_win.append(a.current_health)
			if a.current_health < 30: wounded_after_win += 1
		else:
			losses += 1
	turns.sort()
	var med = turns[turns.size() / 2] if turns.size() > 0 else -1
	var p10 = turns[int(turns.size() * 0.1)] if turns.size() > 0 else -1
	var p90 = turns[int(turns.size() * 0.9)] if turns.size() > 0 else -1
	var avg_hp := 0.0
	for h in hp_left_win: avg_hp += h
	avg_hp = avg_hp / max(1, hp_left_win.size())
	return {"win%": 100.0 * wins / N, "unfinished": unfinished, "halfturns_p10/med/p90": "%d/%d/%d" % [p10, med, p90],
		"player_actions_med": int(med / 2.0 + 0.5), "winner_hp_avg": snappedf(avg_hp, 0.1),
		"win_but_wounded%": snappedf(100.0 * wounded_after_win / max(1, wins), 0.1)}

func _run() -> void:
	CE = load("res://scripts/resources/combat_enums.gd")
	DM = load("res://scripts/resources/duel_manager.gd")
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	seed(12345)
	var strats := ["ofensiva_atacar", "defensiva_atacar", "esgrima_atacar", "muro_atacar", "desesperada_atacar",
		"muro_contra_atacar", "muro_contraatacar_siempre", "ofensiva_desarmar_atacar", "muro_desarmar_atacar",
		"ofensiva_esquivar_atacar", "ofensiva_defender_atacar", "ofensiva_empujar_atacar"]
	print("=== Test char 7/5 vs 7/5 (make_test_character) ===")
	for s in strats:
		print(s, " ", sim(s, 7, 5, 7, 5))
	print("=== Typical created char 10/8 vs 10/8 ===")
	for s in ["ofensiva_atacar", "muro_atacar", "desesperada_atacar", "muro_desarmar_atacar"]:
		print(s, " ", sim(s, 10, 8, 10, 8))
	print("=== Combat-heavy 14/6 vs tank 6/14 (player = 14/6) ===")
	for s in ["ofensiva_atacar", "muro_atacar", "desesperada_atacar"]:
		print(s, " ", sim(s, 14, 6, 6, 14))
	print("=== Tank 6/14 vs 14/6 (player = tank) ===")
	for s in ["ofensiva_atacar", "muro_atacar", "desesperada_atacar"]:
		print(s, " ", sim(s, 6, 14, 14, 6))
	print("=== Stat gap: player +3 combat (10/8 vs 7/8) ===")
	for s in ["ofensiva_atacar", "muro_atacar"]:
		print(s, " ", sim(s, 10, 8, 7, 8))
	print("=== Stat gap: player -3 combat (7/8 vs 10/8) ===")
	for s in ["ofensiva_atacar", "muro_atacar", "muro_desarmar_atacar"]:
		print(s, " ", sim(s, 7, 8, 10, 8))
	print("=== Entrenar spam: player 20/8 vs court 9/8 ===")
	print("ofensiva_atacar ", sim("ofensiva_atacar", 20, 8, 9, 8))
	print("=== Skills (10/8 mirror, ofensiva_atacar unless noted) ===")
	print("Golpe Certero ", sim("ofensiva_atacar", 10, 8, 10, 8, "Golpe Certero"))
	print("Piel de Hierro ", sim("ofensiva_atacar", 10, 8, 10, 8, "Piel de Hierro"))
	print("Desarme Fulminante + ofensiva_desarmar_atacar ", sim("ofensiva_desarmar_atacar", 10, 8, 10, 8, "Desarme Fulminante"))
	print("Desarme Fulminante + muro_desarmar_atacar ", sim("muro_desarmar_atacar", 10, 8, 10, 8, "Desarme Fulminante"))
	quit()
