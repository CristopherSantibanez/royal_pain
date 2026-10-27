extends Node
# Autoload — historias encadenadas (ver StoryCatalog): una a la vez, con pasos separados por meses,
# decisiones que se recuerdan (marcas) y finales que cambian el mundo.
# Los pasos llegan como eventos por la cola de GameManager.queue_event; el flujo de la historia va en
# el efecto "story" de cada opción, que EventCatalog._apply_effects reenvía a apply_story().

const StoryCatalog = preload("res://scripts/resources/story_catalog.gd")

const CHAIN_CHANCE := 0.12            # probabilidad mensual de que empiece una historia (si toca)
const FIRST_CHAIN_MONTH := 6          # ninguna historia en el primer medio año
const MIN_GAP_MONTHS := 30            # entre el final de una y el comienzo de otra (≈3 por década)
const TRAVEL_DEADLINE := 6            # meses para llegar a donde pide un paso (si el paso no fija otro)
const STALL_MONTHS := 4               # un paso sin respuesta (p. ej. combate abandonado) se da por perdido
const HISTORY_MAX := 20
const EVENT_PREFIX := "story_"

signal story_changed

var active: Dictionary = {}           # chain, step, flags[], cast{}, due, awaiting, queued_month, last_choice, started
var history: Array = []               # [{chain, title, ending, m, y}]
var done_chains: Array = []           # ids ya jugados en esta partida (no se repiten)
var last_end_month := -1000

func _ready() -> void:
	GameManager.game_started.connect(func(_c: Character): reset())
	GameManager.turn_advanced.connect(_on_month_passed)
	GameManager.event_option_chosen.connect(_on_option_chosen)
	var travel := get_node_or_null("/root/TravelData")
	if travel != null:
		travel.location_changed.connect(_on_location_changed)

func reset() -> void:
	active = {}
	history = []
	done_chains = []
	last_end_month = -1000

# --- Consultas ---

func is_active() -> bool:
	return not active.is_empty()

func active_title() -> String:
	return str(StoryCatalog.chain(active.get("chain", "")).get("title", "")) if is_active() else ""

## Si el paso actual exige estar en un castillo, su id ("" si no).
func travel_target() -> String:
	if not is_active():
		return ""
	var step := _step()
	return str(active.cast.get(step.get("travel", ""), "")) if step.has("travel") else ""

## Una línea corta para paneles: «Historia: título · última decisión» o «· Viaja a X».
func summary_line() -> String:
	if not is_active():
		if history.is_empty():
			return ""
		var last: Dictionary = history.back()
		return "Última historia: %s — %s" % [last.title, last.ending]
	var line := "Historia: %s" % active_title()
	var target := travel_target()
	if not target.is_empty() and not _at(target) and not active.get("awaiting", false):
		var c := MapData.get_castle_by_id(target)
		line += " · Viaja a %s" % (c.castle_name if c != null else "?")
	elif not str(active.get("last_choice", "")).is_empty():
		line += " · «%s»" % active.last_choice
	return line

# --- Ciclo mensual ---

func _on_month_passed(_month: int, _year: int) -> void:
	if not GameManager.is_game_active or GameManager.player_character == null:
		return
	if is_active():
		_tick()
	else:
		_maybe_start()

func _now() -> int:
	return GameManager.months_elapsed()

func _captive() -> bool:
	var cd := get_node_or_null("/root/CaptureData")
	return cd != null and cd.has_method("is_captive") and cd.is_captive()

func _maybe_start() -> void:
	var now := _now()
	if now < FIRST_CHAIN_MONTH or now - last_end_month < MIN_GAP_MONTHS or _captive():
		return
	if randf() >= CHAIN_CHANCE:
		return
	var pool: Array = []
	var weights: Array[float] = []
	var total := 0.0
	for c: Dictionary in StoryCatalog.CHAINS:
		if c.id in done_chains or not eligible(c):
			continue
		pool.append(c)
		var w: float = c.cond.get("weight", 1.0)
		weights.append(w)
		total += w
	if pool.is_empty():
		return
	var pick := randf() * total
	for i in pool.size():
		pick -= weights[i]
		if pick <= 0.0:
			start(pool[i].id)
			return
	start(pool.back().id)

## ¿Cumple el jugador las condiciones de inicio de la historia?
func eligible(c: Dictionary) -> bool:
	var p: Character = GameManager.player_character
	if p == null:
		return false
	var cond: Dictionary = c.get("cond", {})
	if cond.has("min_rank") and p.rank() < int(cond.min_rank):
		return false
	if cond.has("max_rank") and p.rank() > int(cond.max_rank):
		return false
	if cond.has("min_fame") and p.fame < int(cond.min_fame):
		return false
	if cond.has("min_honor") and p.honor < int(cond.min_honor):
		return false
	if cond.has("months") and not GameManager.current_month in cond.months:
		return false
	if cond.get("needs_liege", false) and RelationsData.liege_name.is_empty():
		return false
	if cond.get("needs_castle", false) and RelationsData.castles_of(p.full_name()).is_empty():
		return false
	if cond.get("needs_war", false) and _enemy_lord_name().is_empty():
		return false
	return not _cast(c).is_empty()

## Empieza una historia (las pruebas la fuerzan con esto). Devuelve false si no se puede repartir el reparto.
func start(chain_id: String) -> bool:
	var c := StoryCatalog.chain(chain_id)
	if c.is_empty():
		return false
	var cast := _cast(c)
	if cast.is_empty():
		return false
	active = {"chain": chain_id, "step": c.start, "flags": [], "cast": cast, "due": _now(),
		"awaiting": false, "queued_month": -1, "last_choice": "", "started": _now(), "travel_since": -1}
	WorldEvents.record("Comienza una historia: %s." % c.title, cast.get("castle", ""), true)
	_tick()
	story_changed.emit()
	return true

func _tick() -> void:
	var now := _now()
	if active.get("awaiting", false):
		# Un paso que nadie respondió (combate abandonado, partida antigua): se da por perdido.
		if now - int(active.queued_month) >= STALL_MONTHS and not _event_waiting():
			_finish("", "La historia quedó en el aire.")
		return
	if _captive() or now < int(active.due):
		return
	var step := _step()
	if step.has("travel") and not _at(str(active.cast.get(step.travel, ""))):
		if int(active.travel_since) < 0:
			active.travel_since = now
		if now - int(active.travel_since) >= int(step.get("deadline", TRAVEL_DEADLINE)):
			var timeout: String = step.get("timeout", "")
			if timeout.is_empty():
				_finish("", "No llegaste a tiempo.")
			else:
				_finish(timeout)
		return
	_queue_step()

func _on_location_changed(_castle_id: String) -> void:
	# Llegar al lugar que pedía el paso lo dispara en ese momento (si ya tocaba y no hubo otro paso este mes).
	if is_active() and not active.get("awaiting", false) and _now() >= int(active.due) \
			and int(active.queued_month) != _now() and not travel_target().is_empty() and _at(travel_target()):
		_queue_step()

func _queue_step() -> void:
	var event := build_event()
	if event.is_empty():
		_finish("", "")
		return
	active.awaiting = true
	active.queued_month = _now()
	active.travel_since = -1
	GameManager.queue_event(event)
	story_changed.emit()

func _event_waiting() -> bool:
	var id := EVENT_PREFIX + str(active.get("chain", ""))
	if str(GameManager.pending_event.get("_story", "")) == id:
		return true
	for e: Dictionary in GameManager.event_queue:
		if str(e.get("_story", "")) == id:
			return true
	return not CombatSetup.pending_outcome.is_empty() and str(CombatSetup.pending_outcome.get("title", "")).begins_with(active_title())

# --- Construcción del evento del paso ---

func _step() -> Dictionary:
	var c := StoryCatalog.chain(active.get("chain", ""))
	return c.get("steps", {}).get(active.get("step", ""), {})

## El evento del paso actual, con las opciones que permiten las marcas y los textos ya rellenos.
func build_event() -> Dictionary:
	var c := StoryCatalog.chain(active.get("chain", ""))
	var step := _step()
	if step.is_empty():
		return {}
	var options: Array = []
	for o: Dictionary in step.options:
		if _option_visible(o):
			options.append(_fill(o.duplicate(true)))
	if options.is_empty():
		return {}
	var event := {"id": "%s%s_%s" % [EVENT_PREFIX, c.id, active.step], "_story": EVENT_PREFIX + str(c.id),
		"title": _fill("%s: %s" % [c.title, step.title]), "text": _fill(step.text), "options": options}
	if step.get("speaker", "") == "lord" and RelationsData.get_relation(str(active.cast.get("lord", ""))) != null:
		event.speaker = active.cast.lord
	return event

func _option_visible(o: Dictionary) -> bool:
	var flags: Array = active.get("flags", [])
	if o.has("if") and not str(o.if) in flags:
		return false
	if o.has("if_not") and str(o.if_not) in flags:
		return false
	var p: Character = GameManager.player_character
	if o.has("min_rank") and p.rank() < int(o.min_rank):
		return false
	if o.has("max_rank") and p.rank() > int(o.max_rank):
		return false
	return true

## Rellena {lord}, {castle}… y las marcas de género en textos, etiquetas y combates.
func _fill(v: Variant) -> Variant:
	if v is String:
		var s: String = v
		var cast: Dictionary = active.get("cast", {})
		var p: Character = GameManager.player_character
		s = s.replace("{player}", p.full_name() if p != null else "")
		for key in ["lord", "npc", "enemy"]:
			s = s.replace("{%s}" % key, str(cast.get(key, "")))
		for key in ["castle", "near", "far"]:
			var c := MapData.get_castle_by_id(str(cast.get(key, "")))
			s = s.replace("{%s}" % key, c.castle_name if c != null else "")
		var home := MapData.get_castle_by_id(str(cast.get("castle", "")))
		s = s.replace("{kingdom}", KingdomEnums.kingdom_name(home.kingdom) if home != null else "")
		var lord_rel := RelationsData.get_relation(str(cast.get("lord", "")))
		return DialogueCatalog._apply_gender(s, lord_rel.character if lord_rel != null else null, p)
	if v is Dictionary:
		var d: Dictionary = v
		for k in d.keys():
			if k != "story":
				d[k] = _fill(d[k])
		return d
	if v is Array:
		var a: Array = v
		for i in a.size():
			a[i] = _fill(a[i])
		return a
	return v

# --- Reparto ---

func _here() -> Castle:
	var travel := get_node_or_null("/root/TravelData")
	var c: Castle = travel.current_castle() if travel != null else null
	return c if c != null else MapData.get_castle_by_id(GameManager.home_castle_id)

func _at(castle_id: String) -> bool:
	var here := _here()
	return here != null and here.castle_id == castle_id

func _cast(c: Dictionary) -> Dictionary:
	var here := _here()
	if here == null:
		return {}
	var cast := {"castle": here.castle_id}
	for role: String in c.get("cast", []):
		match role:
			"lord":
				var lord := here.owner_name if RelationsData.get_relation(here.owner_name) != null else RelationsData.liege_name
				if lord.is_empty() or GameManager.player_character == null or lord == GameManager.player_character.full_name():
					lord = RelationsData.liege_name
				if lord.is_empty() or RelationsData.get_relation(lord) == null:
					return {}
				cast.lord = lord
			"castle":
				pass
			"near":
				var near := _castle_near(here)
				if near == null:
					return {}
				cast.near = near.castle_id
			"far":
				var far := _castle_far(here)
				if far == null:
					return {}
				cast.far = far.castle_id
			"enemy":
				var enemy := _enemy_lord_name()
				if enemy.is_empty():
					return {}
				cast.enemy = enemy
			"npc":
				var culture := MapData.culture_of_castle(here)
				var gender := CharacterEnums.Gender.MASCULINO
				cast.npc = "%s %s" % [CharacterLoader.random_first_name(gender, culture), CharacterLoader.random_last_name(culture, gender)]
	return cast

func _castle_near(here: Castle) -> Castle:
	var options: Array[Castle] = []
	for id: String in here.connected_castle_ids:
		var c := MapData.get_castle_by_id(id)
		if c != null:
			options.append(c)
	return options.pick_random() if not options.is_empty() else null

## Un castillo de otro reino a dos o más tramos (o el más lejano que haya).
func _castle_far(here: Castle) -> Castle:
	var travel := get_node_or_null("/root/TravelData")
	var best: Castle = null
	var best_len := 0
	var candidates: Array[Castle] = []
	for c: Castle in MapData.castles:
		if c == here or c.kingdom == here.kingdom:
			continue
		var hops: int = travel.path_to(c.castle_id, here.castle_id).size() if travel != null else 2
		if hops >= 2:
			candidates.append(c)
		if hops > best_len:
			best_len = hops
			best = c
	return candidates.pick_random() if not candidates.is_empty() else best

func _enemy_lord_name() -> String:
	var mine := GameManager.player_kingdom
	for c: Castle in MapData.castles:
		if c.kingdom != mine and KingdomDiplomacy.at_war(RelationsData.kingdom_wars, mine, c.kingdom) \
				and RelationsData.get_relation(c.owner_name) != null:
			return c.owner_name
	return ""

# --- Flujo: lo llama EventCatalog._apply_effects con el efecto "story" ---

func _on_option_chosen(event: Dictionary, option: Dictionary) -> void:
	if is_active() and str(event.get("_story", "")) == EVENT_PREFIX + str(active.chain):
		active.last_choice = str(option.get("label", ""))

## Aplica {set, next, end} de una opción o de un desenlace. Devuelve un texto para el resumen ("" casi siempre).
func apply_story(spec: Variant, _character: Character = null) -> String:
	if not is_active() or not spec is Dictionary:
		return ""
	var flags: Array = active.flags
	for f in spec.get("set", []):
		if not str(f) in flags:
			flags.append(str(f))
	if spec.has("next"):
		var c := StoryCatalog.chain(active.chain)
		var next_step: Dictionary = c.steps.get(str(spec.next), {})
		if next_step.is_empty():
			return _finish("", "")
		var delay: Array = next_step.get("delay", [1, 2])
		active.step = str(spec.next)
		active.due = _now() + maxi(1, randi_range(int(delay[0]), int(delay[1])))   # nunca dos pasos el mismo mes
		active.awaiting = false
		active.travel_since = -1
		story_changed.emit()
		return ""
	if spec.has("end"):
		return _finish(str(spec.end))
	return ""

## Cierra la historia con un final (o sin él: ending_id = "", con un texto corto).
func _finish(ending_id: String, fallback_text: String = "") -> String:
	var c := StoryCatalog.chain(active.get("chain", ""))
	var ending: Dictionary = c.get("endings", {}).get(ending_id, {})
	var title: String = _fill(ending.get("title", "Sin final"))
	var text: String = _fill(ending.get("text", fallback_text))
	var world := _apply_world(ending.get("world", {}))
	var full := "%s. %s" % [title, text]
	if not world.is_empty():
		full += " (%s)" % world
	WorldEvents.record("Historia «%s»: %s" % [c.get("title", "?"), full], str(active.get("cast", {}).get("castle", "")), true)
	history.append({"chain": c.get("id", ""), "title": c.get("title", "?"), "ending": title,
		"m": GameManager.current_month, "y": GameManager.current_year})
	if history.size() > HISTORY_MAX:
		history = history.slice(history.size() - HISTORY_MAX)
	if not str(c.get("id", "")).is_empty() and not c.id in done_chains:
		done_chains.append(c.id)
	last_end_month = _now()
	var from_event := str(GameManager.pending_event.get("_story", "")) == EVENT_PREFIX + str(c.get("id", ""))
	active = {}
	story_changed.emit()
	# Dentro de la decisión, el final se añade al resultado; si llega tras un combate o sin evento, como aviso.
	if from_event:
		GameManager.pending_event["_extra_result"] = "Fin de la historia — " + full
	else:
		WorldEvents.notify("Fin de «%s»" % c.get("title", "?"), full)
	return ""

func _apply_world(world: Dictionary) -> String:
	if world.is_empty():
		return ""
	var parts: Array[String] = []
	var p: Character = GameManager.player_character
	var cast: Dictionary = active.get("cast", {})
	var lord := RelationsData.get_relation(str(cast.get("lord", "")))
	var castle := MapData.get_castle_by_id(str(cast.get("castle", "")))
	if world.has("lord_affinity") and lord != null:
		lord.adjust(int(world.lord_affinity))
		parts.append("Afinidad con %s %+d" % [lord.person_name, int(world.lord_affinity)])
	if world.has("liege_affinity"):
		var liege := RelationsData.get_relation(RelationsData.liege_name)
		if liege != null:
			liege.adjust(int(world.liege_affinity))
			parts.append("Afinidad con %s %+d" % [liege.person_name, int(world.liege_affinity)])
	if world.has("kingdom_affinity") and castle != null:
		for r: Relationship in RelationsData.lords():
			var cs := RelationsData.castles_of(r.person_name)
			if not cs.is_empty() and cs[0].kingdom == castle.kingdom:
				r.adjust(int(world.kingdom_affinity))
		parts.append("Afinidad con %s %+d" % [KingdomEnums.kingdom_name(castle.kingdom), int(world.kingdom_affinity)])
	if castle != null:
		if world.has("castle_garrison"):
			var before := castle.garrison_size
			castle.garrison_size = int(castle.garrison_size * float(world.castle_garrison))
			parts.append("Guarnición de %s %+d" % [castle.castle_name, castle.garrison_size - before])
		if world.has("castle_food"):
			castle.food = maxi(0, castle.food + int(world.castle_food))
			parts.append("Comida de %s %+d" % [castle.castle_name, int(world.castle_food)])
		if world.has("castle_gold"):
			castle.gold = maxi(0, castle.gold + int(world.castle_gold))
			parts.append("Oro de %s %+d" % [castle.castle_name, int(world.castle_gold)])
	if world.has("kill"):
		var victim := RelationsData.get_relation(str(cast.get(str(world.kill), "")))
		if victim != null and victim.kind == Relationship.Kind.SENOR and p != null and victim.person_name != p.full_name():
			WorldEvents.kill_lord(victim, "veneno")
	if world.has("castle_to_player") and p != null:
		var gift := MapData.get_castle_by_id(str(cast.get(str(world.castle_to_player), "")))
		if gift != null and gift.owner_name != p.full_name() and gift.owner_name != RelationsData.liege_name:
			gift.owner_name = p.full_name()
			if GameManager.player_kingdom >= 0:
				gift.kingdom = GameManager.player_kingdom
			parts.append("%s pasa a tus manos" % gift.castle_name)
	if p != null and (world.has("unique") or world.has("unique_chance")):
		if randf() * 100.0 < float(world.get("unique_chance", 100)):
			var found: String = load("res://scripts/resources/unique_items.gd").grant(p, str(world.get("unique", "")))
			if not found.is_empty():
				parts.append(found)
	return ", ".join(parts)

# --- Guardado ---

func save_state() -> Dictionary:
	return {"active": active.duplicate(true), "history": history.duplicate(true),
		"done": done_chains.duplicate(), "last_end": last_end_month}

func load_state(data: Dictionary) -> void:
	active = data.get("active", {}).duplicate(true)
	history = data.get("history", []).duplicate(true)
	done_chains = data.get("done", []).duplicate()
	last_end_month = int(data.get("last_end", -1000))
	# Una historia guardada con un paso que ya no existe se descarta.
	if not active.is_empty() and _step().is_empty():
		active = {}
