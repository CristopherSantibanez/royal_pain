class_name DuelManager
extends RefCounted

signal log_message(text: String)
signal duel_ended(winner: Character, reason: String)
signal state_updated
signal character_demoted(character: Character, old_role: int, new_role: int)
## Evento puntual de combate para efectos visuales y de sonido.
## kind: hit, crit, parry, parry_fail, dodge, unarmed, guard, dodge_ready, counter_ready,
## disarm, push, guard_break, miss, winded, retreat_fail. `target` es quien recibe el efecto.
signal combat_event(kind: String, actor: Character, target: Character, amount: int)

# --- Daño (fórmula de proporción: con atributos iguales cada golpe hace ~BASE_HIT/2) ---
const BASE_HIT := 24.0
const DAMAGE_SPREAD := 0.2            # ±20% de variación
const POSTURE_WEIGHT := 1.5           # cuánto pesan las bonificaciones de postura frente a los atributos
const CRIT_CHANCE := 0.10
const CRIT_MULTIPLIER := 1.75
const GUARD_MITIGATION := 2.0         # Defender divide el daño del próximo golpe
const MORALE_LOSS_PER_HIT := 4

# --- Aliento ---
const STAMINA_REGEN := 5              # al comenzar cada turno propio
const COST_ATTACK := 15
const COST_DISARM := 15
const COST_PUSH := 12
const COST_PARRY_STANCE := 5
const RECOVER_DEFEND := 25
const RECOVER_DODGE := 10
const FATIGUE_RATIO := 0.2            # por debajo de este aliento: Fatigado
const FATIGUE_DAMAGE := 0.7

# --- Esquiva, parada y maniobras ---
const DODGE_BASE := 0.35
const ESGRIMA_PASSIVE_DODGE := 0.15
const PARRY_BASE := 0.55
const PARRY_RIPOSTE_FACTOR := 1.25    # la respuesta a una parada llega con ventaja
const MURO_PARRY_PENALTY := 0.2       # tras el escudo es difícil devolver el golpe
const PUSH_STAMINA_DAMAGE := 20
const DISARM_TURNS := 2

# --- Consecuencias de abandonar ---
const RETREAT_HONOR_COST := 3
const SURRENDER_EXTRA_HONOR_COST := 3   # además de la derrota (−5)
const SURRENDER_RANSOM := 25

var fighter_a: Character
var fighter_b: Character

var posture := {}
var statuses := {}
var disarmed_turns := {}
var defending := {}
var dodging := {}
var countering := {}
var last_actions := {}   # Character -> últimas acciones (la IA lee las del rival para adaptarse)

const HISTORY_SIZE := 4

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
		last_actions[c] = []
	# Intimidación: el rival empieza con menos moral.
	for c in [a, b]:
		var other: Character = b if c == a else a
		other.current_morale = maxi(0, other.current_morale - roundi(SkillEffects.fx(c, "intimidate")))
	is_over = false
	log_message.emit("¡Comienza el duelo entre %s y %s!" % [a.full_name(), b.full_name()])

## Quién empieza: lo decide la iniciativa (combate) con algo de azar, para que ir primero no esté garantizado.
func roll_first(a: Character, b: Character) -> Character:
	var chance_a: float = 0.5 + (a.combat - b.combat) * 0.05 + SkillEffects.fx(a, "initiative") - SkillEffects.fx(b, "initiative")
	chance_a = clampf(chance_a, 0.15, 0.85)
	return a if randf() < chance_a else b

func opponent_of(c: Character) -> Character:
	return fighter_b if c == fighter_a else fighter_a

func set_posture(actor: Character, p: int) -> void:
	posture[actor] = p
	# Ya no emitimos log aquí: se combina con la acción en take_turn().
	state_updated.emit()

## Proporción de ataques entre las últimas acciones de un luchador (0..1).
func attack_rate(c: Character) -> float:
	var history: Array = last_actions.get(c, [])
	if history.is_empty():
		return 0.5
	return float(history.count(CombatEnums.ActionType.ATACAR)) / history.size()

func is_fatigued(c: Character) -> bool:
	return c.current_stamina < c.max_stamina * FATIGUE_RATIO

## Guardia preparada por un luchador (lo que el rival puede ver venir).
func guard_text(c: Character) -> String:
	if countering.get(c, false):
		return "Preparado para parar y devolver el golpe"
	if dodging.get(c, false):
		return "Atento a esquivar"
	if defending.get(c, false):
		return "En guardia"
	return ""

func take_turn(actor: Character, action: int) -> void:
	if is_over:
		return
	var target := opponent_of(actor)
	var history: Array = last_actions[actor]
	history.append(action)
	if history.size() > HISTORY_SIZE:
		history.pop_front()
	actor.current_stamina = clampi(actor.current_stamina + STAMINA_REGEN + roundi(SkillEffects.fx(actor, "stamina_regen")), 0, actor.max_stamina)
	_update_statuses(actor)
	# Las guardias duran hasta el próximo turno propio: si el rival no atacó, se pierden.
	defending[actor] = false
	dodging[actor] = false
	countering[actor] = false

	var posture_text := CombatEnums.posture_name(posture[actor])
	var prefix := "%s toma postura %s" % [actor.full_name(), posture_text]
	var action_text := ""

	match action:
		CombatEnums.ActionType.ATACAR:
			action_text = _do_attack(actor, target)
		CombatEnums.ActionType.DEFENDER:
			defending[actor] = true
			_recover(actor, RECOVER_DEFEND)
			combat_event.emit("guard", actor, actor, 0)
			action_text = "y se pone en guardia, recobrando el aliento."
		CombatEnums.ActionType.ESQUIVAR:
			dodging[actor] = true
			_recover(actor, RECOVER_DODGE)
			combat_event.emit("dodge_ready", actor, actor, 0)
			action_text = "y se prepara para esquivar."
		CombatEnums.ActionType.CONTRAATACAR:
			countering[actor] = true
			_spend(actor, COST_PARRY_STANCE)
			combat_event.emit("counter_ready", actor, actor, 0)
			action_text = "y espera el golpe para pararlo y devolverlo."
		CombatEnums.ActionType.DESARMAR:
			action_text = _do_disarm(actor, target)
		CombatEnums.ActionType.EMPUJAR:
			action_text = _do_push(actor, target)
		CombatEnums.ActionType.RENDIRSE:
			log_message.emit("%s, %s." % [prefix, "se rinde"])
			_end_duel(target, "%s se rinde." % actor.full_name(), true)
			return
		CombatEnums.ActionType.RETIRARSE:
			_do_retreat(actor, target, prefix)
			return

	log_message.emit("%s %s" % [prefix, action_text])

	_check_end()
	if not is_over:
		_end_turn(actor)

# --- Previsiones (para la interfaz y la IA; no cambian el estado) ---

## Daño mínimo y máximo de un golpe normal (sin crítico) con las posturas actuales.
func preview_damage(actor: Character, target: Character) -> Vector2i:
	var mid := _base_damage(actor, target)
	return Vector2i(maxi(1, roundi(mid * (1.0 - DAMAGE_SPREAD))), maxi(1, roundi(mid * (1.0 + DAMAGE_SPREAD))))

func dodge_chance(attacker: Character, defender: Character) -> float:
	var chance: float = clampf(DODGE_BASE + (defender.combat - attacker.combat) * 0.03 + SkillEffects.fx(defender, "dodge"), 0.1, 0.8)
	return chance * (0.5 if is_fatigued(defender) else 1.0)

func parry_chance(attacker: Character, defender: Character) -> float:
	var chance: float = PARRY_BASE + (defender.combat - attacker.combat) * 0.04 + SkillEffects.fx(defender, "parry")
	if posture.get(defender) == CombatEnums.Posture.MURO:
		chance -= MURO_PARRY_PENALTY
	return clampf(chance, 0.15, 0.85)

func disarm_chance(actor: Character, target: Character) -> float:
	return clampf(0.4 + (actor.combat - target.defense) * 0.04 + SkillEffects.fx(actor, "disarm"), 0.1, 0.85)

func push_chance(actor: Character, target: Character) -> float:
	return clampf(0.5 + (actor.combat - target.combat) * 0.03 + SkillEffects.fx(actor, "push"), 0.15, 0.9)

func retreat_chance(actor: Character, target: Character) -> float:
	return clampf(0.5 + (actor.combat - target.combat) * 0.03, 0.2, 0.8)

# --- Acciones ---

func _base_damage(actor: Character, target: Character) -> float:
	var atk: float = maxf(1.0, actor.combat + _posture_offense_bonus(posture[actor]) * POSTURE_WEIGHT)
	var def: float = maxf(1.0, target.defense + _posture_defense_bonus(posture[target]) * POSTURE_WEIGHT)
	var dmg: float = BASE_HIT * atk / (atk + def)
	if CombatEnums.Status.DESMORALIZADO in statuses[actor]:
		dmg *= 0.8
	if CombatEnums.Status.INSPIRADO in statuses[actor]:
		dmg *= 1.2
	if is_fatigued(actor):
		dmg *= FATIGUE_DAMAGE
	# Efectos de habilidades, rasgos y equipo.
	var bonus := SkillEffects.fx(actor, "dmg")
	if actor.current_health < actor.max_health * 0.3:
		bonus += SkillEffects.fx(actor, "low_hp_dmg")
	dmg *= maxf(0.3, 1.0 + bonus) * maxf(0.3, 1.0 + SkillEffects.fx(target, "dmg_taken"))
	return dmg

func _roll_damage(actor: Character, target: Character, guard_factor: float = 1.0) -> int:
	var dmg: float = _base_damage(actor, target) * randf_range(1.0 - DAMAGE_SPREAD, 1.0 + DAMAGE_SPREAD)
	return maxi(1, roundi(dmg / guard_factor))   # un golpe que conecta nunca hace 0

func _do_attack(actor: Character, target: Character) -> String:
	if CombatEnums.Status.DESARMADO in statuses[actor]:
		combat_event.emit("unarmed", actor, actor, 0)
		return "e intenta atacar, ¡pero está desarmado!"

	_spend(actor, COST_ATTACK)

	# Esquiva preparada, o la esquiva natural de la postura de Esgrima.
	var dodge := 0.0
	if dodging[target]:
		dodging[target] = false
		dodge = dodge_chance(actor, target)
	elif posture[target] == CombatEnums.Posture.ESGRIMA:
		dodge = (ESGRIMA_PASSIVE_DODGE + SkillEffects.fx(target, "dodge")) * (0.5 if is_fatigued(target) else 1.0)
	if dodge > 0.0 and randf() < dodge:
		combat_event.emit("dodge", actor, target, 0)
		return "y ataca, ¡pero %s esquiva el golpe!" % target.full_name()

	# Parada: si sale bien, el defensor no recibe nada y devuelve un golpe completo.
	if countering[target]:
		countering[target] = false
		if randf() < parry_chance(actor, target):
			var riposte := roundi(_roll_damage(target, actor) * (PARRY_RIPOSTE_FACTOR + SkillEffects.fx(target, "riposte")))
			actor.take_damage(riposte)
			_lose_morale(actor)
			combat_event.emit("parry", target, actor, riposte)
			return "y ataca, ¡pero %s para el golpe y responde causándole %d de daño!" % [target.full_name(), riposte]
		var exposed := _roll_damage(actor, target)
		target.take_damage(exposed)
		_lose_morale(target)
		combat_event.emit("parry_fail", actor, target, exposed)
		return "y ataca; %s intenta parar, falla y recibe %d de daño." % [target.full_name(), exposed]

	var guard := 1.0
	if defending[target]:
		guard = GUARD_MITIGATION + SkillEffects.fx(target, "guard")
		defending[target] = false
	var dmg := _roll_damage(actor, target, guard)

	# Golpe crítico: 10% base, más con la habilidad Golpe Certero.
	var extra := ""
	var is_crit := false
	var crit_chance: float = SkillEffects.GOLPE_CERTERO_CRIT_CHANCE if SkillEffects.has(actor, SkillEffects.GOLPE_CERTERO) else CRIT_CHANCE
	crit_chance += SkillEffects.fx(actor, "crit")
	if randf() < crit_chance:
		dmg = roundi(dmg * (CRIT_MULTIPLIER + SkillEffects.fx(actor, "crit_mult")))
		is_crit = true
		extra += " ¡Golpe crítico!"
	# Piel de Hierro: el objetivo herido aguanta mejor los golpes.
	var target_wounded: bool = target.current_health < target.max_health * 0.3
	if target_wounded and SkillEffects.has(target, SkillEffects.PIEL_DE_HIERRO):
		dmg = maxi(1, int(dmg * SkillEffects.PIEL_DE_HIERRO_FACTOR))
		extra += " (La Piel de Hierro de %s amortigua el golpe.)" % target.full_name()
	if guard > 1.0:
		extra += " (La guardia de %s amortigua parte.)" % target.full_name()

	target.take_damage(dmg)
	combat_event.emit("crit" if is_crit else "hit", actor, target, dmg)
	_lose_morale(target)
	return "y ataca causando %d de daño.%s" % [dmg, extra]

func _do_disarm(actor: Character, target: Character) -> String:
	if is_fatigued(actor):
		combat_event.emit("winded", actor, actor, 0)
		return "e intenta desarmar a %s, pero le falta el aliento." % target.full_name()
	_spend(actor, COST_DISARM)
	if randf() < disarm_chance(actor, target):
		disarmed_turns[target] = DISARM_TURNS
		if not CombatEnums.Status.DESARMADO in statuses[target]:
			statuses[target].append(CombatEnums.Status.DESARMADO)
		combat_event.emit("disarm", actor, target, 0)
		if SkillEffects.has(actor, SkillEffects.DESARME_FULMINANTE):
			# El turno extra: aprovecha el descuido para golpear de inmediato.
			return "y logra desarmar a %s! Desarme Fulminante: aprovecha el descuido %s" % [
				target.full_name(), _do_attack(actor, target)]
		return "y logra desarmar a %s!" % target.full_name()
	combat_event.emit("miss", actor, target, 0)
	return "e intenta desarmar a %s, pero falla." % target.full_name()

# Empujar rompe la guardia: es la respuesta a quien se esconde tras Defender, Esquivar o la parada.
func _do_push(actor: Character, target: Character) -> String:
	if is_fatigued(actor):
		combat_event.emit("winded", actor, actor, 0)
		return "e intenta empujar a %s, pero le falta el aliento." % target.full_name()
	_spend(actor, COST_PUSH)
	if randf() < push_chance(actor, target):
		var had_guard: bool = defending[target] or dodging[target] or countering[target]
		defending[target] = false
		dodging[target] = false
		countering[target] = false
		target.current_stamina = maxi(0, target.current_stamina - PUSH_STAMINA_DAMAGE)
		target.current_morale = maxi(0, target.current_morale - 6)
		combat_event.emit("guard_break" if had_guard else "push", actor, target, 0)
		if had_guard:
			return "y empuja a %s, ¡rompiendo su guardia!" % target.full_name()
		return "y empuja a %s, dejándolo sin aliento." % target.full_name()
	combat_event.emit("miss", actor, target, 0)
	return "e intenta empujar a %s, sin éxito." % target.full_name()

func _do_retreat(actor: Character, target: Character, prefix: String) -> void:
	if randf() < retreat_chance(actor, target):
		actor.honor = clampi(actor.honor - RETREAT_HONOR_COST, 0, 100)
		_end_duel(null, "%s logra huir del combate (−%d de honor)." % [actor.full_name(), RETREAT_HONOR_COST])
	else:
		combat_event.emit("retreat_fail", actor, actor, 0)
		log_message.emit("%s e intenta huir, ¡pero %s se lo impide!" % [prefix, target.full_name()])
		actor.current_morale = maxi(0, actor.current_morale - 10)
		_end_turn(actor)

func _spend(c: Character, amount: int) -> void:
	var cost := roundi(amount * maxf(0.3, 1.0 + SkillEffects.fx(c, "stamina_cost")))
	c.current_stamina = maxi(0, c.current_stamina - cost)

# Templanza: algunos rasgos y habilidades reducen la moral perdida por golpe.
func _lose_morale(c: Character) -> void:
	var loss := roundi(MORALE_LOSS_PER_HIT * clampf(1.0 - SkillEffects.fx(c, "morale_resist"), 0.0, 2.0))
	c.current_morale = maxi(0, c.current_morale - loss)

func _recover(c: Character, amount: int) -> void:
	c.current_stamina = mini(c.max_stamina, c.current_stamina + amount)

func _posture_offense_bonus(p: int) -> int:
	match p:
		CombatEnums.Posture.OFENSIVA: return 4
		CombatEnums.Posture.DESESPERADA: return 6
		CombatEnums.Posture.ESGRIMA: return 1
		CombatEnums.Posture.MURO: return -2
		CombatEnums.Posture.DEFENSIVA: return -1
		_: return 0

func _posture_defense_bonus(p: int) -> int:
	match p:
		CombatEnums.Posture.DEFENSIVA: return 3
		CombatEnums.Posture.MURO: return 6
		CombatEnums.Posture.DESESPERADA: return -3
		CombatEnums.Posture.OFENSIVA: return -1
		_: return 0

func _update_statuses(c: Character) -> void:
	var s: Array = statuses[c]
	s.erase(CombatEnums.Status.HERIDO)
	s.erase(CombatEnums.Status.FATIGADO)
	s.erase(CombatEnums.Status.DESMORALIZADO)
	s.erase(CombatEnums.Status.INSPIRADO)

	if c.current_health < c.max_health * 0.3:
		s.append(CombatEnums.Status.HERIDO)
	if is_fatigued(c):
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

func _end_duel(winner: Character, reason: String, surrendered: bool = false) -> void:
	is_over = true
	_apply_duel_results(winner, surrendered)
	log_message.emit(reason)
	duel_ended.emit(winner, reason)

func _apply_duel_results(winner: Character, surrendered: bool = false) -> void:
	# Solo se registran victorias/derrotas cuando hay un ganador claro
	# (una huida exitosa con winner == null no cuenta como derrota de nadie).
	if winner == null:
		return
	var loser := opponent_of(winner)
	# Vencer a alguien más fuerte da más honor; a alguien mucho más débil, poco.
	var power_gap := (loser.combat + loser.defense) - (winner.combat + winner.defense)
	winner.register_duel_win(clampi(6 + 2 * power_gap, 3, 14))
	loser.register_duel_loss()
	# Rendirse evita la herida de caer, pero cuesta más honor y un rescate.
	if surrendered:
		loser.honor = clampi(loser.honor - SURRENDER_EXTRA_HONOR_COST, 0, 100)
		var ransom: int = mini(SURRENDER_RANSOM, loser.gold)
		loser.gold -= ransom
		winner.gold += ransom
		log_message.emit("%s paga %d de oro como rescate." % [loser.full_name(), ransom])
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
