extends SceneTree
# ¿Cada cuánto te llaman a filas? Jugador pasivo (soldado) en su castillo, 20 partidas de 36 meses.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var calls := 0
	var field := 0
	var sieges := 0
	var games := 20
	for g in games:
		MD.new_world()
		var player = CL.make_test_character("Sir Prueba", CH.Role.SOLDADO)
		player.fame = 30
		GM.start_new_game(player, MD.castles[g % MD.castles.size()].castle_id)
		for m in 36:
			GM.pending_event = {}
			GM.advance_turn()
			var e: Dictionary = GM.pending_event
			if e.get("id", "") == "llamada_a_filas":
				calls += 1
				if e.title == "Batalla campal":
					field += 1
				else:
					sieges += 1
				# declina para que el mundo siga
				GM.resolve_pending_event(1, root.get_node("RelationsData").get_relation(e.get("target", "")))
			GM.pending_event = {}
	print("llamadas a filas por partida (36 meses): %.2f  · asedios %.2f · batallas campales %.2f" % [
		calls / float(games), sieges / float(games), field / float(games)])
	quit()
