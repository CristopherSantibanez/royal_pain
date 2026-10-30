extends SceneTree
# Reglas de creación: atributo Agilidad (ficha, PNJ, guardado, combate RPG), rasgos (máx. 2 ventajas,
# mín. 2 desventajas, fijos en partida), equipo inicial (arma/escudo/armadura/accesorio),
# 9 habilidades básicas (3 árboles × 3 ramas) y puntos de habilidad cada 3 niveles.

var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FALLA ") + msg)
	if not ok:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _item(n: String) -> Equipment:
	for e: Equipment in root.get_node("GameData").equipment_catalog:
		if e.equipment_name == n:
			return e
	return null

func _run() -> void:
	var GD = root.get_node("GameData")
	var CC = load("res://scripts/resources/content_catalog.gd")
	var DC = load("res://scripts/resources/data_codec.gd")
	var CL = load("res://scripts/resources/character_loader.gd")
	var RS = load("res://scripts/resources/rpg_stats.gd")
	var TREES: Script = load("res://scripts/resources/skill_tree_catalog.gd")

	print("[agilidad]")
	check("agility" in Character.ATTRIBUTES and Character.ATTRIBUTES.size() == 6, "seis atributos")
	var old := Character.new()
	old.combat = 9; old.strategy = 5
	check(old.agility == 7, "dato antiguo sin agilidad: se deriva (%d)" % old.agility)
	var base: Dictionary = GD.get_base_stats(Character.Personality.COBARDE, CharacterEnums.Alignment.PACIFISTA, CharacterEnums.FighterType.ASESINO)
	check(base.get("agility", 0) == 5 + 2 + 1 + 2, "mods de personalidad/alineación/tipo suman agilidad (%d)" % base.get("agility", 0))
	var pa = load("res://scripts/resources/point_allocator.gd").new()
	pa.setup(0, 0, 0)
	pa.increase("agility")
	var pc := Character.new()
	pa.apply_to_character(pc)
	check(pc.agility == pa.current_value("agility") and pc.agility >= 6, "el reparto asigna agilidad")
	var npc: Character = CL.make_random_character(Character.Role.CABALLERO, 0)
	var raw: Dictionary = DC.encode(npc)
	check(raw.has("agility") and int(raw.agility) >= 1, "PNJ con agilidad propia y se guarda")
	var back: Character = DC.from_json(DC.to_json(npc))
	check(back.agility == npc.agility, "ida y vuelta conserva la agilidad")
	check(npc.advantages.size() <= Character.MAX_ADVANTAGES and npc.disadvantages.size() >= Character.MIN_DISADVANTAGES, "PNJ: ≤2 ventajas, ≥2 desventajas")
	check(DC.decode({"_type": "Character", "first_name": "Vieja", "combat": 8, "strategy": 6}).agility == 7, "partida antigua no rompe")

	print("[combate RPG]")
	var f := Character.new()
	f.agility = 6
	f.equipment.append(_item("Ropas de Viaje"))
	var a_light: float = RS.compute(f).agilidad
	f.agility = 14
	var a_fast: float = RS.compute(f).agilidad
	check(a_fast > a_light, "más Agilidad → más agilidad RPG (%.1f > %.1f)" % [a_fast, a_light])
	f.equipment.clear(); f.equipment.append(_item("Peto de Placas"))
	var a_heavy: float = RS.compute(f).agilidad
	check(a_heavy < a_fast and RS.armor_class(f) == RS.ArmorClass.PLACAS, "las placas pesan (%.1f < %.1f)" % [a_heavy, a_fast])
	f.combat = 15; f.strategy = 15
	check(is_equal_approx(RS.compute(f).agilidad, a_heavy), "Combate/Estrategia ya no dan agilidad")

	print("[creación]")
	var c := Character.new()
	c.first_name = "Prueba"
	c.traits_locked = false
	var weapon := _item(CC.CREATION_WEAPONS["Contundente"])
	check(weapon != null and RS.WEAPON_BY_ITEM.get(weapon.equipment_name) == RS.DamageType.CONTUNDENTE, "arma básica contundente")
	check(CC.CREATION_ACCESSORIES.size() == 6 and _item(CC.CREATION_ACCESSORIES["agility"]).agility_mod == 1, "6 accesorios (+1 cada atributo)")
	c.equipment.append(weapon)
	c.equipment.append(_item(CC.CREATION_ARMORS["Malla"]))
	check(not c.creation_equipment_errors().is_empty(), "sin accesorio: inválido")
	c.equipment.append(_item(CC.CREATION_ACCESSORIES["charisma"]))
	check(c.creation_equipment_errors().is_empty(), "arma + armadura + accesorio: válido")
	c.equipment.append(_item("Rodela"))
	check(c.creation_equipment_errors().is_empty(), "con escudo: válido")
	c.equipment.append(_item("Escudo Redondo"))
	check(not c.creation_equipment_errors().is_empty(), "dos escudos: inválido")
	c.equipment.pop_back()
	c.equipment.append(_item("Espada Larga"))
	check(not c.creation_equipment_errors().is_empty(), "pieza no básica: inválida")
	c.equipment.pop_back()
	for t in GD.advantages.slice(0, 3):
		c.add_trait(t)
	c.add_trait(GD.disadvantages[0])
	var errs: Array = c.is_creation_valid().errors
	check(errs.any(func(e): return "ventajas" in e) and errs.any(func(e): return "desventajas" in e), "3 ventajas y 1 desventaja: inválido")
	c.remove_trait(GD.advantages[2])
	c.add_trait(GD.disadvantages[1])
	errs = c.is_creation_valid().errors
	check(not errs.any(func(e): return "ventajas" in e), "2 ventajas y 2 desventajas: válido")
	if Character.tree_api_ready(TREES):
		check(not c.creation_skill_errors().is_empty(), "sin básicas: inválido")
		var opts: Array = c.basic_tree_options()
		check(opts.size() == 9, "9 ramas (3 árboles × 3)")
		for o in opts:
			c.choose_basic(o, str(o.ids[0]))
		check(c.creation_skill_errors().is_empty() and c.is_creation_valid().valid, "9 básicas: personaje válido")
		c.choose_basic(opts[0], str(opts[0].ids[-1]))
		check(c.creation_skill_errors().is_empty(), "cambiar la básica de una rama mantiene una por rama")
	else:
		print("  (árboles sin API nueva: se omite la comprobación de las 9 básicas)")
		check(c.is_creation_valid().valid, "personaje válido")
	c.traits_locked = true
	var n := c.advantages.size()
	check(not c.add_trait(GD.advantages[5]) and not c.remove_trait(c.advantages[0]) and c.advantages.size() == n, "en partida los rasgos no cambian")
	check(Character.new().traits_locked, "por defecto, rasgos fijos")

	print("[puntos de habilidad]")
	var pts := []
	for lv in range(2, 11):
		pts.append(Character.tree_points_at(lv))
	check(pts == [0, 1, 0, 0, 1, 0, 0, 1, 0], "un punto cada 3 niveles %s" % str(pts))
	var hero := Character.new()
	hero.gain_xp(100 + 200)
	check(hero.level == 3 and hero.pending_skill_choices == 0 and hero.unspent_points == 4, "nivel 3: 4 puntos de atributo, sin elección antigua")

	print("FALLAS: %d" % fails)
	quit()
