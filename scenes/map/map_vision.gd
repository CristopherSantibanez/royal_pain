class_name MapVision

# La visión crece con el rango (nunca se pierde al ascender) y siempre incluye los castillos propios.
const ROLE_HOPS := {
	Character.Role.CAMPESINO: 0, Character.Role.SOLDADO: 1, Character.Role.CABALLERO: 2,
	Character.Role.NOBLEZA_BAJA: 2, Character.Role.NOBLEZA_ALTA: 3,
}

## bonus: saltos de visión extra (rasgos y habilidades, ver SkillEffects.vision_bonus).
static func get_visible_castle_ids(role: int, home_castle_id: String, bonus: int = 0) -> Array[String]:
	var ids := _role_visible_castle_ids(role, home_castle_id)
	if bonus > 0 and ROLE_HOPS.has(role):
		ids = _union(ids, _bfs_within_hops(home_castle_id, ROLE_HOPS[role] + bonus))
	return ids

static func _role_visible_castle_ids(role: int, home_castle_id: String) -> Array[String]:
	var home := MapData.get_castle_by_id(home_castle_id)
	if home == null:
		return []

	var ids: Array[String] = []
	match role:
		Character.Role.CAMPESINO:
			ids = [home_castle_id]
		Character.Role.SOLDADO:
			ids = _bfs_within_hops(home_castle_id, 1)
		Character.Role.CABALLERO:
			ids = _bfs_within_hops(home_castle_id, 2)
		Character.Role.NOBLEZA_BAJA:
			ids = _union(_castles_in_kingdom(home.kingdom), _bfs_within_hops(home_castle_id, 2))
		Character.Role.NOBLEZA_ALTA:
			ids = _union(_kingdom_and_neighbors(home.kingdom), _bfs_within_hops(home_castle_id, 3))
			ids = _union(ids, _castles_of_kingdoms(RelationsData.allied_kingdoms()))
		Character.Role.REGENTE:
			return _all_castle_ids()
		_:
			ids = [home_castle_id]
	return _union(ids, _player_owned_castles())

static func _union(a: Array[String], b: Array[String]) -> Array[String]:
	var result: Array[String] = a.duplicate()
	for id in b:
		if not id in result:
			result.append(id)
	return result

static func _player_owned_castles() -> Array[String]:
	var ids: Array[String] = []
	var player: Character = GameManager.player_character
	if player == null:
		return ids
	for c: Castle in MapData.castles:
		if c.owner_name == player.full_name():
			ids.append(c.castle_id)
	return ids

static func _castles_of_kingdoms(kingdoms: Array) -> Array[String]:
	var ids: Array[String] = []
	for c: Castle in MapData.castles:
		if c.kingdom in kingdoms:
			ids.append(c.castle_id)
	return ids

static func _all_castle_ids() -> Array[String]:
	var ids: Array[String] = []
	for c: Castle in MapData.castles:
		ids.append(c.castle_id)
	return ids

static func _castles_in_kingdom(kingdom: int) -> Array[String]:
	var ids: Array[String] = []
	for c: Castle in MapData.castles:
		if c.kingdom == kingdom:
			ids.append(c.castle_id)
	return ids

static func _kingdom_and_neighbors(kingdom: int) -> Array[String]:
	var kingdoms: Dictionary = {kingdom: true}
	for c: Castle in MapData.castles:
		if c.kingdom == kingdom:
			for neighbor_id in c.connected_castle_ids:
				var neighbor := MapData.get_castle_by_id(neighbor_id)
				if neighbor != null:
					kingdoms[neighbor.kingdom] = true

	var ids: Array[String] = []
	for c: Castle in MapData.castles:
		if kingdoms.has(c.kingdom):
			ids.append(c.castle_id)
	return ids

static func _bfs_within_hops(start_id: String, max_hops: int) -> Array[String]:
	var visited: Dictionary = {start_id: true}
	var frontier: Array[String] = [start_id]

	for hop in range(max_hops):
		var next_frontier: Array[String] = []
		for id in frontier:
			var c := MapData.get_castle_by_id(id)
			if c == null:
				continue
			for neighbor_id in c.connected_castle_ids:
				if not visited.has(neighbor_id):
					visited[neighbor_id] = true
					next_frontier.append(neighbor_id)
		frontier = next_frontier

	var result: Array[String] = []
	for id in visited.keys():
		result.append(id)
	return result
