extends Node
# Autoload — registrar como "ExplorationData"
# Lugares del mapa que aparecen y desaparecen (ruinas, campamentos, cuevas...). Guarda su estado (SaveSystem.MODULES).
# Cada pocos meses aparece un lugar junto a un castillo; dura unos meses y luego se desvanece.
# Visitarlo gasta una acción y plantea una decisión (ver SiteCatalog), que puede acabar en combate.

const SiteCatalog = preload("res://scripts/resources/site_catalog.gd")
const XpRules = preload("res://scripts/resources/xp_rules.gd")

signal sites_changed

const MAX_SITES := 4
const SPAWN_EVERY := [2, 3]           # meses entre apariciones (al azar en el rango)
const NEAR_VISIBLE_CHANCE := 0.75     # casi siempre aparecen donde el jugador puede verlos
const DISTANCE_RANGE := [70.0, 110.0] # píxeles desde su castillo
const MIN_CASTLE_GAP := 50.0          # sin taparse con otros castillos
const MIN_SITE_GAP := 90.0            # ni con otros lugares (sus nombres son largos)

## [{uid, type, castle_id, x, y, months_left}]
var sites: Array[Dictionary] = []
var visited_count := 0
var _months_to_next := 1
var _next_uid := 1

func _ready() -> void:
	GameManager.game_started.connect(func(_character: Character): reset())
	GameManager.turn_advanced.connect(_on_month_passed)

func reset() -> void:
	sites.clear()
	visited_count = 0
	_months_to_next = 1
	_next_uid = 1
	sites_changed.emit()

func find(uid: String) -> Dictionary:
	for s: Dictionary in sites:
		if s.uid == uid:
			return s
	return {}

func site_position(site: Dictionary) -> Vector2:
	return Vector2(float(site.x), float(site.y))

func site_name(site: Dictionary) -> String:
	return SiteCatalog.site_def(site.type).get("name", site.type)

# --- Paso del tiempo ---

func _on_month_passed(_month: int, _year: int) -> void:
	if not GameManager.is_game_active:
		return
	for s: Dictionary in sites.duplicate():
		s.months_left = int(s.months_left) - 1
		if s.months_left <= 0:
			sites.erase(s)
	_months_to_next -= 1
	if _months_to_next <= 0:
		spawn_site()
		_months_to_next = randi_range(SPAWN_EVERY[0], SPAWN_EVERY[1])
	sites_changed.emit()

## Hace aparecer un lugar (de un tipo al azar, o el pedido). Devuelve el lugar o {} si no cupo.
func spawn_site(type: String = "", castle_id: String = "") -> Dictionary:
	if sites.size() >= MAX_SITES or MapData.castles.is_empty():
		return {}
	if type.is_empty():
		var free_types: Array = SiteCatalog.ORDER.filter(func(t): return not sites.any(func(s): return s.type == t))
		if free_types.is_empty():
			return {}
		type = free_types.pick_random()
	var castle: Castle = MapData.get_castle_by_id(castle_id) if not castle_id.is_empty() else _pick_castle()
	if castle == null:
		return {}
	var pos := _free_spot_near(castle)
	var d := SiteCatalog.site_def(type)
	var site := {"uid": "s%d" % _next_uid, "type": type, "castle_id": castle.castle_id, "x": pos.x, "y": pos.y,
		"months_left": randi_range(int(d.months[0]), int(d.months[1]))}
	_next_uid += 1
	sites.append(site)
	if castle.castle_id in _player_visible_ids():
		WorldEvents.record("Cerca de %s aparece un lugar: %s." % [castle.castle_name, d.name], castle.castle_id)
	sites_changed.emit()
	return site

func _player_visible_ids() -> Array[String]:
	var player: Character = GameManager.player_character
	if player == null:
		return []
	return MapVision.get_visible_castle_ids(player.role, GameManager.home_castle_id, SkillEffects.vision_bonus(player))

func _pick_castle() -> Castle:
	var visible := _player_visible_ids()
	var pool: Array[Castle] = []
	if randf() < NEAR_VISIBLE_CHANCE:
		for c: Castle in MapData.castles:
			if c.castle_id in visible:
				pool.append(c)
	if pool.is_empty():
		pool = MapData.castles.duplicate()
	return pool.pick_random()

func _free_spot_near(castle: Castle) -> Vector2:
	var best := castle.position_on_map + Vector2(DISTANCE_RANGE[0], 0)
	for attempt in 12:
		var p := castle.position_on_map + Vector2.from_angle(randf() * TAU) * randf_range(DISTANCE_RANGE[0], DISTANCE_RANGE[1])
		p.x = clampf(p.x, 40.0, MapData.MAP_WIDTH - 40.0)
		p.y = clampf(p.y, 40.0, MapData.MAP_HEIGHT - 40.0)
		var clear := MapData.castles.all(func(c: Castle) -> bool: return c.position_on_map.distance_to(p) >= MIN_CASTLE_GAP) \
			and sites.all(func(s: Dictionary) -> bool: return site_position(s).distance_to(p) >= MIN_SITE_GAP)
		best = p
		if clear:
			break
	return best

# --- Visitas ---

## Visita el lugar eligiendo una opción: gasta una acción, aplica sus efectos y el lugar desaparece.
## Devuelve {ok, text, fight (dict de combate para CombatSetup.begin_event_fight, o {}), title}.
func visit(uid: String, option_index: int) -> Dictionary:
	var site := find(uid)
	var player: Character = GameManager.player_character
	if site.is_empty() or player == null:
		return {"ok": false, "text": "Ese lugar ya no está."}
	var event := SiteCatalog.as_event(site.type)
	var options: Array = event.options
	if option_index < 0 or option_index >= options.size():
		return {"ok": false, "text": ""}
	var home := MapData.get_castle_by_id(GameManager.home_castle_id)
	if not EventCatalog.can_choose(options[option_index], player, home):
		return {"ok": false, "text": EventCatalog.requirement_text(options[option_index])}
	if not GameManager.consume_action():
		return {"ok": false, "text": "No te quedan acciones este mes."}
	var text := EventCatalog.apply_option(event, option_index, player, home)
	var levels := player.gain_xp(XpRules.EXPLORATION, XpRules.SOURCE_EXPLORATION)
	text += "\n(+%d exp. por explorar%s)" % [player.last_xp_gained, " · ¡subes al nivel %d!" % player.level if levels > 0 else ""]
	sites.erase(site)
	visited_count += 1
	var option: Dictionary = options[option_index]
	WorldEvents.record("%s: %s. %s" % [event.title, option.get("label", ""), text.get_slice("\n", 0)], site.castle_id, true)
	sites_changed.emit()
	return {"ok": true, "text": text, "fight": CombatSetup.tag_fight(option.get("fight", {}), "exploracion"), "title": event.title}

# --- Guardado ---

## Estado para el guardado: solo datos planos (los personajes, con DataCodec.encode).
func save_state() -> Dictionary:
	return {"sites": sites.duplicate(true), "visited_count": visited_count, "months_to_next": _months_to_next, "next_uid": _next_uid}

func load_state(data: Dictionary) -> void:
	sites.clear()
	for s in data.get("sites", []):
		if s is Dictionary and SiteCatalog.SITES.has(s.get("type", "")):
			sites.append({"uid": str(s.uid), "type": str(s.type), "castle_id": str(s.castle_id),
				"x": float(s.x), "y": float(s.y), "months_left": int(s.months_left)})
	visited_count = int(data.get("visited_count", 0))
	_months_to_next = int(data.get("months_to_next", 1))
	_next_uid = int(data.get("next_uid", sites.size() + 1))
	sites_changed.emit()
