extends SceneTree
# Batallas con compañeros: el jugador (atacante) juega con la IA de BattleManager.

const N := 300
var BM
var BE
var CL
var CH

func _initialize() -> void:
	_run.call_deferred()

func _cmd() -> Character:
	var c: Character = CL.make_test_character("Cmd", CH.Role.NOBLEZA_ALTA)
	c.leadership = 8
	c.strategy = 8
	return c

func _companion(combat: int, leadership: int, faction: bool = false) -> Character:
	var c: Character = CL.make_test_character("Comp", CH.Role.CABALLERO)
	c.combat = combat
	c.leadership = leadership
	c.strategy = 6
	if faction:
		c.set_meta("faction_companion", true)
	return c

func _sim(label: String, att: int, defn: int, mine: Array[Character], theirs: Array[Character]) -> void:
	var wins := 0
	var wounded := 0
	for i in N:
		var b = BM.new()
		b.player_side = BE.Side.ATACANTE
		for c in mine + theirs:
			c.wound_months = 0
		b.start_battle(att, defn, true, _cmd(), _cmd(), "X", mine, theirs)
		var guard := 0
		while not b.is_over and guard < 50:
			guard += 1
			b._run_ai(BE.Side.ATACANTE)
			if b.is_over:
				break
			b.end_player_turn()
		if b.active_units(BE.Side.DEFENSOR).is_empty() and not b.active_units(BE.Side.ATACANTE).is_empty():
			wins += 1
		wounded += b.wounded_companions.size()
	print("%-42s atacante gana %5.1f%% | compañeros heridos por batalla %.2f" % [label, 100.0 * wins / N, float(wounded) / N])

func _run() -> void:
	BM = load("res://scripts/resources/battle_manager.gd")
	BE = load("res://scripts/resources/battle_enums.gd")
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	seed(99)
	var none: Array[Character] = []
	_sim("135 vs 90, sin compañeros", 135, 90, none, none)
	var two: Array[Character] = [_companion(12, 10), _companion(9, 8)]
	_sim("135 vs 90, 2 compañeros del séquito", 135, 90, two, none)
	var faction: Array[Character] = [_companion(8, 6, true), _companion(8, 6, true)]
	_sim("135 vs 90, 2 compañeros de facción", 135, 90, faction, none)
	var enemy: Array[Character] = [_companion(10, 9), _companion(10, 9)]
	_sim("135 vs 90, el señor enemigo trae 2", 135, 90, none, enemy)
	_sim("135 vs 90, 2 y 2", 135, 90, two, enemy)
	quit()
