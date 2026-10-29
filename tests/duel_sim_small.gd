extends SceneTree
# Simula el duelo nuevo: jugador con estrategias fijas o reactiva contra DuelAI con cada personalidad.

const N := 150
const CAP := 200

var CE
var CL
var CH
var AI
var NOBLE_ROLE := -1

func _initialize() -> void:
	_run.call_deferred()

func _mk(combat: int, defense: int, personality: int = -1) -> Character:
	var c: Character = CL.make_test_character("X", CH.Role.CABALLERO)
	c.combat = combat
	c.defense = defense
	c.personality = maxi(personality, 0)
	if NOBLE_ROLE >= 0 and personality >= 0:
		c.role = NOBLE_ROLE
	return c

func _player(d, me: Character, foe: Character, strat: String) -> void:
	var p: int = CE.Posture.OFENSIVA
	var a: int = CE.ActionType.ATACAR
	match strat:
		"ofensiva_atacar": pass
		"defensiva_atacar": p = CE.Posture.DEFENSIVA
		"muro_atacar": p = CE.Posture.MURO
		"esgrima_atacar": p = CE.Posture.ESGRIMA
		"desesperada_atacar": p = CE.Posture.DESESPERADA
		"reactiva":
			var foe_guard: bool = d.defending[foe] or d.dodging[foe] or d.countering[foe]
			if d.is_fatigued(me):
				p = CE.Posture.DEFENSIVA
				a = CE.ActionType.DEFENDER
			elif foe_guard:
				a = CE.ActionType.EMPUJAR
			elif me.current_stamina < 40 and randf() < 0.5:
				a = CE.ActionType.CONTRAATACAR
		"ia_astuta":
			var r: Dictionary = AI.choose(d, me, foe)
			p = r.posture
			a = r.action
			if a in [CE.ActionType.RENDIRSE, CE.ActionType.RETIRARSE]:
				a = CE.ActionType.DEFENDER
	d.set_posture(me, p)
	d.take_turn(me, a)

func _duel(strat: String, pc: Character, ec: Character) -> Array:
	var DM = load("res://scripts/resources/duel_manager.gd")
	var d = DM.new()
	d.start_duel(pc, ec)
	var player_turn: bool = d.roll_first(pc, ec) == pc
	var actions := 0
	var half := 0
	var holder := [null]
	d.duel_ended.connect(func(w, _r): holder[0] = w)
	while not d.is_over and half < CAP:
		if player_turn:
			_player(d, pc, ec, strat)
			actions += 1
		else:
			var r: Dictionary = AI.choose(d, ec, pc)
			d.set_posture(ec, r.posture)
			d.take_turn(ec, r.action)
		player_turn = not player_turn
		half += 1
	return [holder[0] == pc, actions, pc.current_health, d.is_over]

func _case(label: String, strat: String, pstats: Vector2i, estats: Vector2i, personality: int) -> void:
	var wins := 0
	var acts: Array = []
	var unfinished := 0
	for i in N:
		var r := _duel(strat, _mk(pstats.x, pstats.y), _mk(estats.x, estats.y, personality))
		if r[0]:
			wins += 1
		acts.append(r[1])
		if not r[3]:
			unfinished += 1
	acts.sort()
	print("%-34s win=%5.1f%%  clicks median=%d p90=%d  unfinished=%d" % [label, 100.0 * wins / N, acts[N / 2], acts[int(N * 0.9)], unfinished])

func _run() -> void:
	CE = load("res://scripts/resources/combat_enums.gd")
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	AI = load("res://scripts/resources/duel_ai.gd")
	var P = CH.Personality
	print("--- 7/5 vs 7/5, enemigo por personalidad, jugador reactivo ---")
	for name in P.keys():
		_case("reactiva vs " + name, "reactiva", Vector2i(7, 5), Vector2i(7, 5), P[name])
	print("--- estrategias fijas vs ARROGANTE / PRUDENTE (7/5) ---")
	for s in ["ofensiva_atacar", "defensiva_atacar", "muro_atacar", "esgrima_atacar", "desesperada_atacar", "reactiva", "ia_astuta"]:
		_case(s + " vs ARROGANTE", s, Vector2i(7, 5), Vector2i(7, 5), P.ARROGANTE)
		_case(s + " vs PRUDENTE", s, Vector2i(7, 5), Vector2i(7, 5), P.PRUDENTE)
	print("--- diferencias de atributos (reactiva vs LEAL) ---")
	_case("+3 combate", "reactiva", Vector2i(10, 5), Vector2i(7, 5), P.LEAL)
	_case("-3 combate", "reactiva", Vector2i(4, 5), Vector2i(7, 5), P.LEAL)
	_case("20/8 vs 9/8", "reactiva", Vector2i(20, 8), Vector2i(9, 8), P.LEAL)
	print("--- dificultad por rango del rival (reactiva, 7/5 vs 7/5, LEAL) ---")
	for role in [CH.Role.CAMPESINO, CH.Role.SOLDADO, CH.Role.NOBLEZA_ALTA, CH.Role.REGENTE]:
		NOBLE_ROLE = role
		_case("rival rol %d" % role, "reactiva", Vector2i(7, 5), Vector2i(7, 5), P.LEAL)
	NOBLE_ROLE = -1
	quit()
