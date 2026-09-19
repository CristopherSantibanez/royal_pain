class_name DuelManager
extends RefCounted

signal log_message(text: String)
signal duel_ended(winner: Character, reason: String)
signal state_updated
signal character_demoted(character: Character, old_role: int, new_role: int)

var fighter_a: Character
var fighter_b: Character

var posture := {}
var statuses := {}
var disarmed_turns := {}
var defending := {}
var dodging := {}
var countering := {}

var is_over := false

func start_duel(a: Character, b: Character) -> void:
	fighter_a = a
	fighter_b = b
	for c in [a, b]:
		posture[c] = CombatEnums.Posture.DEFENSIVA
		statuses[c] = []
		disarmed_turns[c] = 0
		defending[c] = false
		dodging[c] = false
		countering[c] = false
	is_over = false
	log_message.emit("¡Comienza el duelo entre %s y %s!" % [a.full_name(), b.full_name()])

func opponent_of(c: Character) -> Character:
	return fighter_b if c == fighter_a else fighter_a

func set_posture(actor: Character, p: int) -> void:
	posture[actor] = p
	# Ya no emitimos log aquí: se combina con la acción en take_turn().
	state_updated.emit()

func take_turn(actor: Character, action: int) -> void:
	if is_over:
		return
	var target := opponent_of(actor)
	_update_statuses(actor)

	var posture_text := CombatEnums.posture_name(posture[actor])
	var prefix := "%s toma postura %s" % [actor.full_name(), posture_text]
	var action_text := ""

	match action:
		CombatEnums.ActionType.ATACAR:
			action_text = _do_attack(actor, target)
		CombatEnums.ActionType.DEFENDER:
			defending[actor] = true
			actor.current_stamina = max(0, actor.current_stamina - 5)
			action_text = "y se pone en guardia."
		CombatEnums.ActionType.ESQUIVAR:
			dodging[actor] = true
			actor.current_stamina = max(0, actor.current_stamina - 8)
			action_text = "y se prepara para esquivar."
		CombatEnums.ActionType.CONTRAATACAR:
			countering[actor] = true
			actor.current_stamina = max(0, actor.current_stamina - 10)
			action_text = "y adopta guardia de contraataque."
		CombatEnums.ActionType.DESARMAR:
			action_text = _do_disarm(actor, target)
		CombatEnums.ActionType.EMPUJAR:
			action_text = _do_push(actor, target)
		CombatEnums.ActionType.RENDIRSE:
			log_message.emit("%s, %s." % [prefix, "se rinde"])
			_end_duel(target, "%s se rinde." % actor.full_name())
			return
		CombatEnums.ActionType.RETIRARSE:
			_do_retreat(actor, target, prefix)
			return

	log_message.emit("%s %s" % [prefix, action_text])

	_check_end()
	if not is_over:
		_end_turn(actor)

func _do_attack(actor: Character, target: Character) -> String:
	if CombatEnums.Status.DESARMADO in statuses[actor]:
		return "e intenta atacar, ¡pero está desarmado!"

	actor.current_stamina = max(0, actor.current_stamina - 12)

	if dodging[target]:
		dodging[target] = false
		var dodge_chance: float = clamp(0.25 + (target.combat - actor.combat) * 0.03, 0.05, 0.75)
		if randf() < dodge_chance:
			return "y ataca, ¡pero %s esquiva el golpe!" % target.full_name()

	var base: int = actor.combat + _posture_offense_bonus(posture[actor])
	var mitigation: float = target.defense + _posture_defense_bonus(posture[target])
	if defending[target]:
		mitigation += mitigation * 0.5
		defending[target] = false

	var dmg: int = int(clamp(float(base) - mitigation + randi_range(-2, 3), 1, 9999))
	if CombatEnums.Status.DESMORALIZADO in statuses[actor]:
		dmg = int(dmg * 0.8)
	if CombatEnums.Status.INSPIRADO in statuses[actor]:
		dmg = int(dmg * 1.2)

	var extra := ""
	if countering[target]:
		countering[target] = false
		var counter_dmg := int(dmg * 0.5)
		dmg = int(dmg * 0.5)
		actor.take_damage(counter_dmg)
		extra = " ¡Pero %s contraataca, causándole %d de daño!" % [target.full_name(), counter_dmg]

	target.take_damage(dmg)
	target.current_morale = max(0, target.current_morale - 4)
	return "y ataca causando %d de daño.%s" % [dmg, extra]

func _do_disarm(actor: Character, target: Character) -> String:
	actor.current_stamina = max(0, actor.current_stamina - 15)
	var chance: float = clamp(0.4 + (actor.combat - target.defense) * 0.04, 0.1, 0.8)
	if randf() < chance:
		disarmed_turns[target] = 2
		if not CombatEnums.Status.DESARMADO in statuses[target]:
			statuses[target].append(CombatEnums.Status.DESARMADO)
		return "y logra desarmar a %s!" % target.full_name()
	else:
		return "e intenta desarmar a %s, pero falla." % target.full_name()

func _do_push(actor: Character, target: Character) -> String:
	actor.current_stamina = max(0, actor.current_stamina - 10)
	var chance: float = clamp(0.5 + (actor.combat - target.combat) * 0.03, 0.15, 0.85)
	if randf() < chance:
		target.current_stamina = max(0, target.current_stamina - 10)
		target.current_morale = max(0, target.current_morale - 6)
		return "y empuja a %s, desequilibrándolo." % target.full_name()
	else:
		return "e intenta empujar a %s, sin éxito." % target.full_name()

func _do_retreat(actor: Character, target: Character, prefix: String) -> void:
	var chance: float = clamp(0.5 + (actor.combat - target.combat) * 0.03, 0.2, 0.8)
	if randf() < chance:
		_end_duel(null, "%s logra huir del combate." % actor.full_name())
	else:
		log_message.emit("%s e intenta huir, ¡pero %s se lo impide!" % [prefix, target.full_name()])
		actor.current_morale = max(0, actor.current_morale - 10)
		_end_turn(actor)

func _posture_offense_bonus(p: int) -> int:
	match p:
		CombatEnums.Posture.OFENSIVA: return 4
		CombatEnums.Posture.DESESPERADA: return 6
		CombatEnums.Posture.ESGRIMA: return 1
		_: return 0

func _posture_defense_bonus(p: int) -> int:
	match p:
		CombatEnums.Posture.DEFENSIVA: return 3
		CombatEnums.Posture.MURO: return 6
		CombatEnums.Posture.DESESPERADA: return -3
		_: return 0

func _update_statuses(c: Character) -> void:
	var s: Array = statuses[c]
	s.erase(CombatEnums.Status.HERIDO)
	s.erase(CombatEnums.Status.FATIGADO)
	s.erase(CombatEnums.Status.DESMORALIZADO)
	s.erase(CombatEnums.Status.INSPIRADO)

	if c.current_health < c.max_health * 0.3:
		s.append(CombatEnums.Status.HERIDO)
	if c.current_stamina < c.max_stamina * 0.2:
		s.append(CombatEnums.Status.FATIGADO)
	if c.current_morale < c.max_morale * 0.3:
		s.append(CombatEnums.Status.DESMORALIZADO)
	elif c.current_morale > c.max_morale * 0.8:
		s.append(CombatEnums.Status.INSPIRADO)

	if disarmed_turns.get(c, 0) > 0:
		disarmed_turns[c] -= 1
		if disarmed_turns[c] <= 0:
			s.erase(CombatEnums.Status.DESARMADO)

func _end_turn(actor: Character) -> void:
	state_updated.emit()

func _check_end() -> void:
	if not fighter_a.is_alive():
		_end_duel(fighter_b, "%s ha caído." % fighter_a.full_name())
	elif not fighter_b.is_alive():
		_end_duel(fighter_a, "%s ha caído." % fighter_b.full_name())

func _end_duel(winner: Character, reason: String) -> void:
	is_over = true
	_apply_duel_results(winner)
	log_message.emit(reason)
	duel_ended.emit(winner, reason)

func _apply_duel_results(winner: Character) -> void:
	# Solo se registran victorias/derrotas cuando hay un ganador claro
	# (una huida exitosa con winner == null no cuenta como derrota de nadie).
	if winner == null:
		return
	var loser := opponent_of(winner)
	winner.register_duel_win()
	loser.register_duel_loss()
	_check_dishonor_demotion(loser)

func _check_dishonor_demotion(character: Character) -> void:
	if not RoleProgression.check_dishonor_demotion(character):
		return
	var old_role := character.role
	RoleProgression.apply_dishonor_demotion(character)
	log_message.emit("%s cae en deshonra y desciende de %s a %s." % [
		character.full_name(), Character.role_name_for(old_role), character.role_name()
	])
	character_demoted.emit(character, old_role, character.role)
