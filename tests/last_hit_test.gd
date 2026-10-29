extends SceneTree
# Regresión: clicar para atacar y rematar al último pelotón enemigo (antes: «is_active» en Nil, battle.gd:303).

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var GM = root.get_node("GameManager")
	var CS = root.get_node("CombatSetup")
	var MD = root.get_node("MapData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var EC = load("res://scripts/resources/event_catalog.gd")
	var player = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	GM.start_new_game(player, MD.castles[0].castle_id)
	MD.get_castle_by_id(GM.home_castle_id).garrison_size = 100
	var bandits: Dictionary = {}
	for e in EC.EVENTS:
		if e.id == "bandidos":
			bandits = e
	var fight: Dictionary = bandits.options.filter(func(o): return o.has("fight") and o.fight.type == "battle")[0].fight
	change_scene_to_file(CS.begin_event_fight(fight, bandits.title))
	await create_timer(0.6).timeout
	var scene = current_scene
	var b = scene.battle
	var mine = b.units.filter(func(u): return b.is_player_unit(u) and u.is_active())
	var foes = b.units.filter(func(u): return not b.is_player_unit(u) and u.is_active())
	# Deja un solo enemigo, con 1 soldado, pegado a un pelotón propio.
	for i in range(1, foes.size()):
		foes[i].soldiers = 0
	var foe = foes[0]
	foe.soldiers = 1
	foe.morale = 1
	var attacker = mine.filter(func(u): return u.type != BattleEnums.UnitType.ARQUEROS)[0] if mine.any(func(u): return u.type != BattleEnums.UnitType.ARQUEROS) else mine[0]
	attacker.soldiers = 200
	var free_cell := Vector2i(-1, -1)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = foe.cell + d
		if b.in_bounds(c) and b.unit_at(c) == null:
			free_cell = c
			break
	attacker.cell = free_cell
	attacker.has_moved = false
	attacker.has_acted = false
	scene.selected = attacker
	var in_range: bool = foe in b.targets_in_range(attacker) and b.can_attack(attacker)
	print("objetivo en alcance: ", in_range)
	scene._on_cell_clicked(foe.cell)
	await create_timer(0.3).timeout
	print("batalla terminada: ", b.is_over, " · selección: ", scene.selected)
	quit()
