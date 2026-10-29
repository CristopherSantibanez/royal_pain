extends SceneTree
# Mundo con jugador pasivo (no hace nada) durante 36 meses: crecimiento de guarniciones,
# ataques contra el castillo del jugador, pérdida del castillo (fin de partida), castillos que cambian de manos.

const GAMES := 30
const MONTHS := 36

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var AD = root.get_node("ArmyData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	seed(4242)
	var homes := ["hielo", "carmesi", "gris", "oliva", "cumbres", "azul"]
	var lost := 0
	var lost_month_sum := 0
	var attacks_on_player := 0
	var avg_garr_12 := 0.0
	var avg_garr_36 := 0.0
	var changes := 0
	var event_months := 0
	for g in range(GAMES):
		var home: String = homes[g % homes.size()]
		var pc: Character = CL.make_test_character("Jugador%d" % g, CH.Role.NOBLEZA_BAJA)
		GM.start_new_game(pc, home)
		var initial := {}
		for c in MD.castles: initial[c.castle_id] = c.kingdom
		for m in range(MONTHS):
			GM.pending_event = {}
			GM.advance_turn()
			if not GM.pending_event.is_empty(): event_months += 1
			for e in AD.turn_events:
				if "Va hacia tu castillo" in e.text: attacks_on_player += 1
			if m == 11:
				for c in MD.castles: avg_garr_12 += c.garrison_size / 12.0 / GAMES
			if not GM.is_game_active:
				lost += 1
				lost_month_sum += m + 1
				break
		if GM.is_game_active:
			for c in MD.castles: avg_garr_36 += c.garrison_size / 12.0
		for c in MD.castles:
			if c.kingdom != initial[c.castle_id]: changes += 1
	var survived: int = GAMES - lost
	print("passive player, %d games x %d months" % [GAMES, MONTHS])
	print("home lost (game over): %d/%d, avg month of loss %.1f" % [lost, GAMES, float(lost_month_sum) / max(1, lost)])
	print("AI armies sent at player castle: %.2f per game" % (float(attacks_on_player) / GAMES))
	print("avg garrison all castles: month 12 = %.0f, month 36 (surviving games) = %.0f" % [avg_garr_12, avg_garr_36 / max(1, survived)])
	print("castles changed kingdom per game: %.2f" % (float(changes) / GAMES))
	print("months with a decision event: %.0f%%" % (100.0 * event_months / (GAMES * MONTHS)))
	quit()
