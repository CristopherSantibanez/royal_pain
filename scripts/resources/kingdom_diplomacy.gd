class_name KingdomDiplomacy
# Diplomacia entre los reinos de la IA (guerras, paces, alianzas) y rebeliones en castillos
# conquistados por el jugador. Lógica pura: recibe el estado y lo modifica; no referencia autoloads.
#
# Estado (lo guarda RelationsData):
#   wars:      {"a|b": mes_en_que_empezó}   (a < b, ids de KingdomEnums.Kingdom)
#   alliances: {"a|b": true}

# --- Balance (ajustables sin tocar la lógica) ---
const WAR_CHANCE := 0.04          # por reino y mes, de declarar la guerra a un vecino
const PEACE_CHANCE := 0.12        # por guerra y mes, una vez cumplida la duración mínima
const MIN_WAR_MONTHS := 6
const ALLIANCE_CHANCE := 0.02     # por reino y mes, de aliarse con un vecino en paz
const MAX_WARS_PER_KINGDOM := 2
const REBELLION_BASE := 0.03
const REBELLION_LOW_HONOR := 40       # por debajo, más rebeliones
const REBELLION_LOW_HONOR_BONUS := 0.05
const REBELLION_WEAK_GARRISON := 30   # por debajo, más rebeliones
const REBELLION_WEAK_GARRISON_BONUS := 0.05
const REBELLION_TREGUA_FACTOR := 0.5  # la Tregua del Rey reduce a la mitad el riesgo
const REBEL_GARRISON_FACTOR := 0.5    # la guarnición se divide: la mitad se pasa a los rebeldes

static func pair_key(a: int, b: int) -> String:
	return "%d|%d" % [mini(a, b), maxi(a, b)]

static func at_war(wars: Dictionary, a: int, b: int) -> bool:
	return wars.has(pair_key(a, b))

static func allied(alliances: Dictionary, a: int, b: int) -> bool:
	return alliances.has(pair_key(a, b))

static func declare_war(wars: Dictionary, alliances: Dictionary, a: int, b: int, month: int) -> bool:
	if a == b or at_war(wars, a, b):
		return false
	alliances.erase(pair_key(a, b))
	wars[pair_key(a, b)] = month
	return true

# Reinos vivos (con al menos un castillo) y sus vecinos según las rutas.
static func kingdom_neighbors(castles: Array[Castle]) -> Dictionary:
	var by_id := {}
	for c: Castle in castles:
		by_id[c.castle_id] = c
	var result := {}
	for c: Castle in castles:
		if not result.has(c.kingdom):
			result[c.kingdom] = []
		for n_id in c.connected_castle_ids:
			var n: Castle = by_id.get(n_id)
			if n != null and n.kingdom != c.kingdom and not n.kingdom in result[c.kingdom]:
				result[c.kingdom].append(n.kingdom)
	return result

static func _kingdom_strength(castles: Array[Castle], kingdom: int) -> int:
	var total := 0
	for c: Castle in castles:
		if c.kingdom == kingdom:
			total += c.garrison_size
	return total

static func _wars_of(wars: Dictionary, kingdom: int) -> int:
	var n := 0
	for key: String in wars.keys():
		var parts := key.split("|")
		if int(parts[0]) == kingdom or int(parts[1]) == kingdom:
			n += 1
	return n

# Actualización mensual. Devuelve noticias [{text, castle_id}] (castle_id: un castillo del reino que actúa).
static func monthly_update(castles: Array[Castle], wars: Dictionary, alliances: Dictionary,
		month: int, player_kingdom: int) -> Array[Dictionary]:
	var news: Array[Dictionary] = []
	var neighbors := kingdom_neighbors(castles)
	var a_castle := {}
	for c: Castle in castles:
		if not a_castle.has(c.kingdom):
			a_castle[c.kingdom] = c.castle_id

	# Guerras que terminan (o que pierden sentido porque un reino desapareció).
	for key: String in wars.keys().duplicate():
		var parts := key.split("|")
		var a := int(parts[0])
		var b := int(parts[1])
		if not neighbors.has(a) or not neighbors.has(b):
			wars.erase(key)
			continue
		if month - int(wars[key]) >= MIN_WAR_MONTHS and randf() < PEACE_CHANCE:
			wars.erase(key)
			news.append({"text": "%s y %s firman la paz." % [KingdomEnums.kingdom_name(a), KingdomEnums.kingdom_name(b)],
				"castle_id": a_castle.get(a, "")})

	# Nuevas guerras y alianzas. El reino del jugador no participa: su diplomacia la decide él.
	for k in neighbors.keys():
		if k == player_kingdom or k == KingdomEnums.Kingdom.NEUTRAL:
			continue
		var options: Array = neighbors[k].filter(func(o): return o != player_kingdom)
		if options.is_empty():
			continue
		if randf() < WAR_CHANCE and _wars_of(wars, k) < MAX_WARS_PER_KINGDOM:
			# Prefiere al vecino más débil con el que no tenga alianza ni guerra.
			var targets: Array = options.filter(func(o): return not allied(alliances, k, o) and not at_war(wars, k, o))
			if not targets.is_empty():
				targets.sort_custom(func(x, y): return _kingdom_strength(castles, x) < _kingdom_strength(castles, y))
				var t: int = targets[0]
				declare_war(wars, alliances, k, t, month)
				news.append({"text": "%s declara la guerra a %s." % [KingdomEnums.kingdom_name(k), KingdomEnums.kingdom_name(t)],
					"castle_id": a_castle.get(k, "")})
		elif randf() < ALLIANCE_CHANCE:
			var friends: Array = options.filter(func(o): return not allied(alliances, k, o) and not at_war(wars, k, o) and o != KingdomEnums.Kingdom.NEUTRAL)
			if not friends.is_empty():
				var f: int = friends.pick_random()
				alliances[pair_key(k, f)] = true
				news.append({"text": "%s y %s sellan una alianza." % [KingdomEnums.kingdom_name(k), KingdomEnums.kingdom_name(f)],
					"castle_id": a_castle.get(k, "")})
	return news

# --- Rebeliones en castillos conquistados por el jugador ---

static func rebellion_chance(player_honor: int, garrison: int, tregua_active: bool) -> float:
	var chance := REBELLION_BASE
	if player_honor < REBELLION_LOW_HONOR:
		chance += REBELLION_LOW_HONOR_BONUS
	if garrison < REBELLION_WEAK_GARRISON:
		chance += REBELLION_WEAK_GARRISON_BONUS
	if tregua_active:
		chance *= REBELLION_TREGUA_FACTOR
	return chance
