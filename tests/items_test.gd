extends SceneTree
# Consumibles del combate RPG: tienda, efectos en combate, turno gastado, botín, IA y guardado de la bolsa.

var fails := 0

func check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLA ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _char(ft: int, lvl: int = 3) -> Character:
	var c := Character.new()
	c.first_name = "P%d" % randi()
	c.fighter_type = ft
	c.level = lvl
	for k in ["combat", "defense", "strategy", "leadership", "charisma", "agility"]:
		c.set(k, 8)
	return c

## Combate 2 contra 2 con la bolsa dada, avanzado hasta el turno de alguien del bando 0.
func _battle(bag: Dictionary, enemy_bag: Dictionary = {}) -> RpgBattleManager:
	var F := CharacterEnums.FighterType
	var bm := RpgBattleManager.new()
	bm.setup([_char(F.DUELISTA), _char(F.TANQUE)], [_char(F.BERSERKER), _char(F.DEFENSOR)], {"seed": 5, "bag": bag, "enemy_bag": enemy_bag})
	var f := bm.next_turn()
	while f != null and f.side != 0:
		bm.act(f, {"type": "defender"})
		f = bm.next_turn()
	return bm

func _use(id: String, prep: Callable, verify: Callable, to_enemy := false) -> void:
	var bag := {id: 2}
	var bm := _battle(bag)
	var f: RpgBattleManager.Fighter = bm.current
	var t: RpgBattleManager.Fighter = bm.active_of(1)[0] if to_enemy else f
	prep.call(bm, t)
	bm.act(f, {"type": "objeto", "item": id, "target": t})
	check(bag.get(id, 0) == 1 and bm.current != f and verify.call(bm, t), "%s: efecto, gasta 1 y el turno" % ConsumableCatalog.item_name(id))

func _run() -> void:
	seed(11)
	print("[catálogo y tienda]")
	check(ConsumableCatalog.ITEMS.size() == 10, "10 consumibles")
	check(not "humo" in ConsumableCatalog.shop_items(0) and "humo" in ConsumableCatalog.shop_items(2), "el Mercado desbloquea más objetos")
	var GM = root.get_node("GameManager")
	var CL = load("res://scripts/resources/character_loader.gd")
	var player = CL.make_test_character("Sir Prueba", Character.Role.CABALLERO)
	player.gold = 500
	GM.start_new_game(player, root.get_node("MapData").castles[0].castle_id)
	var shop = load("res://scripts/ui/shop_panel.gd").open(root)
	await process_frame
	shop._set_tab("consumibles")
	var gold0: int = player.gold
	check(shop.buy_consumable("venda") and player.consumables.get("venda", 0) == 1 and player.gold < gold0, "comprar una Venda en la tienda")
	for i in 6:
		shop.buy_consumable("venda")
	check(player.consumables.venda == ConsumableCatalog.MAX_STACK, "tope por objeto (%d)" % ConsumableCatalog.MAX_STACK)
	shop.queue_free()

	print("[efectos en combate]")
	_use("venda", func(_bm, t): t.hp = t.max_hp / 2, func(_bm, t): return t.hp > t.max_hp / 2)
	_use("unguento", func(bm, t): t.hp = t.max_hp / 2; bm._add_status(t, "sangrado", 3, null),
		func(_bm, t): return t.hp > t.max_hp / 2 and not t.has("sangrado"))
	_use("pan_vino", func(_bm, t): t.pt = 0, func(_bm, t): return t.pt > 0)
	_use("cerveza", func(bm, t): t.morale = 40, func(_bm, t): return t.morale > 40 and t.has("ebrio"))
	_use("aceite", func(_bm, _t): pass, func(_bm, t): return t.hp < t.max_hp and t.has("ardiendo"), true)
	_use("piedra", func(_bm, _t): pass, func(_bm, t): return t.has("afilado"))
	_use("agua_bendita", func(bm, t): bm._add_status(t, "aturdido", 2, null), func(_bm, t): return not t.has("aturdido"))
	_use("humo", func(_bm, _t): pass, func(bm, _t): return bm.active_of(0).all(func(o): return o.has("humo")))
	_use("red", func(_bm, _t): pass, func(_bm, _t): return true, true)
	_use("hierbas", func(bm, t): bm._add_status(t, "debilitado", 3, null), func(_bm, t): return not t.has("debilitado"))
	# Afilado y ebrio cambian daño y puntería; el humo, la evasión.
	var bm := _battle({})
	var a: RpgBattleManager.Fighter = bm.current
	var e: RpgBattleManager.Fighter = bm.active_of(1)[0]
	var d0 := bm.base_damage(a, e, 1.0, int(a.s.weapon))
	var h0 := bm.hit_chance(a, e)
	var he0 := bm.hit_chance(e, a)
	bm._add_status(a, "afilado", 2, null)
	bm._add_status(a, "ebrio", 2, null)
	bm._add_status(a, "humo", 2, null)
	check(bm.base_damage(a, e, 1.0, int(a.s.weapon)) > d0 and bm.hit_chance(a, e) < h0 and bm.hit_chance(e, a) <= he0, "Afilado sube el daño, Ebrio baja la puntería, Humo la evasión")
	var nets := 0
	for i in 12:
		var bag := {"red": 1}
		var b2 := _battle(bag)
		b2.rng.seed = i
		var tgt: RpgBattleManager.Fighter = b2.active_of(1)[0]
		b2.act(b2.current, {"type": "objeto", "item": "red", "target": tgt})
		nets += 1 if tgt.has("derribado") else 0
	check(nets >= 6, "la Red de caza derriba a menudo (%d/12)" % nets)
	var empty := _battle({})
	var cur := empty.current
	empty.act(cur, {"type": "objeto", "item": "venda", "target": cur})
	check(empty.current == cur and cur.actions_left > 0, "sin el objeto no se gasta el turno")

	print("[IA, botín y guardado]")
	var used := false
	for i in 30:
		var b3 := _battle({}, {"venda": 1})
		var foe: RpgBattleManager.Fighter = b3.active_of(1)[0]
		foe.hp = 1
		b3.rng.seed = i
		if b3.ai_choose(foe).get("type", "") == "objeto":
			used = true
			break
	check(used, "la IA rival usa un objeto a veces")
	var loot_bag := {}
	var got := false
	for i in 20:
		var r := {"loot": []}
		ConsumableCatalog.grant_loot(loot_bag, r)
		if not r.loot.is_empty():
			got = true
			break
	check(got and not loot_bag.is_empty(), "ganar da botín de consumibles")
	var b4 := RpgBattleManager.new()
	var F := CharacterEnums.FighterType
	var hooked := []
	b4.setup([_char(F.DUELISTA, 10)], [_char(F.DUELISTA, 1)], {"seed": 1, "loot_hook": func(r): hooked.append(r.loot)})
	b4.run_auto()
	check(b4.result.winner != 0 or hooked.size() == 1, "el gancho de botín se llama al ganar")
	player.consumables = {}
	var txt: String = load("res://scripts/resources/event_catalog.gd")._apply_effects({"consumable": 2}, player, null)
	check(txt.begins_with("Consigues") and not player.consumables.is_empty(), "un suceso da consumibles (%s)" % txt)
	player.consumables = {"aceite": 2, "red": 1}
	var DC = load("res://scripts/resources/data_codec.gd")
	var back: Character = DC.from_json(DC.to_json(player))
	check(back != null and int(back.consumables.get("aceite", 0)) == 2 and int(back.consumables.get("red", 0)) == 1, "la bolsa se guarda y se carga")
	var old: Character = DC.from_json(DC.to_json(_char(F.DUELISTA)))
	check(old.consumables.is_empty(), "personaje sin bolsa: vacía")
	print("FALLAS: %d" % fails if fails else "TODO OK")
	quit()
