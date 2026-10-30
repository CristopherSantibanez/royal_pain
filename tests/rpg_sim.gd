extends SceneTree
# Simulación de equilibrio del combate RPG: duración de combates, espejo por tipo de líder y peso de las debilidades.
# Objetivos: 4–8 rondas; cada tipo 45–55% como líder en espejo; acertar debilidades sube las victorias
# de forma clara pero no decisiva.

const N := 30                 # combates por caso (subir para más precisión)
const MIRROR_LEVEL := 6
const WEAK_TEST_LEVEL_UP := 4   # soldados veteranos más fuertes: así se nota el arma
const LEVELS := [3, 8, 14]
const ATTR_BASE := 6.0
const ATTR_PER_LEVEL := 0.4
const HERO_ARMORS := [RpgStats.ArmorClass.CUERO, RpgStats.ArmorClass.MALLA, RpgStats.ArmorClass.PLACAS]

func _initialize() -> void:
	_run.call_deferred()

func _hero(ft: int, lvl: int) -> Character:
	var c := Character.new()
	c.first_name = "H%d" % randi()
	c.fighter_type = ft
	c.level = lvl
	c.role = Character.Role.CABALLERO
	c.personality = Character.Personality.values().pick_random()
	c.set_meta(RpgStats.META_ARMOR, HERO_ARMORS.pick_random())   # armadura y arma variadas: el espejo mide el tipo, no el arma
	c.set_meta(RpgStats.META_DAMAGE, randi() % 4)
	var a := roundi(ATTR_BASE + lvl * ATTR_PER_LEVEL)
	c.combat = a
	c.defense = a
	c.strategy = a
	c.leadership = a
	c.charisma = a
	return c

func _party(types: Array, lvl: int) -> Array:
	return types.map(func(t: int) -> Character: return _hero(t, lvl))

func _fight(a: Array, b: Array) -> Dictionary:
	var bm := RpgBattleManager.new()
	bm.setup(a, b, {"auto_learn": [0, 1], "can_flee": false})
	return bm.run_auto()

func _run() -> void:
	seed(11)
	var F := CharacterEnums.FighterType
	var all: Array = F.values()
	print("[duración] grupo de 4 contra 2/4/6 enemigos")
	print("  nivel  enemigos  victorias  rondas")
	var groups := {2: [["capitan_bandido", "bandido"], 1], 4: [["soldado", "bandido", "arquero", "piquero"], -1], 6: [["bandido", "miliciano", "soldado", "arquero", "miliciano", "explorador"], -1]}
	for lvl in LEVELS:
		for size in groups:
			var wins := 0
			var rounds := 0.0
			for i in N:
				all.shuffle()
				var foes: Array = []
				for t in groups[size][0]:
					foes.append(EnemyCatalog.make_enemy(t, lvl + int(groups[size][1])))
				var r := _fight(_party(all.slice(0, 4), lvl), foes)
				wins += 1 if r.winner == 0 else 0
				rounds += r.rounds
			print("  %5d  %8d  %8d%%  %6.1f" % [lvl, size, 100 * wins / N, rounds / N])
	print("[espejo] tipo como líder contra los demás (mismos 3 compañeros)")
	var total_rounds := 0.0
	var fights := 0
	for x in all:
		var wins := 0
		var games := 0
		for y in all:
			if y == x:
				continue
			for i in N / 2:
				var mates: Array = []
				for k in 3:
					mates.append(all.pick_random())
				var a := _party([x] + mates, MIRROR_LEVEL)
				var b := _party([y] + mates, MIRROR_LEVEL)
				var r := _fight(a, b) if i % 2 == 0 else _fight(b, a)
				var x_side := 0 if i % 2 == 0 else 1
				wins += 1 if r.winner == x_side else 0
				games += 1
				total_rounds += r.rounds
				fights += 1
		print("  %-10s %3d%%" % [CharacterEnums.fighter_type_name(x), 100 * wins / games])
	print("  rondas medias en espejo: %.1f" % (total_rounds / fights))
	print("[debilidades] grupo mixto contra 4 soldados (Malla) a nivel %d" % MIRROR_LEVEL)
	for dt in [RpgStats.DamageType.ESTOCADA, RpgStats.DamageType.CONTUNDENTE, RpgStats.DamageType.TAJO]:
		var wins := 0
		for i in N * 2:
			all.shuffle()
			var a := _party(all.slice(0, 4), MIRROR_LEVEL)
			for c: Character in a:
				c.set_meta(RpgStats.META_DAMAGE, dt)
			var foes: Array = []
			for k in 4:
				foes.append(EnemyCatalog.make_enemy("soldado", MIRROR_LEVEL + WEAK_TEST_LEVEL_UP, 1))
			wins += 1 if _fight(a, foes).winner == 0 else 0
		print("  %-12s %3d%%" % [RpgStats.DAMAGE_NAMES[dt], 100 * wins / (N * 2)])
	quit()
