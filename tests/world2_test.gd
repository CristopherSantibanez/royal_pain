extends SceneTree
# Mundo 2: nombres por cultura, nombres de reinos, trato con señores (rango y presencia/cartas)
# y piezas únicas. Solo escribe en user://_pruebas.

var fails := 0

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(5)
	var GM = root.get_node("GameManager")
	var MD = root.get_node("MapData")
	var RD = root.get_node("RelationsData")
	var TD = root.get_node("TravelData")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	var NC = load("res://scripts/resources/name_catalog.gd")
	var SS = load("res://scripts/resources/save_system.gd")
	var SE = load("res://scripts/resources/skill_effects.gd")
	var UI = load("res://scripts/resources/unique_items.gd")
	var EC = load("res://scripts/resources/event_catalog.gd")
	var SP = load("res://scripts/ui/shop_panel.gd")
	var DM = load("res://scripts/resources/duel_manager.gd")
	var BM = load("res://scripts/resources/battle_manager.gd")
	var M := CharacterEnums.Gender.MASCULINO
	var F := CharacterEnums.Gender.FEMENINO

	print("[variedad de nombres: 2000 por cultura]")
	for cu in NC.CULTURE_COUNT:
		var names := {}
		var males: int = NC.MALE[cu].size()
		var females: int = NC.FEMALE[cu].size()
		for i in 2000:
			names[NC.full_name(cu, M if i % 2 == 0 else F, [0, 1, 2, 3, 4][i % 5])] = true
		var ratio := names.size() / 2000.0
		print("    %s: %d nombres de varón, %d de mujer · %.0f%% únicos" % [NC.culture_name(cu), males, females, ratio * 100.0])
		check(males >= 55 and females >= 55, "%s: al menos ~60 nombres por sexo" % NC.culture_name(cu))
		check(ratio >= 0.8, "%s: menos de un 20%% de repetidos en 2000" % NC.culture_name(cu))
	check(NC.surname(NC.Culture.ROMANA, F, 0).ends_with("a") or not NC.surname(NC.Culture.ROMANA, F, 0).ends_with("o"), "apellido romano en femenino")
	var fem_ok := true
	for i in 200:
		if NC.first_name(NC.Culture.CASTELLANA, F) in NC.MALE[NC.Culture.CASTELLANA]:
			fem_ok = false
	check(fem_ok, "los nombres de mujer salen de la lista de mujeres")

	print("[mundo: culturas y nombres de reinos]")
	MD.new_world(4242)
	var realm_names := {}
	var lord_names := {}
	var cultures := {}
	for c in MD.castles:
		realm_names[c.castle_name] = true
		if c.owner_name != RD.NO_LORD:
			lord_names[c.owner_name] = true
		check(c.culture >= 0 and c.culture < NC.CULTURE_COUNT, "%s tiene cultura (%s)" % [c.castle_name, NC.culture_name(c.culture)])
		check(KingdomEnums.kingdom_name(c.kingdom) == c.castle_name, "el reino se llama como su castillo: %s" % c.castle_name)
		if c.kingdom != KingdomEnums.Kingdom.NEUTRAL:
			cultures[c.culture] = true
	check(realm_names.size() == MD.castles.size(), "sin nombres de reino repetidos")
	check(cultures.size() >= NC.CULTURE_COUNT, "se usan las %d culturas" % NC.CULTURE_COUNT)
	check(not realm_names.has("Reino Azul"), "ya no salen los nombres fijos")

	var player = CL.make_test_character("Sir Alaric", CH.Role.CABALLERO)
	player.gender = M
	player.honor = 60
	GM.start_new_game(player, MD.castles[0].castle_id)
	await process_frame
	var home = MD.get_castle_by_id(GM.home_castle_id)
	var people := {}
	var dupes := 0
	var culture_ok := 0
	var culture_total := 0
	for r in RD.relations:
		if people.has(r.person_name):
			dupes += 1
		people[r.person_name] = true
		if r.character != null and r.kind != Relationship.Kind.SENOR and r.kingdom >= 0 and r.kingdom != KingdomEnums.Kingdom.NEUTRAL:
			culture_total += 1
			var cu: int = MD.culture_of_kingdom(r.kingdom)
			if r.character.first_name in NC.MALE[cu] or r.character.first_name in NC.FEMALE[cu]:
				culture_ok += 1
	check(dupes == 0, "nadie se llama igual que otro en el mundo (%d repetidos)" % dupes)
	check(culture_total > 0 and culture_ok == culture_total, "la gente lleva nombres de la cultura de su reino (%d/%d)" % [culture_ok, culture_total])
	var sample: Array = []
	for r in RD.people_in_area().slice(0, 5):
		sample.append(r.person_name)
	print("    gente de %s: %s" % [home.castle_name, ", ".join(sample)])

	print("[guardado de culturas y nombres]")
	var names_before := {}
	for c in MD.castles:
		names_before[c.castle_id] = [c.castle_name, c.culture]
	check(SS.save_game() == OK and SS.load_game(), "guardar y cargar")
	var same := true
	for c in MD.castles:
		if names_before[c.castle_id] != [c.castle_name, c.culture] or KingdomEnums.kingdom_name(c.kingdom) != c.castle_name:
			same = false
	check(same, "culturas y nombres de reino sobreviven al guardado")
	# Partida antigua: castillos sin cultura y con los nombres fijos.
	var old_castles: Array[Castle] = []
	for c in MD.castles:
		var o: Castle = c.duplicate()
		o.culture = -1
		o.castle_name = KingdomEnums.default_kingdom_name(o.kingdom)
		old_castles.append(o)
	var saved_castles: Array[Castle] = MD.castles
	MD.castles = old_castles
	check(KingdomEnums.kingdom_name(KingdomEnums.Kingdom.AZUL) == "Reino Azul", "partida antigua: conserva los nombres fijos")
	check(MD.culture_of_kingdom(KingdomEnums.Kingdom.AZUL) >= 0, "partida antigua: cultura por defecto del reino")
	MD.castles = saved_castles
	player = GM.player_character
	home = MD.get_castle_by_id(GM.home_castle_id)

	print("[señores: rango]")
	var far_lord: Relationship = null
	var near_lord: Relationship = null
	for r in RD.lords():
		if RD.lord_present(r):
			near_lord = r
		elif far_lord == null and not RD.castles_of(r.person_name).is_empty():
			far_lord = r
	check(near_lord != null and far_lord != null, "hay un señor aquí y otro lejos")
	GM.actions_remaining = 6
	player.gold = 2000
	player.role = CH.Role.CAMPESINO
	check(not RD.lord_rank_blocker().is_empty(), "un campesino no puede dirigirse a un señor: «%s»" % RD.lord_rank_blocker())
	check(not RD.can_send_gift(near_lord).is_empty() and not RD.can_ask_news(far_lord).is_empty(), "ni presentes ni cartas")
	check(TD.audience_blocker(home) == RD.lord_rank_blocker() or home.owner_name == player.full_name() or TD.lord_relation(home) == null,
		"ni audiencia")
	player.role = CH.Role.SOLDADO
	check(not RD.lord_rank_blocker().is_empty(), "un soldado tampoco")
	player.role = CH.Role.MERCENARIO
	check(RD.lord_rank_blocker().is_empty(), "el mercenario sí (necesita contratos)")
	player.role = CH.Role.CABALLERO

	print("[señores: presencia y cartas]")
	check(RD.letter_extra_actions(near_lord) == 0 and RD.letter_extra_actions(far_lord) == 1, "carta = 1 acción más")
	var acts: int = GM.actions_remaining
	var gold: int = player.gold
	var text: String = RD.send_gift(far_lord)
	check(GM.actions_remaining == acts - 2 and player.gold == gold - RD.GIFT_COST - RD.COURIER_GIFT_COST and text.begins_with("✉"),
		"presentes por carta: 2 acciones y mensajero (%s)" % text.get_slice("\n", 0))
	GM.actions_remaining = 6
	var news: String = RD.ask_news(far_lord)
	check(news.begins_with("✉") and GM.actions_remaining == 4, "noticias por carta")
	check(not RD.can_ask_news(near_lord).is_empty(), "al señor de aquí se le pide audiencia, no carta")
	far_lord.affinity = 90
	check(RD.can_propose_marriage(far_lord).contains("carta"), "una mano no se pide por carta")
	GM.actions_remaining = 1
	check(RD.can_send_gift(far_lord).contains("2 acciones"), "sin acciones para la carta")
	GM.actions_remaining = 6
	var faraway: Relationship = null
	for r in RD.relations:
		if RD.sociable(r) and not RD.in_area(r) and r.kind != Relationship.Kind.CONYUGE:
			faraway = r
			break
	check(faraway != null and not RD.can_interact(faraway, "friendly").is_empty(), "no se conversa con quien está lejos: «%s»" % RD.can_interact(faraway, "friendly"))
	RD.retinue.append(faraway.person_name)
	check(RD.can_interact(faraway, "friendly").is_empty(), "el séquito viaja contigo")
	RD.retinue.erase(faraway.person_name)

	print("[piezas únicas]")
	var uniques: Array = UI.catalog()
	check(uniques.size() >= 12, "%d piezas únicas en el catálogo" % uniques.size())
	var by_id := {}
	for e: Dictionary in load("res://scripts/resources/content_catalog.gd").EQUIPMENT:
		if e.has("unique"):
			by_id[e.unique] = e.name
	# Sello: cartas sin acción extra.
	UI.grant(player, by_id[SE.UNIQUE_SEAL])
	check(SE.has_unique(player, SE.UNIQUE_SEAL) and RD.letter_extra_actions(far_lord) == 0, "Sello del Emperador: cartas sin acción extra")
	# Babieca: el invierno no cuesta más.
	UI.grant(player, by_id[SE.UNIQUE_BABIECA])
	check(TD.hop_cost(1) == TD.HOP_COST, "Babieca: viajar en enero cuesta %d" % TD.hop_cost(1))
	# Capa: la mitad de encuentros.
	var to_id: String = home.connected_castle_ids[0]
	var before: float = TD.encounter_chance(home.castle_id, to_id)
	UI.grant(player, by_id[SE.UNIQUE_SAFE_ROADS])
	check(absf(TD.encounter_chance(home.castle_id, to_id) - before * SE.SAFE_ROADS_FACTOR) < 0.001, "Capa del Peregrino: la mitad de encuentros")
	# Anillo: +15% al conversar.
	var talker: Relationship = RD.people_in_area()[0]
	var chance0: float = RD.converse_chance(talker, "franco")
	UI.grant(player, by_id[SE.UNIQUE_ELOQUENCE])
	check(RD.converse_chance(talker, "franco") > chance0, "Anillo de Teodolinda: más éxito al conversar (%.2f → %.2f)" % [chance0, RD.converse_chance(talker, "franco")])
	# Relicario: las heridas graves sanan al mes.
	UI.grant(player, by_id[SE.UNIQUE_RELIC])
	player.wound_months = 3
	player.monthly_recovery()
	check(player.wound_months == 0, "Relicario de Aquisgrán: heridas curadas en un mes")
	check(player.equipment.size() <= GameData.MAX_EQUIPMENT, "nunca más de %d piezas (%d)" % [GameData.MAX_EQUIPMENT, player.equipment.size()])

	# Duelo: Durandal, sangrado, anticrítico, reflejo y firmeza.
	var a = CL.make_test_character("Atacante", CH.Role.CABALLERO)
	var d = CL.make_test_character("Defensor", CH.Role.CABALLERO)
	a.combat = 10
	d.combat = 10
	d.defense = 8
	UI.grant(a, by_id[SE.UNIQUE_DURANDAL])
	var landed := 0
	for i in 100:
		var dm = DM.new()
		a.current_health = a.max_health
		d.current_health = d.max_health
		dm.start_duel(a, d)
		dm.countering[d] = true
		dm.dodging[d] = true
		var hp: int = d.current_health
		dm._do_attack(a, d)
		if d.current_health < hp:
			landed += 1
	check(landed == 100, "Durandal: el primer ataque siempre entra (%d/100)" % landed)
	var dm2 = DM.new()
	dm2.start_duel(a, d)
	dm2.unique_spent[a][SE.UNIQUE_DURANDAL] = true
	var parried := 0
	for i in 60:
		dm2.countering[d] = true
		var hp2: int = d.current_health
		d.current_health = d.max_health
		dm2._do_attack(a, d)
		if d.current_health == d.max_health:
			parried += 1
	check(parried > 0, "Durandal: el resto de ataques sí se pueden parar (%d paradas)" % parried)

	var b2 = CL.make_test_character("Sangrador", CH.Role.CABALLERO)
	UI.grant(b2, by_id[SE.UNIQUE_BLEED])
	var dm3 = DM.new()
	d.current_health = d.max_health
	dm3.start_duel(b2, d)
	dm3._do_attack(b2, d)
	check(dm3.bleeding[d] == SE.BLEED_TURNS, "Misericordia: el golpe hace sangrar")
	var hp3: int = d.current_health
	dm3.take_turn(d, CombatEnums.ActionType.DEFENDER)
	check(d.current_health == hp3 - SE.BLEED_DAMAGE and dm3.bleeding[d] == SE.BLEED_TURNS - 1, "la herida sangra al empezar su turno")

	var crit_plain := 0
	var crit_ward := 0
	var plain = CL.make_test_character("Sin loriga", CH.Role.CABALLERO)
	var ward = CL.make_test_character("Con loriga", CH.Role.CABALLERO)
	UI.grant(ward, by_id[SE.UNIQUE_CRIT_WARD])
	for target in [plain, ward]:
		for i in 400:
			var dm4 = DM.new()
			target.current_health = target.max_health
			var crits := [0]
			dm4.combat_event.connect(func(kind, _x, _y, _z): if kind == "crit": crits[0] += 1)
			dm4.start_duel(a, target)
			dm4.unique_spent[a][SE.UNIQUE_DURANDAL] = true
			dm4._do_attack(a, target)
			if target == plain:
				crit_plain += crits[0]
			else:
				crit_ward += crits[0]
	check(crit_plain > 0 and crit_ward == 0, "Loriga: el primer crítico de cada duelo se anula (%d críticos sin ella, %d con ella)" % [crit_plain, crit_ward])

	var shield = CL.make_test_character("Escudado", CH.Role.CABALLERO)
	UI.grant(shield, by_id[SE.UNIQUE_REFLECT])
	var hit = CL.make_test_character("Golpeador", CH.Role.CABALLERO)
	var dm5 = DM.new()
	dm5.start_duel(hit, shield)
	var hit_hp: int = hit.current_health
	dm5._do_attack(hit, shield)
	check(hit.current_health < hit_hp, "Escudo de Teodorico: devuelve parte del daño (%d)" % (hit_hp - hit.current_health))

	var steady = CL.make_test_character("Firme", CH.Role.CABALLERO)
	UI.grant(steady, by_id[SE.UNIQUE_STEADY])
	var pusher = CL.make_test_character("Empujador", CH.Role.CABALLERO)
	pusher.combat = 20
	var unbalanced_seen := false
	for i in 30:
		var dm6 = DM.new()
		dm6.start_duel(pusher, steady)
		dm6._do_push(pusher, steady)
		if dm6.unbalanced[steady] or dm6.advantage[pusher] == DM.ADV_DESEQUILIBRIO:
			unbalanced_seen = true
	check(not unbalanced_seen, "Yelmo de Sutton Hoo: nunca queda desequilibrado")

	# Batalla: Oriflama y Olifante.
	var knight_a = CL.make_test_character("Portaestandarte", CH.Role.NOBLEZA_ALTA)
	UI.grant(knight_a, by_id[SE.UNIQUE_ORIFLAMMA])
	var knight_b = CL.make_test_character("Rival", CH.Role.NOBLEZA_ALTA)
	var bm = BM.new()
	bm.start_battle(80, 60, false, knight_a, knight_b, "Prueba")
	var mine: Array = bm.units.filter(func(u): return u.side == BattleEnums.Side.ATACANTE and not u.routed)
	mine[0].morale = 1
	bm._check_rout(mine[0])
	mine[1].morale = 1
	bm._check_rout(mine[1])
	check(not mine[0].routed and mine[1].routed, "Oriflama: el primer pelotón que huiría resiste; el segundo no")
	var horn = CL.make_test_character("Trompetero", CH.Role.NOBLEZA_ALTA)
	UI.grant(horn, by_id[SE.UNIQUE_OLIFANT])
	bm._used_abilities[horn] = 1
	bm._used_abilities[knight_b] = 1
	check(not bm.ability_used_by(horn) and bm.ability_used_by(knight_b), "Olifante: una habilidad de mando más")

	print("[de dónde salen]")
	var npc_uniques := 0
	for i in 500:
		var npc = CL.make_random_character(CH.Role.NOBLEZA_BAJA, M)
		if UI.carried_by(npc) != null:
			npc_uniques += 1
	print("    PNJ nobles con pieza única: %d de 500" % npc_uniques)
	check(npc_uniques > 5 and npc_uniques < 80, "algunos PNJ, raros, llevan una pieza única")
	home.buildings["herreria"] = 2
	check(SP.monthly_forge(home.castle_id) == null, "sin forja con herrería de nivel 2")
	home.buildings["herreria"] = 3
	var forged = SP.monthly_forge(home.castle_id)
	check(forged != null and SE.is_unique_item(forged), "la herrería de nivel 3 forja: %s" % (forged.equipment_name if forged != null else "nada"))
	var hunter = CL.make_test_character("Explorador", CH.Role.CABALLERO)
	var found: String = EC._apply_effects({"unique": 100}, hunter, home)
	check(UI.carried_by(hunter) != null, "efecto de evento «unique»: %s" % found.left(60))
	# Trofeo de duelo.
	var loser_rel: Relationship = RD.people_in_area()[1]
	UI.grant(loser_rel.character, by_id[SE.UNIQUE_DURANDAL])
	var honor0: int = player.honor
	var grudge0: int = loser_rel.grudge
	var trophy: String = UI.claim_trophy(player, loser_rel.character)
	check(SE.has_unique(player, SE.UNIQUE_DURANDAL) and UI.carried_by(loser_rel.character) == null, "trofeo: la pieza cambia de manos")
	check(player.honor == honor0 - UI.TROPHY_HONOR_COST and loser_rel.grudge == grudge0 + UI.TROPHY_GRUDGE, "trofeo: −%d de honor y +%d de rencor" % [UI.TROPHY_HONOR_COST, UI.TROPHY_GRUDGE])

	print("[guardado de piezas únicas]")
	var held: Array = player.equipment.filter(func(e): return SE.is_unique_item(e)).map(func(e): return e.equipment_name)
	check(SS.save_game() == OK and SS.load_game(), "guardar y cargar")
	var after: Array = GM.player_character.equipment.filter(func(e): return SE.is_unique_item(e)).map(func(e): return e.equipment_name)
	check(held == after and not held.is_empty(), "las piezas únicas se conservan: %s" % ", ".join(after))
	check(SE.has_unique(GM.player_character, SE.UNIQUE_DURANDAL), "y siguen funcionando tras cargar")

	print("RESULTADO: %d FALLAS" % fails)
	quit(fails)
