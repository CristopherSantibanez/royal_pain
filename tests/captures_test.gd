extends SceneTree
# Capturas: suerte de cada jefe, opciones con tus presos, siervos, presos de la IA (rescates), tu
# cautiverio (rescate, mazmorra, fuga, ejecución), guardado y compañeros elegidos en batalla.

var fails := 0
var GM
var CS
var MD
var AD
var RD
var TD
var KD
var DD
var CL
var CH
var SS

func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok  ", what)
	else:
		fails += 1
		print("  FALLA ", what)

func _initialize() -> void:
	_run.call_deferred()

func _courtier(kingdom: int, role := -1):
	for pass_i in 2:
		for r in RD.courtiers(kingdom if pass_i == 0 else -1) + RD.commoners(kingdom if pass_i == 0 else -1):
			if r.character != null and (role < 0 or r.character.role == role) and not r.person_name in RD.retinue 					and (pass_i == 0 or r.kingdom != GM.player_kingdom or kingdom == GM.player_kingdom):
				return r
	return null

func _lord_other_kingdom():
	for r in RD.lords():
		if r.character != null and not RD.castles_of(r.person_name).is_empty() and KD._kingdom_of(r) != GM.player_kingdom:
			return r
	return null

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

func _run() -> void:
	seed(5)
	GM = root.get_node("GameManager")
	CS = root.get_node("CombatSetup")
	MD = root.get_node("MapData")
	AD = root.get_node("ArmyData")
	RD = root.get_node("RelationsData")
	TD = root.get_node("TravelData")
	KD = root.get_node("CaptureData")
	DD = root.get_node("DynastyData")
	CL = load("res://scripts/resources/character_loader.gd")
	CH = load("res://scripts/resources/character.gd")
	SS = load("res://scripts/resources/save_system.gd")
	var player = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	player.honor = 70
	player.gold = 2000
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame
	GM.pending_event = {}

	print("[suerte de cada jefe al terminar]")
	var bm := BattleManager.new()
	var foe_lord = _lord_other_kingdom()
	var c1 = _courtier(foe_lord.kingdom if foe_lord.kingdom >= 0 else KD._kingdom_of(foe_lord))
	bm.player_leader = player
	var theirs: Array[Character] = []
	if c1 != null:
		theirs.append(c1.character)
	bm.start_battle(100, 100, false, player, foe_lord.character, "el campo", [], theirs)
	var enemy_units = bm.units.filter(func(u): return u.side == BattleEnums.Side.DEFENSOR)
	for u in enemy_units:
		if u.leader() == foe_lord.character:
			u.soldiers = 0
		elif c1 != null and u.leader() == c1.character:
			u.routed = true
	var fates := {}
	for e in bm.capture_fates(BattleEnums.Side.DEFENSOR):
		fates[e[1]] = fates.get(e[1], 0) + 1
	check(fates.has("destroyed"), "pelotón aniquilado → «destroyed» (%s)" % [fates])
	check(c1 == null or fates.has("routed"), "pelotón que huye → «routed»")
	bm.retreating_side = BattleEnums.Side.DEFENSOR
	var after_retreat: Array = bm.capture_fates(BattleEnums.Side.DEFENSOR).filter(func(e): return e[1] == "standing")
	check(after_retreat.is_empty(), "si su bando se retiró a tiempo, nadie queda «standing»")

	# Probabilidad: el jefe del pelotón aniquilado cae preso ~45% de las veces.
	var caught := 0
	var tries := 300
	var destroyed_leader = enemy_units[0].leader()
	for i in tries:
		KD.prisoners.clear()
		var fake := BattleManager.new()
		fake.player_leader = player
		fake.random_conditions = false
		fake.start_battle(60, 60, false, player, foe_lord.character, "el campo", [], [])
		for u in fake.units:
			if u.side == BattleEnums.Side.DEFENSOR:
				u.soldiers = 0
		KD.after_battle(fake, BattleEnums.Side.ATACANTE)
		if KD.is_prisoner(foe_lord.person_name):
			caught += 1
	KD.prisoners.clear()
	var rate := caught / float(tries)
	check(rate > 0.33 and rate < 0.57, "general enemigo aniquilado: preso el %d%% de las veces (≈45%%)" % roundi(rate * 100))

	print("[tus prisioneros: reclutar]")
	var k: int = (GM.player_kingdom + 1) % 6
	var rec = _courtier(k)
	rec.character.personality = CH.Personality.COBARDE
	rec.affection = 40
	check(KD.capture(rec.character, null, true).contains("en tus manos"), "lo capturas")
	check(not RD.sociable(rec) and not rec in RD.courtiers(k), "un preso no aparece en su zona ni se puede tratar")
	var p = KD._find(rec.person_name)
	check(p != null and p.by_player, "aparece entre tus prisioneros")
	var chance: float = KD.recruit_chance(p)
	check(chance > 0.5, "un cobarde que te aprecia acepta a menudo (%d%%)" % roundi(chance * 100))
	var joined := false
	for i in 20:
		p.recruit_month = -1
		var t: String = KD.recruit(p)
		if rec.person_name in RD.retinue:
			joined = true
			break
	check(joined and not KD.is_prisoner(rec.person_name), "acepta servirte y entra en tu séquito")
	check(RD.sociable(rec), "ya se puede tratar")
	var p2 = KD._find(rec.person_name)
	check(p2 == null, "deja de ser preso")

	print("[esclavizar, siervos, vender, liberar]")
	var sl = _courtier(k)
	KD.capture(sl.character, null, true)
	var honor0: int = player.honor
	var lord_k = null
	for r in RD.lords():
		if KD._kingdom_of(r) == k:
			lord_k = r
	var aff0: int = lord_k.affinity if lord_k != null else 0
	var txt: String = KD.enslave(KD._find(sl.person_name))
	check(KD.is_serf(sl.person_name) and sl.person_name in RD.retinue, "pasa a tu séquito como siervo: %s" % txt.left(70))
	check(player.honor == honor0 - KD.ENSLAVE_HONOR, "−%d de honor" % KD.ENSLAVE_HONOR)
	check(lord_k == null or lord_k.affinity < aff0, "su reino se ofende")
	var counts: Dictionary = RD.retinue_counts()
	check(counts.others + counts.intimates == RD.retinue.size() - 1, "el siervo no ocupa plaza")
	check(not sl.character in RD.battle_companions(), "un siervo no va a la batalla")
	check(not sl in RD.occupation_people(), "ni tiene ocupación")
	var greet: String = RD.greeting_line(sl)
	check(not greet.is_empty(), "te saluda como siervo: «%s»" % greet)
	var gold0: int = player.gold
	KD._serfs_month()
	check(player.gold >= gold0 + KD.SERF_GOLD_BASE or not KD.is_serf(sl.person_name), "rinde oro al mes (+%d)" % (player.gold - gold0))
	if KD.is_serf(sl.person_name):
		var price: int = KD.serf_price(sl)
		gold0 = player.gold
		KD.sell_serf(sl.person_name)
		check(player.gold == gold0 + price and RD.get_relation(sl.person_name) == null, "se vende por %d de oro y desaparece" % price)
	var sl2 = _courtier(k)
	KD.capture(sl2.character, null, true)
	KD.enslave(KD._find(sl2.person_name))
	var aff_before: int = sl2.affection
	KD.manumit(sl2.person_name)
	check(not KD.is_serf(sl2.person_name) and sl2.affection > aff_before, "liberar a un siervo: libre y agradecido")

	print("[vender a su facción, liberar, ejecutar]")
	var rs = _courtier(k)
	KD.capture(rs.character, null, true)
	var pr = KD._find(rs.person_name)
	var value: int = KD.ransom_value(pr)
	gold0 = player.gold
	KD.sell_to_faction(pr)
	check(value > 0 and player.gold == gold0 + value and RD.sociable(rs), "su gente paga %d y vuelve" % value)
	var fr = _courtier(k)
	KD.capture(fr.character, null, true)
	honor0 = player.honor
	KD.free_prisoner(KD._find(fr.person_name))
	check(player.honor == mini(100, honor0 + KD.FREE_HONOR) and not KD.is_prisoner(fr.person_name), "liberar da honor")
	var ex = _courtier(k)
	KD.capture(ex.character, null, true)
	honor0 = player.honor
	var ex_name: String = ex.person_name
	KD.execute(KD._find(ex_name))
	check(RD.get_relation(ex_name) == null and player.honor == maxi(0, honor0 - KD.EXECUTE_HONOR), "ejecutar: muere y cuesta %d de honor" % KD.EXECUTE_HONOR)
	var bandit = CL.make_test_character("Bandido Tuerto", CH.Role.SOLDADO)
	KD.capture(bandit, null, true)
	var bp = KD._find(bandit.full_name())
	check(bp != null and bp.temp and not KD.ransom_blocker(bp).is_empty(), "nadie paga por un salteador")
	KD.free_prisoner(bp)
	check(RD.get_relation(bandit.full_name()) == null, "liberado, el salteador desaparece")
	var lord_pr = _lord_other_kingdom()
	KD.capture(lord_pr.character, null, true)
	var lp = KD._find(lord_pr.person_name)
	check(not KD.recruit_blocker(lp).is_empty() and not KD.enslave_blocker(lp).is_empty(), "un señor no se recluta ni se esclaviza")
	var castles_before: Array = RD.castles_of(lord_pr.person_name).map(func(c): return c.castle_id)
	var old_lord: String = lord_pr.person_name
	KD.execute(lp)
	var heir_ok := true
	for cid in castles_before:
		var c = MD.get_castle_by_id(cid)
		heir_ok = heir_ok and c.owner_name != old_lord
	check(heir_ok and not castles_before.is_empty(), "ejecutar a un señor: le sucede un heredero en sus castillos")

	print("[los tuyos, presos de la IA: rescate]")
	var friend = _courtier(GM.player_kingdom, CH.Role.SOLDADO)
	if friend == null:
		friend = _courtier(GM.player_kingdom)
	friend.character.role = CH.Role.SOLDADO
	friend.affection = 90
	RD.retinue.append(friend.person_name)
	var captor = _lord_other_kingdom()
	captor.character.personality = CH.Personality.AMBICIOSO
	KD.capture(friend.character, captor.character, false)
	check(not friend.person_name in RD.retinue and KD.held_own_people().size() == 1, "sale de tu séquito mientras está preso")
	GM.pending_event = {}
	KD._on_month_passed(GM.current_month, GM.current_year)
	var ev: Dictionary = GM.pending_event
	check(ev.get("id", "") == "rescate_de_los_tuyos", "su captor te pide rescate (%s)" % ev.get("text", ""))
	gold0 = player.gold
	GM.resolve_pending_event(0)
	check(friend.person_name in RD.retinue and not KD.is_prisoner(friend.person_name) and player.gold < gold0, "pagas y vuelve a tu séquito")
	KD.capture(friend.character, captor.character, false)
	GM.pending_event = {}
	KD._on_month_passed(GM.current_month, GM.current_year)
	GM.resolve_pending_event(1)
	check(KD._find(friend.person_name).refused, "si te niegas, queda en sus manos")
	for i in KD.AI_MAX_HOLD + 1:
		KD._ai_prisoners_month()
	check(not KD.is_prisoner(friend.person_name), "un captor no cruel lo acaba soltando")
	check(RD.get_relation(friend.person_name) != null, "y vuelve con vida")
	var cruel_capt = CL.make_test_character("Barón Sangriento", CH.Role.NOBLEZA_BAJA)
	cruel_capt.personality = CH.Personality.CRUEL
	var friend2 = _courtier(GM.player_kingdom)
	friend2.character.role = CH.Role.SOLDADO
	RD.retinue.append(friend2.person_name)
	var executed := 0
	var returned := 0
	for i in 40:
		if RD.get_relation(friend2.person_name) == null:
			break
		if not friend2.person_name in RD.retinue:
			RD.retinue.append(friend2.person_name)
		KD.capture(friend2.character, cruel_capt, false)
		var fp = KD._find(friend2.person_name)
		fp.requested = true
		fp.refused = true
		KD._ai_prisoners_month()
		if RD.get_relation(friend2.person_name) == null:
			executed += 1
		elif not KD.is_prisoner(friend2.person_name):
			returned += 1
		else:
			KD._release_record(fp)
	check(executed == 1, "un captor cruel ejecuta a quien no rescatas")

	print("[señores de la IA entre sí]")
	var l1 = _lord_other_kingdom()
	var l2 = null
	for r in RD.lords():
		if r != l1 and r.character != null and not RD.castles_of(r.person_name).is_empty():
			l2 = r
	var got := false
	for i in 60:
		KD.after_auto_battle(l2.person_name, l1.person_name)
		if KD.is_prisoner(l1.person_name):
			got = true
			break
	check(got and not KD._find(l1.person_name).by_player, "el vencido puede caer preso del vencedor")
	for i in KD.AI_MAX_HOLD + 1:
		KD._ai_prisoners_month()
	check(not KD.is_prisoner(l1.person_name), "con los meses se resuelve (rescate, libertad o ejecución)")

	print("[duelos hostiles]")
	var duel_foe = CL.make_test_character("Salteador Duelista", CH.Role.SOLDADO)
	var duel_caught := 0
	for i in 200:
		KD.prisoners.clear()
		if not KD.after_duel(player, player, duel_foe, player, true).is_empty():
			duel_caught += 1
	check(duel_caught > 20 and duel_caught < 70, "vencido en un duelo hostil: preso %d de 200 (≈20%%)" % duel_caught)
	KD.prisoners.clear()
	check(KD.after_duel(player, player, duel_foe, player, false).is_empty(), "un duelo amistoso no hace presos")
	if RD.get_relation(duel_foe.full_name()) != null:
		RD.relations.erase(RD.get_relation(duel_foe.full_name()))

	print("[tu cautiverio: rescate]")
	GM.pending_event = {}
	var my_captor = _lord_other_kingdom()
	my_captor.affinity = 0
	my_captor.character.personality = CH.Personality.AMBICIOSO
	KD.capture_player(my_captor.character, "el campo")
	KD.captivity.decision = "ransom"
	GM.pending_event = KD._captivity_event()
	check(KD.is_captive() and GM.actions_remaining == 0, "preso: sin acciones")
	check(not TD.travel_blocker(MD.castles[1].castle_id).is_empty(), "no puedes viajar")
	check(GM.pending_event.get("id", "") == "cautiverio" and GM.pending_event.options.size() == 2, "evento: pagar o negarte")
	gold0 = player.gold
	var home = MD.get_castle_by_id(GM.home_castle_id)
	var total0: int = player.gold + home.gold
	var ransom: int = KD.captivity.ransom
	GM.resolve_pending_event(0)
	check(not KD.is_captive() and player.gold + home.gold == total0 - ransom, "pagas %d (tu oro y el del castillo) y sales" % ransom)

	print("[mazmorra y fuga]")
	KD.capture_player(my_captor.character, "")
	KD.captivity.decision = "prison"
	GM.pending_event = KD._captivity_event()
	GM.resolve_pending_event(0)
	check(KD.captivity.get("stage", "") == "prison" and int(KD.captivity.months_left) >= KD.PRISON_MIN_MONTHS, "a la mazmorra: %d meses" % int(KD.captivity.get("months_left", 0)))
	var months0: int = KD.captivity.months_left
	GM.pending_event = {}
	GM.advance_turn()
	await process_frame
	check(KD.is_captive() and int(KD.captivity.months_left) == months0 - 1, "cada mes queda uno menos")
	check(GM.pending_event.get("id", "") == "mazmorra" and GM.actions_remaining == 0, "cada mes: fugarte o esperar (sin acciones)")
	player.strategy = 20
	player.combat = 20
	var escaped := false
	for i in 30:
		if not KD.is_captive():
			break
		GM.pending_event = KD._prison_event()
		GM.resolve_pending_event(0)
		if not KD.is_captive():
			escaped = true
	check(escaped and TD.current_castle_id() == GM.home_castle_id, "te fugas y vuelves a casa")
	KD.capture_player(my_captor.character, "")
	KD.captivity.decision = "prison"
	KD._to_prison()
	KD.captivity.months_left = 1
	GM.pending_event = {}
	GM.advance_turn()
	await process_frame
	check(not KD.is_captive(), "cumplida la condena, sales libre")

	print("[guardado]")
	var keep = _courtier(k)
	KD.capture(keep.character, null, true)
	var sv = _courtier(k)
	KD.capture(sv.character, null, true)
	KD.enslave(KD._find(sv.person_name))
	KD.capture_player(my_captor.character, "")
	KD.captivity.decision = "prison"
	KD._to_prison()
	var months_saved: int = KD.captivity.months_left
	GM.pending_event = KD._prison_event()
	check(SS.save_game() == OK and SS.load_game(), "se guarda y se carga")
	check(KD.is_prisoner(keep.person_name) and KD.is_serf(sv.person_name), "presos y siervos sobreviven al guardado")
	check(KD.is_captive() and int(KD.captivity.months_left) == months_saved, "tu cautiverio también")
	KD.load_state({})
	check(KD.prisoners.is_empty() and KD.captivity.is_empty(), "partida antigua: sin presos")
	SS.load_game()
	player = GM.player_character
	KD.captivity = {}
	GM.pending_event = {}

	print("[ejecución: con y sin heredero]")
	KD.capture_player(my_captor.character, "")
	KD.captivity.decision = "execute"
	GM.pending_event = KD._captivity_event()
	GM.resolve_pending_event(1)
	check(DD.needs_succession(), "te ejecutan: hay que elegir heredero o se acaba el linaje")
	check(DD.death_cause().contains("orden de"), "causa: %s" % DD.death_cause())
	check(DD.adult_children().is_empty(), "sin hijos adultos, la sucesión terminará la partida")

	print("[compañeros en batalla]")
	var p2c = CL.make_test_character("Sir Beltrán", CH.Role.SOLDADO)
	GM.start_new_game(p2c, MD.castles[0].castle_id)
	await process_frame
	GM.pending_event = {}
	var a1 = _courtier(GM.player_kingdom)
	var a2 = null
	for r in RD.courtiers(GM.player_kingdom):
		if r != a1 and r.character != null:
			a2 = r
			break
	for r in [a1, a2]:
		r.character.role = CH.Role.SOLDADO
		r.character.wound_months = 0
		r.affection = 90
		RD.retinue.append(r.person_name)
	var pair := _front()
	check(not pair.is_empty(), "hay un frente")
	if pair.is_empty():
		quit(1)
		return
	var target = pair[0]
	var enemy = pair[1]
	target.garrison_size = 80
	TD.location_id = target.castle_id
	var siege = _siege(enemy, target, 70)
	var fight := {"type": "invited", "kind": "army", "army_id": siege.army_id, "side": BattleEnums.Side.DEFENSOR,
		"lord": target.owner_name, "inviter": target.owner_name, "castle_id": target.castle_id}
	change_scene_to_file(CS.begin_event_fight(fight, "Llamada a filas"))
	await create_timer(0.6).timeout
	var scene = current_scene
	var b = scene.battle
	var mine = b.units.filter(func(u): return b.is_player_unit(u))
	var led = mine.filter(func(u): return u.companion != null)
	check(mine.size() == 3 and led.size() == 2, "invitado: tu pelotón y uno por compañero (%d propios, %d con compañero)" % [mine.size(), led.size()])
	check(scene._council != null, "el consejo pregunta quién te acompaña")
	var terrain_before = str(b.terrain)
	scene._excluded.append(a2.person_name)
	scene._restart_battle()
	await process_frame
	b = scene.battle
	mine = b.units.filter(func(u): return b.is_player_unit(u))
	check(mine.size() == 2 and str(b.terrain) == terrain_before, "dejas a uno en casa: 2 pelotones, mismo campo")
	check(not b.units.any(func(u): return u.companion == a2.character), "%s no está en el campo" % a2.person_name)
	# Duelos de jefes: tus compañeros cuentan como tuyos.
	check(b.is_player_unit(mine.filter(func(u): return u.companion != null)[0]), "el pelotón del compañero lo mueves tú")
	scene.queue_free()
	CS.invited = {}
	await process_frame

	print("[campesino invitado con su íntimo]")
	var peas = CL.make_test_character("Juan Labriego", CH.Role.CAMPESINO)
	GM.start_new_game(peas, MD.castles[0].castle_id)
	await process_frame
	GM.pending_event = {}
	var buddy = _courtier(GM.player_kingdom)
	buddy.character.role = CH.Role.SOLDADO
	buddy.character.wound_months = 0
	buddy.affection = 90
	RD.retinue.append(buddy.person_name)
	pair = _front()
	target = pair[0]
	enemy = pair[1]
	TD.location_id = target.castle_id
	siege = _siege(enemy, target, 60)
	fight = {"type": "invited", "kind": "army", "army_id": siege.army_id, "side": BattleEnums.Side.DEFENSOR,
		"lord": target.owner_name, "inviter": target.owner_name, "castle_id": target.castle_id}
	change_scene_to_file(CS.begin_event_fight(fight, "Llamada a filas"))
	await create_timer(0.6).timeout
	scene = current_scene
	b = scene.battle
	mine = b.units.filter(func(u): return b.is_player_unit(u))
	check(mine.size() == 2 and mine.any(func(u): return u.companion == buddy.character), "campesino invitado: su pelotón y el de su íntimo")

	print("FALLAS: ", fails)
	quit(fails)
