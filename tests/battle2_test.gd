extends SceneTree
# Batallas v2: campesinos solo si los llaman, llamadas a filas con IA aliada, lazos de batalla,
# duelos singulares entre jefes (jugados y automáticos), traición en plena batalla y guardado.

var fails := 0
var GM
var CS
var MD
var AD
var RD
var TD
var CL
var CH
var EC
var SS

func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok  ", what)
	else:
		fails += 1
		print("  FALLA ", what)

func _initialize() -> void:
	_run.call_deferred()

# Un castillo de tu reino (que no es tu hogar) con un vecino de otro reino: el escenario de las llamadas.
func _front() -> Array:
	for pass_i in 2:
		for t in MD.castles:
			if t.castle_id == GM.home_castle_id or (pass_i == 0 and t.kingdom != GM.player_kingdom):
				continue
			for id in t.connected_castle_ids:
				var e = MD.get_castle_by_id(id)
				if e == null or e.kingdom == t.kingdom or e.kingdom == GM.player_kingdom or e.castle_id == GM.home_castle_id:
					continue
				if RD.get_relation(e.owner_name) != null and RD.get_relation(t.owner_name) != null:
					return [t, e]
	return []

func _siege(from_castle, to_castle, size: int):
	var a = AD.create_army(from_castle.owner_name, from_castle.kingdom, size, from_castle.castle_id)
	a.origin_castle_id = from_castle.castle_id
	a.current_castle_id = to_castle.castle_id
	a.destination_castle_id = ""
	a.pending_battle = true
	return a

func _wait_duel(scene) -> Object:
	for i in 120:
		await process_frame
		for ch in scene.get_children():
			if ch is CanvasLayer and ch.get_child_count() > 0 and "embedded" in ch.get_child(0):
				var d = ch.get_child(0)
				if d.duel != null:
					return d
	return null

# Juega el duelo atacando cada vez que te toca, y vuelve a la batalla.
func _play_embedded(scene) -> bool:
	var d = await _wait_duel(scene)
	if d == null:
		return false
	var guard := 0
	while not d.duel.is_over and guard < 300:
		Engine.time_scale = 6.0
		if d.player_turn:
			d._player_action(0)
		await create_timer(0.25).timeout
		guard += 1
	Engine.time_scale = 1.0
	d._on_volver_menu_pressed()
	await process_frame
	return true

func _kill_side(b, side: int) -> void:
	for u in b.units:
		if u.side == side and u.is_active():
			u.soldiers = 1
			u.morale = 1

func _run() -> void:
	seed(11)
	GM = root.get_node("GameManager")
	CS = root.get_node("CombatSetup")
	MD = root.get_node("MapData")
	AD = root.get_node("ArmyData")
	RD = root.get_node("RelationsData")
	TD = root.get_node("TravelData")
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	EC = load("res://scripts/resources/event_catalog.gd")
	SS = load("res://scripts/resources/save_system.gd")
	var player = CL.make_test_character("Sir Alaric", CH.Role.CAMPESINO)
	player.honor = 70
	player.combat = 14
	player.defense = 12
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame
	GM.pending_event = {}

	print("[campesino: sin batallas por su cuenta]")
	var bandits: Dictionary = {}
	for e in EC.EVENTS:
		if e.id == "bandidos":
			bandits = e
	var battle_opt: Dictionary = bandits.options.filter(func(o): return o.has("fight") and o.fight.type == "battle")[0]
	var home = MD.get_castle_by_id(GM.home_castle_id)
	home.garrison_size = 100
	check(not EC.can_choose(battle_opt, player, home), "la opción de batalla del evento está bloqueada")
	check(EC.requirement_text(battle_opt).contains("campesino"), "explica por qué: «%s»" % EC.requirement_text(battle_opt))
	check(CS.begin_event_fight(battle_opt.fight, "Bandidos") == "", "begin_event_fight no prepara la escaramuza")
	var stuck: Array[String] = []
	for e in EC.EVENTS:
		var any_ok := false
		for o in e.options:
			if not o.has("fight") or o.fight.get("type", "") != "battle":
				any_ok = true
		if not any_ok:
			stuck.append(e.id)
	check(stuck.is_empty(), "ningún evento deja al campesino sin opción posible %s" % [stuck])
	var own_army = AD.add_player_troops(home.castle_id, home.kingdom, 30)
	var foreign = null
	for id in home.connected_castle_ids:
		var c = MD.get_castle_by_id(id)
		if c.kingdom != home.kingdom:
			foreign = c
	if foreign != null:
		check(not AD.set_destination(own_army, foreign.castle_id), "no puede llevar un ejército contra otro reino")
	AD.disband_army(own_army)
	var neighbor = MD.get_castle_by_id(home.connected_castle_ids[0])
	var raid = AD.create_army(neighbor.owner_name, (home.kingdom + 1) % 6, 40, neighbor.castle_id)
	raid.origin_castle_id = neighbor.castle_id
	raid.destination_castle_id = home.castle_id
	var pend := [false]
	AD.battle_pending.connect(func(_a): pend[0] = true)
	TD.location_id = home.castle_id
	RD.get_relation(RD.liege_name).affinity = 10
	AD._resolve_arrival(raid)
	check(not pend[0], "un asedio a su castillo no le obliga a defenderlo")
	check(GM.pending_event.get("id", "") == "llamada_a_filas", "su señor lo llama a filas para defenderlo (%s)" % GM.pending_event.get("title", "nada"))
	if GM.pending_event.get("id", "") == "llamada_a_filas":
		check(EC.can_choose(GM.pending_event.options[0], player, home), "aceptar la llamada sí está permitido")
		GM.resolve_pending_event(1, RD.get_relation(GM.pending_event.target))
	check(AD.find_army(raid.army_id) == null or not AD.find_army(raid.army_id).pending_battle, "al declinar, el asedio se resuelve sin él")

	print("[llamada a filas: asedio con IA aliada]")
	player.role = CH.Role.SOLDADO
	GM.pending_event = {}
	var pair := _front()
	check(not pair.is_empty(), "hay un frente para probar")
	if pair.is_empty():
		quit(1)
		return
	var target = pair[0]
	var enemy = pair[1]
	target.garrison_size = 80
	TD.location_id = target.castle_id
	var lord_rel = RD.get_relation(target.owner_name)
	lord_rel.affinity = 30
	var siege = _siege(enemy, target, 70)
	print("  diag: rol=%s reino=%d target=%s(%d) enemigo=%s(%d) cerca=%s def=%s att=%s pend=%s" % [player.role_title(), GM.player_kingdom,
		target.castle_name, target.kingdom, enemy.castle_name, enemy.kingdom, AD._player_near(target, enemy.castle_id),
		AD._inviter_for(target.owner_name, target.kingdom, enemy.kingdom), AD._inviter_for(enemy.owner_name, enemy.kingdom, target.kingdom), GM.pending_event.get("id", "")])
	var offered_inv := false
	for i in 10:
		if AD.offer_invitation(siege):
			offered_inv = true
			break
	check(offered_inv, "estando allí, te llaman a filas")
	var ev: Dictionary = GM.pending_event
	check(ev.get("id", "") == "llamada_a_filas" and ev.options[0].fight.type == "invited", "evento con opción de unirte (%s)" % ev.get("text", "").left(80))
	check(int(ev.options[0].fight.side) == BattleEnums.Side.DEFENSOR, "te llaman a defender %s" % target.castle_name)

	print("[guardado con la llamada pendiente]")
	check(SS.save_game() == OK and SS.load_game(), "se guarda y se carga")
	check(GM.pending_event.get("id", "") == "llamada_a_filas", "la llamada sigue pendiente tras cargar")
	siege = AD.find_army(str(GM.pending_event.options[0].fight.army_id))
	check(siege != null and siege.pending_battle, "el asedio sigue esperando")
	target = MD.get_castle_by_id(target.castle_id)
	enemy = MD.get_castle_by_id(enemy.castle_id)
	player = GM.player_character
	lord_rel = RD.get_relation(target.owner_name)

	var fight: Dictionary = GM.pending_event.options[0].fight
	var title: String = GM.pending_event.title
	GM.resolve_pending_event(0, lord_rel)
	var scene_path: String = CS.begin_event_fight(fight, title)
	check(scene_path.ends_with("battle.tscn"), "aceptar lleva a la batalla")
	var gold_before: int = player.gold
	var target_kingdom: int = target.kingdom
	var affection_before: int = lord_rel.affection
	change_scene_to_file(scene_path)
	await create_timer(0.6).timeout
	var scene = current_scene
	var b = scene.battle
	var mine = b.units.filter(func(u): return b.is_player_unit(u))
	var allies = b.units.filter(func(u): return u.ally)
	check(not allies.is_empty() and allies.all(func(u): return u.side == b.player_side and not b.is_player_unit(u)), "%d pelotones aliados en tu bando, que no mueves" % allies.size())
	check(mine.size() >= 1 and mine.size() <= 2, "mueves %d pelotón(es) propio(s)" % mine.size())
	check(mine.any(func(u): return u.captain == player), "tu pelotón lo encabezas tú")
	check(b._commander(b.player_side) != player and allies.any(func(u): return u.captain == b._commander(b.player_side)), "el anfitrión manda a los aliados")
	check(b.ability_users(b.player_side, b.ABILITY_PLAYER).all(func(c): return c != b._commander(b.player_side)), "las órdenes del anfitrión no son tuyas")
	check(b.has_walls and not b.challenge_blocker(mine[0], b.active_units(b._other_side(b.player_side))[0]).is_empty(), "en un asedio no hay duelos de jefes")
	var cells_before = allies.map(func(u): return u.cell)
	var soldiers_before: int = b.total_soldiers(b._other_side(b.player_side))
	for i in 6:
		scene._on_end_turn_pressed()
		await process_frame
	var moved := false
	for i in allies.size():
		if allies[i].cell != cells_before[i] or allies[i].has_acted:
			moved = true
	check(moved or b.total_soldiers(b._other_side(b.player_side)) < soldiers_before, "la IA aliada mueve y lucha")
	_kill_side(b, b._other_side(b.player_side))
	var live = b.units.filter(func(u): return b.is_player_unit(u) and u.is_active())
	if not live.is_empty():
		for t in b.active_units(b._other_side(b.player_side)):
			if not b.is_over:
				t.cell = live[0].cell + Vector2i(1, 0) if b.player_side == BattleEnums.Side.ATACANTE else live[0].cell + Vector2i(-1, 0)
	var guard := 0
	while not b.is_over and guard < 20:
		scene._on_end_turn_pressed()
		await process_frame
		guard += 1
	await create_timer(1.5).timeout
	check(b.is_over and b.player_side == BattleEnums.Side.DEFENSOR, "la batalla termina")
	var won: bool = b.active_units(b._other_side(b.player_side)).is_empty()
	check(AD.find_army(siege.army_id) == null, "el asedio queda resuelto en el mapa")
	check(not won or target.kingdom == target_kingdom, "si ganáis, %s no cambia de manos" % target.castle_name)
	check(not won or player.gold > gold_before, "tu anfitrión paga si ganáis (%d → %d)" % [gold_before, player.gold])
	check(lord_rel.affection > affection_before, "luchar a su lado sube la intimidad con %s (%d → %d)" % [lord_rel.person_name, affection_before, lord_rel.affection])
	check(CS.invited.is_empty(), "la batalla ajena queda cerrada")
	print("  cartel: ", scene.result_label.text.replace("\n", " / ").left(300))

	print("[batalla campal: duelos de jefes]")
	var IC = load("res://scripts/resources/invitation_catalog.gd")
	var ally_castle = target
	var foe_castle = enemy
	ally_castle.garrison_size = 100
	foe_castle.garrison_size = 100
	var fe: Dictionary = IC.field_event(ally_castle, foe_castle, ally_castle.owner_name, ally_castle.owner_name, false)
	change_scene_to_file(CS.begin_event_fight(fe.options[0].fight, fe.title))
	await create_timer(0.6).timeout
	scene = current_scene
	b = scene.battle
	check(not b.has_walls and b.has_allies(), "campo abierto con aliados")
	var my_unit = b.units.filter(func(u): return b.is_player_unit(u) and u.captain == player)[0]
	var foes = b.active_units(b._other_side(b.player_side))
	var foe_unit = foes[0]
	foe_unit.cell = my_unit.cell + Vector2i(1, 0)
	var foe_leader = foe_unit.leader()
	foe_leader.personality = CH.Personality.VALIENTE
	foe_leader.combat = player.combat
	foe_leader.defense = player.defense
	foe_leader.current_health = 4
	player.current_health = player.max_health
	scene.selected = my_unit
	check(b.can_challenge(my_unit, foe_unit), "puedes retar al jefe que tienes delante (%s)" % b.challenge_blocker(my_unit, foe_unit))
	var low = CL.make_test_character("Sin Honor", CH.Role.SOLDADO)
	low.honor = 10
	var keep = my_unit.captain
	my_unit.captain = low
	check(b.challenge_blocker(my_unit, foe_unit).contains("honor"), "sin honor no se reta")
	my_unit.captain = keep
	scene._issue_challenge(my_unit, foe_unit)
	await process_frame
	if foe_unit.challenged and not foe_unit.left_field and not my_unit.left_field:
		check(true, "(el retado rehusó: se probará el duelo de otra forma)")
	else:
		var played := await _play_embedded(scene)
		check(played, "el duelo se juega de verdad encima del tablero")
		await process_frame
		check(foe_unit.left_field and not foe_unit.is_active(), "al vencer, el jefe enemigo se retira con su pelotón")
		check(my_unit.has_acted and my_unit.challenged, "retar gasta el turno del pelotón")
	# Rehusar: un cobarde dice que no y su bando pierde moral.
	var coward_unit = b.active_units(b._other_side(b.player_side)).filter(func(u): return not u.challenged)[0]
	var morale_before: int = coward_unit.morale
	b.refuse_challenge(b.units.filter(func(u): return u.ally and u.is_active())[0], coward_unit)
	check(coward_unit.morale == morale_before - b.CHALLENGE_REFUSE_MORALE, "rehusar cuesta moral a su bando (%d → %d)" % [morale_before, coward_unit.morale])
	# Duelo entre jefes que no manejas: se resuelve solo.
	var a1 = CL.make_test_character("Aliado Fuerte", CH.Role.CABALLERO)
	a1.combat = 18
	a1.defense = 16
	var e1 = CL.make_test_character("Enemigo Flojo", CH.Role.SOLDADO)
	e1.combat = 4
	e1.defense = 4
	var wins := 0
	for i in 10:
		a1.current_health = a1.max_health
		e1.current_health = e1.max_health
		if b.auto_duel(a1, e1) == a1:
			wins += 1
	check(wins >= 7, "el duelo automático lo gana casi siempre el mejor (%d/10)" % wins)
	# La IA reta a uno de tus jefes: la batalla espera tu respuesta. Rehúsas una vez; luego aceptas y pierdes.
	for accept in [false, true]:
		b.is_over = true
		change_scene_to_file(CS.begin_event_fight(fe.options[0].fight, fe.title))
		await create_timer(0.6).timeout
		scene = current_scene
		b = scene.battle
		var mu = b.units.filter(func(u): return b.is_player_unit(u) and u.captain == player)[0]
		var au = b.active_units(b._other_side(b.player_side))[0]
		var spot: Vector2i = mu.cell + Vector2i(1, 0)
		var blocker_unit = b.unit_at(spot)
		if blocker_unit != null and blocker_unit != au:
			blocker_unit.cell = Vector2i(b.GRID_W - 1, 0)
		au.cell = spot
		au.leader().combat = 20
		au.leader().defense = 20
		au.leader().current_health = au.leader().max_health
		au.leader().wound_months = 0   # pudo quedar herido en el duelo anterior
		au.leader().honor = maxi(au.leader().honor, BattleManager.CHALLENGE_MIN_HONOR + 10)   # el retador necesita honor
		au.challenged = false
		mu.challenged = false
		for other in b.units:   # solo este pelotón de la IA puede retar, y solo a tu jefe
			if other != au and other != mu:
				other.challenged = true
		player.current_health = 3
		var offered := false
		for i in 80:
			au.has_acted = false
			if b._ai_try_challenge(b._other_side(b.player_side)):
				offered = true
				break
		check(offered and not b.pending_challenge.is_empty() and b.pending_challenge.target == mu, "la IA reta a tu jefe y la batalla espera tu respuesta (%s)" % b.challenge_blocker(au, mu))
		check(scene._prompt != null and scene.btn_end_turn.disabled, "se te pregunta (y no puedes pasar turno mientras)")
		if not offered:
			continue
		var turn_before: int = b.turn
		if not accept:
			var m_before: int = mu.morale
			scene._answer_challenge(false)
			await process_frame
			check(b.pending_challenge.is_empty() and (b.turn > turn_before or b.is_over), "al rehusar, sigue el turno enemigo")
			check(mu.morale < m_before or not mu.is_active(), "rehusar te cuesta moral")
		else:
			scene._answer_challenge(true)
			var played := await _play_embedded(scene)
			await process_frame
			check(played, "aceptas y juegas el duelo")
			check(mu.left_field or au.left_field, "quien pierde se retira del campo (tuyo: %s, suyo: %s)" % [mu.left_field, au.left_field])
			check(b.pending_challenge.is_empty() and (b.turn > turn_before or b.is_over), "tras el duelo sigue el turno enemigo")
	player.current_health = player.max_health

	print("[traición en plena batalla]")
	b.is_over = true
	GM.pending_event = {}
	player.honor = 70
	var traitor_target = target
	traitor_target.garrison_size = 90
	# Si el asedio anterior lo perdió tu bando, el castillo es ya del atacante: se le devuelve a su señor
	# para que la escena tenga sentido (defiendes a uno, te pasas al otro).
	if traitor_target.owner_name == enemy.owner_name or traitor_target.kingdom == enemy.kingdom:
		for r in RD.lords():
			if r.person_name != enemy.owner_name and KD_kingdom(r) != enemy.kingdom and not RD.castles_of(r.person_name).is_empty():
				traitor_target.owner_name = r.person_name
				traitor_target.kingdom = RD.castles_of(r.person_name)[0].kingdom
				break
	var siege2 = _siege(enemy, traitor_target, 90)
	var enemy_lord: String = enemy.owner_name
	var old_liege: String = RD.liege_name
	CS.invited = {}
	var inv_fight := {"type": "invited", "kind": "army", "army_id": siege2.army_id, "side": BattleEnums.Side.DEFENSOR,
		"lord": traitor_target.owner_name, "inviter": traitor_target.owner_name, "castle_id": traitor_target.castle_id}
	change_scene_to_file(CS.begin_event_fight(inv_fight, "Llamada a filas"))
	await create_timer(0.6).timeout
	scene = current_scene
	b = scene.battle
	var host_rel = RD.get_relation(traitor_target.owner_name)
	var host_aff: int = host_rel.affinity
	var honor_before: int = player.honor
	check(scene._betrayal_blocker() == "", "en una batalla ajena puedes traicionar")
	var own_before = b.units.filter(func(u): return u.own)
	scene._on_betray_pressed()
	check(b.betrayed_side < 0 and scene._betray_armed, "el primer clic solo pide confirmación")
	scene._on_betray_pressed()
	check(b.betrayed_side == BattleEnums.Side.DEFENSOR and b.player_side == BattleEnums.Side.ATACANTE, "tus pelotones se pasan al atacante")
	check(own_before.all(func(u): return u.side == BattleEnums.Side.ATACANTE and b.is_player_unit(u)), "siguen siendo tuyos, ahora en el otro bando")
	check(b.units.filter(func(u): return u.side == BattleEnums.Side.ATACANTE and not u.own).all(func(u): return u.ally), "los antiguos enemigos son tus aliados (IA)")
	check(b.units.filter(func(u): return u.side == BattleEnums.Side.DEFENSOR).all(func(u): return not u.ally), "tu antiguo bando lo mueve la IA enemiga")
	check(host_rel.affinity <= host_aff + AD.BETRAYAL_RELATION + 1, "tu anfitrión traicionado te odia (%d → %d)" % [host_aff, host_rel.affinity])
	check(player.honor == maxi(0, honor_before - AD.BETRAYAL_HONOR), "honor −%d (%d → %d)" % [AD.BETRAYAL_HONOR, honor_before, player.honor])
	check(scene._betrayal_blocker() != "", "no se traiciona dos veces")
	_kill_side(b, BattleEnums.Side.DEFENSOR)
	guard = 0
	while not b.is_over and guard < 25:
		scene._on_end_turn_pressed()
		await process_frame
		guard += 1
	if not b.is_over:
		b._end_battle(BattleEnums.Side.ATACANTE, "Prueba: el castillo cae.")
	await create_timer(1.5).timeout
	check(RD.liege_name == enemy_lord or RD.liege_name != old_liege, "tras la batalla juras lealtad a %s (señor: %s)" % [enemy_lord, RD.liege_name])
	check(GM.player_kingdom == enemy.kingdom or player.is_mercenary(), "tu reino es ahora el de tu nuevo señor")
	check(scene.result_label.text.contains("Traicionas"), "el cartel cuenta la traición")
	print("  cartel: ", scene.result_label.text.replace("\n", " / ").left(400))

	print("[traición defendiendo el castillo de tu señor]")
	b.is_over = true
	GM.pending_event = {}
	player.role = CH.Role.SOLDADO
	player.honor = 70
	var my_home = MD.get_castle_by_id(GM.home_castle_id)
	my_home.garrison_size = 80
	var att_castle = null
	for id in my_home.connected_castle_ids:
		var c = MD.get_castle_by_id(id)
		if c.kingdom != my_home.kingdom and RD.get_relation(c.owner_name) != null:
			att_castle = c
	if att_castle == null:
		check(true, "(sin vecino de otro reino: se omite)")
	else:
		var assault = _siege(att_castle, my_home, 80)
		AD.active_battle_army = assault
		change_scene_to_file("res://scenes/battle/battle.tscn")
		await create_timer(0.6).timeout
		scene = current_scene
		b = scene.battle
		check(scene.player_defending and not b.has_allies(), "defiendes el castillo de tu señor al mando")
		check(b.units.filter(func(u): return u.own).size() >= 1 and b.units.any(func(u): return b.is_player_unit(u) and not u.own), "tu pelotón es tuyo; el resto, tropa de tu señor")
		var why: String = scene._betrayal_blocker()
		check(why == "", "puedes traicionar a tu señor (%s)" % why)
		if why == "":
			scene._on_betray_pressed()
			scene._on_betray_pressed()
			check(b.player_side == BattleEnums.Side.ATACANTE and b._commander(BattleEnums.Side.DEFENSOR) != player, "te pasas al asaltante y otro toma el mando de la defensa")
			b._end_battle(BattleEnums.Side.ATACANTE, "Prueba: el castillo cae.")
			await create_timer(1.5).timeout
			check(RD.liege_name == att_castle.owner_name or player.is_mercenary(), "juras lealtad al asaltante (%s)" % RD.liege_name)
			check(not scene.result_label.text.contains("Pierdes %d de honor y algo de fama" % AD.DEFEAT_HONOR), "no se te castiga como defensor vencido")

	print("FALLAS: ", fails)
	quit(fails)

func KD_kingdom(r) -> int:
	var cs = RD.castles_of(r.person_name)
	return cs[0].kingdom if not cs.is_empty() else r.kingdom
