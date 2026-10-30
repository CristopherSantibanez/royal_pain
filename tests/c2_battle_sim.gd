extends SceneTree
# Batallas nuevas: desglose por rasgo del mapa, clima y hora; cuántas acaban por tiempo.

const N := 400
var BM
var BE
var CL
var CH
var with_skills := false

func _initialize() -> void:
	_run.call_deferred()

func _cmd() -> Character:
	var c: Character = CL.make_test_character("Cmd", CH.Role.NOBLEZA_ALTA)
	c.leadership = 8
	c.strategy = 8
	c.battle_skills.clear()
	if with_skills:
		var pool: Array = root.get_node("GameData").battle_skills.duplicate()
		pool.shuffle()
		c.battle_skills.append(pool[0])
		c.battle_skills.append(pool[1])
	return c

func _run() -> void:
	BM = load("res://scripts/resources/battle_manager.gd")
	BE = load("res://scripts/resources/battle_enums.gd")
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	seed(7)
	var none: Array[Character] = []
	for mode in ["skills", "all"]:
		with_skills = mode == "skills"
		var stats := {}
		var wins := 0
		var timeouts := 0
		var abilities := [0]
		var turns := 0
		for i in N:
			var b = BM.new()
			b.player_side = BE.Side.ATACANTE
			b.biome = i % 12
			if mode == "clear_day":
				b.random_conditions = false
			b.ability_used.connect(func(_c, _id, _s): abilities[0] += 1)
			b.start_battle(135, 90, true, _cmd(), _cmd(), "X", none, none)
			if mode == "no_feature":
				for x in BM.GRID_W:
					for y in BM.GRID_H:
						if b.terrain[x][y] in [BE.Terrain.RIO, BE.Terrain.VADO, BE.Terrain.PUENTE, BE.Terrain.ALDEA]:
							b.terrain[x][y] = BE.Terrain.LLANO
			var guard := 0
			while not b.is_over and guard < 50:
				guard += 1
				b._run_ai(BE.Side.ATACANTE)
				if b.is_over:
					break
				if mode == "no_hold":
					for u in b.units:
						u.order = BE.Order.NINGUNA
				b.end_player_turn()
			var won: bool = b.active_units(BE.Side.DEFENSOR).is_empty() and not b.active_units(BE.Side.ATACANTE).is_empty()
			var key: String = (b.map_feature.split(" ")[1] if not b.map_feature.is_empty() else "-") + " / " + BE.weather_name(b.weather) + " / " + BE.time_name(b.time_of_day)
			var feat: String = "feat:" + (b.map_feature.split(" ")[1] if not b.map_feature.is_empty() else "-")
			var wkey: String = "clima:" + BE.weather_name(b.weather) + "/" + BE.time_name(b.time_of_day)
			for k in [feat, wkey]:
				if not stats.has(k):
					stats[k] = [0, 0]
				stats[k][0] += 1
				stats[k][1] += 1 if won else 0
			wins += 1 if won else 0
			timeouts += 1 if b.turn > BM.MAX_TURNS else 0
			turns += b.turn
		print("== %s: atacante gana %.1f%% | por tiempo %.1f%% | turnos medios %.1f | habilidades/batalla %.2f" % [mode, 100.0 * wins / N, 100.0 * timeouts / N, float(turns) / N, float(abilities[0]) / N])
		if mode == "all":
			var keys := stats.keys()
			keys.sort()
			for k in keys:
				print("   %-30s n=%3d gana %.0f%%" % [k, stats[k][0], 100.0 * stats[k][1] / stats[k][0]])
	quit()
