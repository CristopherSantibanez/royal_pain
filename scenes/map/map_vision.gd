class_name MapVision

static func get_visible_castle_ids(role: int, home_castle_id: String) -> Array[String]:
	var home := MapData.get_castle_by_id(home_castle_id)
	if home == null:
		return []

	match role:
		Character.Role.CAMPESINO:
			return [home_castle_id]
		Character.Role.SOLDADO:
			return _bfs_within_hops(home_castle_id, 1)
		Character.Role.CABALLERO:
			return _bfs_within_hops(home_castle_id, 2)
		Character.Role.NOBLEZA_BAJA:
			return _castles_in_kingdom(home.kingdom)
		Character.Role.NOBLEZA_ALTA:
			return _kingdom_and_neighbors(home.kingdom)
		Character.Role.REGENTE:
			return _all_castle_ids()
		_:
			return [home_castle_id]

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
