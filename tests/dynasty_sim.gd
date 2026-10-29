extends SceneTree
# 40 años de partida real (480 meses) con eventos al azar. El jugador se casa en cuanto puede
# (simulado: con una dama/caballero de su corte del otro sexo) y, al morir, hereda el hijo adulto mayor.
# Al final, una simulación rápida de solo las reglas de dinastía (1000 vidas) para ver medias.

const RUNS := 3
const MONTHS := 480

func _initialize() -> void:
	_run.call_deferred()

func _marry(RD, player) -> bool:
	if RD.is_married() or player.age < 18:
		return false
	var want := CharacterEnums.Gender.FEMENINO if player.gender == CharacterEnums.Gender.MASCULINO else CharacterEnums.Gender.MASCULINO
	for r in RD.relations:
		if r.character != null and r.character.gender == want and r.kind != Relationship.Kind.SENOR and r.character.age >= 16 and r.character.age <= 30:
			r.kind = Relationship.Kind.CONYUGE
			RD.spouse_name = r.person_name
			return true
	return false

func _run() -> void:
	var GM = root.get_node("GameManager")
	var RD = root.get_node("RelationsData")
	var MD = root.get_node("MapData")
	var DD = root.get_node("DynastyData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	for run in RUNS:
		seed(100 + run)
		var player = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
		player.gold = 500
		GM.start_new_game(player, MD.castles[run].castle_id)
		await process_frame
		var births := 0
		var log: Array[String] = []
		var generation := 1
		var t0 := Time.get_ticks_msec()
		var last_kids := 0
		for m in MONTHS:
			if not GM.is_game_active:
				log.append("año %d: partida terminada — %s" % [GM.current_year, GM.game_over_reason])
				break
			if _marry(RD, GM.player_character):
				log.append("año %d: %s se casa a los %d" % [GM.current_year, GM.player_character.full_name(), GM.player_character.age])
			for c in MD.castles:
				if c.kingdom == GM.player_kingdom:
					c.garrison_size = 5000
			GM.advance_turn()
			await process_frame
			if GM.has_pending_event():
				var e: Dictionary = GM.pending_event
				var rel = RD.get_relation(e.get("target", e.get("speaker", "")))
				GM.resolve_pending_event(randi() % e.options.size(), rel)
			var kids: int = DD.children().size()
			if kids > last_kids:
				births += kids - last_kids
			last_kids = kids
			if DD.needs_succession():
				var adults: Array = DD.adult_children()
				log.append("año %d: muere %s %s" % [GM.current_year, DD.deceased_name(), DD.death_cause()])
				if adults.is_empty():
					log.append("año %d: %s" % [GM.current_year, DD.end_lineage()])
					break
				adults.sort_custom(func(a, b): return a.age > b.age)
				log.append("año %d: %s" % [GM.current_year, DD.succeed(adults[0])])
				generation += 1
				last_kids = DD.children().size()
		print("=== Partida %d (%.1f s) ===" % [run + 1, (Time.get_ticks_msec() - t0) / 1000.0])
		for l in log:
			print("  ", l)
		var p = GM.player_character
		if p != null:
			print("  Final año %d: %s, %d años, nivel %d, generación %d, nacimientos %d, hijos vivos %d (adultos %d)" % [
				GM.current_year, p.full_name(), p.age, p.level, generation, births, DD.children().size(), DD.adult_children().size()])
		else:
			print("  Final: sin jugador · generación %d · nacimientos %d" % [generation, births])

	# Solo reglas: edad de muerte e hijos por vida (casado a los 20 con cónyuge de 20).
	var deaths := []
	var kids_total := 0
	var adult_at_death := 0
	for i in 1000:
		var age := 20
		var spouse := 20
		var kid_ages: Array = []
		while true:
			age += 1
			spouse += 1
			for k in kid_ages.size():
				kid_ages[k] += 1
			if spouse < DD.MAX_FERTILE_AGE and kid_ages.size() < DD.MAX_CHILDREN and randf() < DD.BIRTH_CHANCE:
				kid_ages.append(0)
			if randf() < DD.old_age_chance(age):
				break
		deaths.append(age)
		kids_total += kid_ages.size()
		if kid_ages.any(func(a): return a >= DD.ADULT_AGE):
			adult_at_death += 1
	deaths.sort()
	var total := 0
	for d in deaths:
		total += d
	print("=== Reglas (1000 vidas, casado a los 20) ===")
	print("  muerte por vejez: media %.1f años · mediana %d · p10 %d · p90 %d · máx %d" % [
		float(total) / deaths.size(), deaths[500], deaths[100], deaths[900], deaths[-1]])
	print("  hijos por vida: %.2f · con heredero adulto al morir: %.1f%%" % [float(kids_total) / 1000.0, adult_at_death / 10.0])
	quit()
