# --- Más trato con presos y siervos: interrogar, trabajos, adiestrar, negociar ---

const INTERROGATE_BASE := 0.4          # + Carisma × INTERROGATE_PER_CHARISMA
const INTERROGATE_PER_CHARISMA := 0.03
const INTERROGATE_AFFECTION := -8
const WORKS := {"forja": "Forja", "campo": "Campo", "servicio": "Servicio"}
const WORK_FORGE_GOLD := 6             # oro extra al mes
const WORK_FIELD_FOOD := 8             # comida al mes para tu castillo
const WORK_SERVICE_GOLD := 5           # oro al mes para tu castillo
const TRAIN_COST := 15
const TRAIN_XP := 40
const TRAIN_LOYALTY := 6
const TRAIN_AFFECTION := 4
const NEGOTIATE_BASE := 0.35           # + Carisma × NEGOTIATE_PER_CHARISMA
const NEGOTIATE_PER_CHARISMA := 0.025
const NEGOTIATE_MULT := 1.6
const NEGOTIATE_FAIL_AFFINITY := -5
const CAPTIVE_EVENT_CHANCE := 0.25     # al mes, un suceso con un preso o siervo
const PRISONER_ESCAPE_CHASE := 0.6
const CHASE_HEALTH := 10
const SERVICE_OFFER_AFFECTION := 45    # un preso que te aprecia se ofrece a servirte
const FAMILY_OFFER_MULT := 1.2
const DENY_FREEDOM_AFFECTION := -6

func interrogate_blocker(p: Dictionary) -> String:
	if bool(p.get("interrogated", false)):
		return "Ya no sabe más."
	if not GameManager.has_actions_remaining():
		return "No te quedan acciones este turno."
	return ""

## Interrogar: con suerte suelta un rumor o un secreto de su reino (una vez por preso).
func interrogate(p: Dictionary) -> String:
	var reason := interrogate_blocker(p)
	if not reason.is_empty():
		return reason
	var player: Character = GameManager.player_character
	GameManager.consume_action()
	p["interrogated"] = true
	var r := relation_of(p)
	if r != null:
		r.adjust_affection(INTERROGATE_AFFECTION)
	_changed()
	if randf() >= INTERROGATE_BASE + player.charisma * INTERROGATE_PER_CHARISMA:
		return "%s no suelta prenda." % p.name
	var secret := _kingdom_secret(int(p.kingdom))
	WorldEvents.record("Confesión de %s: %s" % [p.name, secret], "", true)
	return "%s confiesa: %s" % [p.name, secret]

func _kingdom_secret(kingdom: int) -> String:
	for lord: Relationship in RelationsData.lords():
		if _kingdom_of(lord) == kingdom and not AmbitionData.ambition_of(lord.person_name).is_empty():
			return "%s anda tras esto — %s." % [lord.person_name, AmbitionData.ambition_text(lord.person_name)]
	var weakest: Castle = null
	for c: Castle in MapData.castles:
		if c.kingdom == kingdom and (weakest == null or c.garrison_size < weakest.garrison_size):
			weakest = c
	if weakest != null:
		return "%s solo tiene %d soldados." % [weakest.castle_name, weakest.garrison_size]
	return "nada que no supieras."

## Trabajo de un siervo: forja (oro), campo (comida del castillo) o servicio (oro del castillo).
func assign_work(person_name: String, work: String) -> String:
	if not is_serf(person_name) or not WORKS.has(work):
		return "No disponible."
	serf_work[person_name] = work
	_changed()
	return "%s trabajará en: %s." % [person_name, WORKS[work]]

func _work_month(person_name: String) -> int:
	var home: Castle = MapData.get_castle_by_id(GameManager.home_castle_id)
	match serf_work.get(person_name, ""):
		"forja":
			return WORK_FORGE_GOLD
		"campo":
			if home != null:
				home.food += WORK_FIELD_FOOD
		"servicio":
			if home != null:
				home.gold += WORK_SERVICE_GOLD
	return 0

func train_blocker(person_name: String) -> String:
	if not is_serf(person_name):
		return "No disponible."
	if int(train_month.get(person_name, -1)) == GameManager.months_elapsed():
		return "Ya entrenó este mes."
	if GameManager.player_character.gold < TRAIN_COST:
		return "Necesitas %d de oro." % TRAIN_COST
	if not GameManager.has_actions_remaining():
		return "No te quedan acciones este turno."
	return ""

## Adiestrar a un siervo para tu mesnada: gana experiencia, intimidad y lealtad.
func train_serf(person_name: String) -> String:
	var reason := train_blocker(person_name)
	if not reason.is_empty():
		return reason
	var r := RelationsData.get_relation(person_name)
	GameManager.consume_action()
	GameManager.player_character.gold -= TRAIN_COST
	train_month[person_name] = GameManager.months_elapsed()
	if r.character != null:
		r.character.gain_xp(TRAIN_XP, XpRules.SOURCE_TRAINING)
	r.adjust_affection(TRAIN_AFFECTION)
	LoyaltyData.change(person_name, TRAIN_LOYALTY)
	_changed()
	return "Adiestras a %s (+%d exp., lealtad +%d)." % [person_name, TRAIN_XP, TRAIN_LOYALTY]

func negotiate_blocker(p: Dictionary) -> String:
	var reason := ransom_blocker(p)
	if not reason.is_empty():
		return reason
	if bool(p.get("negotiated", false)):
		return "Su familia ya no negocia."
	if not GameManager.has_actions_remaining():
		return "No te quedan acciones este turno."
	return ""

## Negociar con su familia: si sale bien pagan más que el rescate; si no, se ofenden y ya no negocian.
func negotiate_ransom(p: Dictionary) -> String:
	var reason := negotiate_blocker(p)
	if not reason.is_empty():
		return reason
	var player: Character = GameManager.player_character
	GameManager.consume_action()
	p["negotiated"] = true
	if randf() < NEGOTIATE_BASE + player.charisma * NEGOTIATE_PER_CHARISMA:
		var gold := roundi(ransom_value(p) * NEGOTIATE_MULT)
		player.gold += gold
		_kingdom_affinity(int(p.kingdom), RANSOM_AFFINITY)
		_release_record(p)
		_changed()
		var text := "Su familia paga %d de oro por %s." % [gold, p.name]
		WorldEvents.record(text, "", true)
		return text
	_kingdom_affinity(int(p.kingdom), NEGOTIATE_FAIL_AFFINITY)
	_changed()
	return "La familia de %s rechaza tus exigencias." % p.name

## Un suceso al mes como mucho: fuga, ofrecimiento de servir, súplica o reclamación de la familia.
func _captive_event_month() -> void:
	var own := player_prisoners()
	if own.is_empty() or randf() >= CAPTIVE_EVENT_CHANCE:
		return
	GameManager.queue_event(captive_event(own.pick_random()))

func captive_event(p: Dictionary, kind: String = "") -> Dictionary:
	var who := str(p.name)
	var r := relation_of(p)
	if kind.is_empty():
		var kinds := ["escape", "plea"]
		if r != null and r.affection >= SERVICE_OFFER_AFFECTION:
			kinds.append("service")
		if ransom_value(p) > 0:
			kinds.append("family")
		kind = kinds.pick_random()
	var ev := {"id": "preso_" + kind, "speaker": who}
	match kind:
		"escape":
			ev.title = "Intento de fuga"
			ev.text = "%s ha burlado a la guardia y huye." % who
			ev.options = [{"label": "Perseguir (%d%%)" % roundi(PRISONER_ESCAPE_CHASE * 100), "result": "", "capture_action": "chase", "person": who},
				{"label": "Dejarle ir", "result": "", "capture_action": "let_go", "person": who}]
		"service":
			ev.title = "Lealtad en la celda"
			ev.text = "%s se ofrece a servirte." % who
			ev.options = [{"label": "Aceptar", "result": "", "capture_action": "accept_service", "person": who},
				{"label": "Rechazar", "result": "Sigue preso."}]
		"family":
			ev.title = "Su familia reclama"
			ev.text = "La familia de %s ofrece %d de oro por su vuelta." % [who, roundi(ransom_value(p) * FAMILY_OFFER_MULT)]
			ev.options = [{"label": "Aceptar el oro", "result": "", "capture_action": "family_accept", "person": who},
				{"label": "Negarse", "result": "", "capture_action": "family_refuse", "person": who}]
		_:
			ev.title = "Súplica"
			ev.text = "%s te suplica la libertad." % who
			ev.options = [{"label": "Liberar", "result": "", "capture_action": "grant_freedom", "person": who},
				{"label": "Negarse", "result": "", "capture_action": "deny_freedom", "person": who}]
	return ev

func captive_choice(action: String, who: String) -> String:
	var found: Variant = _find(who)
	if found == null or not (found as Dictionary).by_player:
		return "Ya no está en tus mazmorras."
	var p: Dictionary = found
	var r := relation_of(p)
	var player: Character = GameManager.player_character
	match action:
		"chase":
			if randf() < PRISONER_ESCAPE_CHASE:
				return "Le das alcance y vuelve a su celda."
			player.current_health = maxi(1, player.current_health - CHASE_HEALTH)
			_release_record(p)
			_changed()
			return "Se te escapa (vida −%d)." % CHASE_HEALTH
		"let_go":
			_release_record(p)
			_changed()
			return "%s desaparece en la noche." % who
		"accept_service":
			_release_record(p)
			if r != null and not r.person_name in RelationsData.retinue:
				RelationsData.retinue.append(r.person_name)
			_changed()
			return "%s se une a tu séquito." % who
		"grant_freedom":
			return free_prisoner(p)
		"deny_freedom":
			if r != null:
				r.adjust_affection(DENY_FREEDOM_AFFECTION)
			return "%s vuelve a la oscuridad de su celda." % who
		"family_accept":
			var gold := roundi(ransom_value(p) * FAMILY_OFFER_MULT)
			player.gold += gold
			_kingdom_affinity(int(p.kingdom), RANSOM_AFFINITY)
			_release_record(p)
			_changed()
			return "Recibes %d de oro y %s vuelve con los suyos." % [gold, who]
		"family_refuse":
			_kingdom_affinity(int(p.kingdom), NEGOTIATE_FAIL_AFFINITY)
			return "Su familia no olvidará tu negativa."
	return ""
