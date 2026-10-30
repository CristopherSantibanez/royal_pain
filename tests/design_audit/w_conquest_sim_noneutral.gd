extends SceneTree
# Caballero enfocado en conquistar: cada mes gasta sus 2 acciones en movilizar o contratar
# mercenarios (reuniendo todo en un solo ejército), marcha al vecino más débil, lo asedia y
# asalta cuando tiene 1,5x su guarnición (asalto resuelto con auto_resolve). Mide meses hasta la 1ª conquista.

const GAMES := 40
const MONTHS := 36
const MOBILIZE := 0.4
const MERC_COST := 4
const MERC_MAX := 40
const ASSAULT_RATIO := 1.5

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for duel_income in [0, 50]:
		_batch(duel_income)
	quit()

func _batch(duel_income: int) -> void:
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var AD = root.get_node("ArmyData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var KAI = load("res://scripts/resources/kingdom_ai.gd")
	seed(777 + duel_income)
	var homes := ["hielo", "carmesi", "gris", "oliva", "cumbres", "azul"]
	var conquered_months: Array[int] = []
	var lost_home := 0
	for g in range(GAMES):
		var pc: Character = CL.make_test_character("Conquistador%d" % g, CH.Role.CABALLERO)
		pc.leadership = 8
		pc.strategy = 8
		GM.start_new_game(pc, homes[g % homes.size()])
		var home = MD.get_castle_by_id(GM.home_castle_id)
		var done := -1
		var army = null
		var target = null
		for m in range(MONTHS):
			pc.gold += duel_income
			# 2 acciones: si hay ejército en casa parado, se refuerza; si no, se moviliza.
			if target == null:
				for a in range(2):
					if pc.gold >= 40:
						var hired: int = mini(MERC_MAX, pc.gold / MERC_COST)
						pc.gold -= hired * MERC_COST
						army = AD.add_player_troops(home.castle_id, home.kingdom, hired)
					elif home.garrison_size >= 60:
						var mob := int(home.garrison_size * MOBILIZE)
						home.garrison_size -= mob
						army = AD.add_player_troops(home.castle_id, home.kingdom, mob)
				# Marcha si el ejército ya supera al vecino más débil.
				var weakest = null
				for nid in home.connected_castle_ids:
					var n = MD.get_castle_by_id(nid)
					if n != null and n.kingdom != home.kingdom and n.kingdom != 6 and (weakest == null or n.garrison_size < weakest.garrison_size):
						weakest = n
				if army != null and weakest != null and army.size >= weakest.garrison_size:
					AD.set_destination(army, weakest.castle_id)
					target = weakest
			elif army != null and army.pending_battle and army.size >= target.garrison_size * ASSAULT_RATIO:
				var r = KAI.auto_resolve(army.size, target.garrison_size)
				AD.resolve_battle(army, r.attacker_won, r.attacker_survivors, r.defender_survivors)
				if r.attacker_won:
					done = m + 1
					break
				army = null
				target = null
			elif army != null and not AD.armies.has(army):
				army = null
				target = null
			GM.pending_event = {}
			GM.advance_turn()
			if not GM.is_game_active:
				lost_home += 1
				break
		if done > 0:
			conquered_months.append(done)
	conquered_months.sort()
	var med := conquered_months[conquered_months.size() / 2] if not conquered_months.is_empty() else -1
	print("duel income %d/month: conquest in %d/%d games, median month %d, months %s, home lost %d" % [
		duel_income, conquered_months.size(), GAMES, med, str(conquered_months), lost_home])
