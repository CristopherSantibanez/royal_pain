class_name RpgBattleManager
extends RefCounted
# Lógica del combate RPG (sin interfaz). Dos bandos (0 = jugador, 1 = rival) de hasta 4 activos + reserva.
#
# LÍNEA DE TURNOS (estilo FFX): cada luchador actúa cuando el reloj llega a su next_time; tras actuar
# suma TICK / Agilidad. timeline(n) predice los próximos n turnos para la interfaz.
# Una RONDA termina cuando todos los activos en pie han actuado una vez.
#
# TURNO EXTRA: cada turno da `actions` acciones (1; mini jefes 2). Golpear una debilidad o hacer un
# crítico solo sube el daño; NO da turnos, y fallar o ser resistido no los quita. Solo quien tiene la
# pasiva «brecha» (nodo «Aprovechar la brecha», Estoque, Misericordia de Toledo) gana +1 acción
# («¡Aprovecha la brecha!») al conectar una debilidad o un crítico, como mucho EXTRA_ACTIONS_MAX por turno.
#
# Acciones: atacar, tecnica, defender, objeto (gancho), cambiar (con la reserva; gasta el turno),
#           abandonar (rendirse / retirarse).
# Estados: derribado (débil a todo, retrasa su turno), desequilibrado (débil a Contundente), sangrado,
#          aturdido (pierde el turno), desarmado (−40% Fuerza), debilitado (−20% Fuerza y Defensa),
#          cegado (−25% acierto), provocado (debe atacar a quien lo provocó), marcado (+20% daño recibido);
#          a favor: inspirado, furia, guardia_esgrima, fortaleza, oculto, cubierto, guardia (Defender).

signal log_line(text: String)
signal turn_started(f)
signal action_done(info: Dictionary)
signal fighter_down(f)
signal swapped(out_f, in_f)
signal battle_ended(result: Dictionary)

const MAX_ACTIVE := 4
const TICK := 100.0
const START_JITTER := 0.1
const DMG_SCALE := 2.5
const DEF_K := 30.0                 # daño × DEF_K / (DEF_K + Defensa)
const VARIANCE := 0.1
const HIT_BASE := 0.9
const HIT_PER_POINT := 0.015        # (Puntería − Agilidad) por punto
const HIT_MIN := 0.55
const HIT_MAX := 0.98
const CRIT_BASE := 0.03
const CRIT_PER_AIM := 0.002
const CRIT_MAX := 0.5
const CRIT_MULT := 1.5
const EXTRA_ACTIONS_MAX := 1
const DOWN_DELAY := 0.5             # derribado: su turno se retrasa medio intervalo
const PT_REGEN := 2
const PT_ON_ATTACK := 3
const DEFEND_MULT := 0.5
const DEFEND_GUARD_FACTOR := 0.4    # cada +1 de "guard" quita 0,4 más al multiplicador
const DEFEND_MIN := 0.25
const DEFEND_PT := 4
const COUNTER_POW := 0.6
const ESGRIMA_COUNTER := 0.25
const ESGRIMA_EVASION := 0.12
const OCULTO_EVASION := 0.45
const OCULTO_CRIT := 0.4
const OCULTO_HIT_MIN := 0.2
const CEGADO_HIT := 0.25
const INSPIRADO_DMG := 0.15
const INSPIRADO_HIT := 0.08
const FURIA_DMG := 0.4
const FURIA_DEF := 0.85
const FORTALEZA_DEF := 1.5
const DESARMADO_STR := 0.6
const DEBILITADO_MULT := 0.8
const MARCADO_TAKEN := 0.25
const BLEED_FRAC := 0.06
const LOW_HP := 0.3
const ALLY_TAKEN_CAP := -0.2
const STATUS_WILL_REF := 10.0
const STATUS_PER_WILL := 0.02
const STATUS_RES_MAX := 0.6
const HEAL_PER_WILL := 0.02
const MORALE_BASE := 50
const MORALE_PER_WILL := 2
const MORALE_ALLY_DOWN := 12
const MORALE_LOW := 25
const MORALE_LOW_DMG := 0.9
const RETREAT_BASE := 0.45
const RETREAT_PER_AGI := 0.03
const RETREAT_MIN := 0.1
const RETREAT_MAX := 0.9
const XP_PER_NAMED_LEVEL := 8
const XP_LOSS_FRAC := 0.3
const MAX_ROUNDS := 40
const MAX_TURNS := 1000

const NEGATIVE := ["derribado", "desequilibrado", "sangrado", "aturdido", "desarmado", "debilitado", "cegado", "provocado", "marcado"]
const STATUS_NAMES := {
	"derribado": "Derribado", "desequilibrado": "Desequilibrado", "sangrado": "Sangrado", "aturdido": "Aturdido",
	"desarmado": "Desarmado", "debilitado": "Debilitado", "cegado": "Cegado", "provocado": "Provocado",
	"marcado": "Marcado", "inspirado": "Inspirado", "furia": "Furia", "guardia_esgrima": "Guardia de esgrima",
	"fortaleza": "Fortaleza", "oculto": "Oculto", "cubierto": "Cubierto", "guardia": "En guardia",
}

# IA por personalidad (ideas de DuelAI): agresividad, prudencia, astucia (debilidades y rematar), apoyo.
const P := Character.Personality
const AI_PROFILE := {
	P.ARROGANTE: [1.4, 0.4, 0.8, 0.6], P.PRUDENTE: [0.9, 1.6, 1.0, 1.2], P.ASTUTO: [1.0, 0.9, 1.8, 1.0],
	P.LEAL: [1.0, 1.1, 1.0, 1.4], P.PIADOSO: [0.9, 1.2, 0.9, 1.6], P.AMBICIOSO: [1.3, 0.8, 1.2, 0.8],
	P.VALIENTE: [1.3, 0.6, 1.0, 1.0], P.CRUEL: [1.2, 0.8, 1.5, 0.6], P.GENEROSO: [1.0, 1.1, 0.9, 1.5],
	P.COBARDE: [0.7, 1.8, 1.1, 0.9], P.ROMANTICO: [1.1, 0.7, 1.0, 1.2], P.HONORABLE: [1.1, 1.1, 0.6, 1.2],
}
const AI_WEAK_BONUS := 0.6          # valor del turno extra (pasiva «brecha») al buscar debilidades (× astucia)
const AI_RESIST_PENALTY := 0.5
const AI_KILL_BONUS := 0.5
const AI_NOISE := 0.15
const AI_COWARD_FLEE_HP := 0.25
const AI_COWARD_FLEE_CHANCE := 0.3
const AI_HEAL_THRESHOLD := 0.6
const AI_STATUS_VALUE := 0.5        # valor de un estado en «golpes equivalentes»

class Fighter extends RefCounted:
	var c: Character
	var side := 0
	var s: Dictionary = {}           # RpgStats.compute
	var hp := 0
	var max_hp := 0
	var pt := 0
	var max_pt := 0
	var morale := 50
	var statuses := {}               # id -> {turns, src, power}
	var next_time := 0.0
	var active := false
	var down := false
	var dead := false
	var participated := false
	var acted := false
	var actions_left := 0
	var extra_used := 0
	var action_index := 0
	var last_stand_used := false
	var crit_ward_used := false
	var first_sure_used := false
	func fx(k: String) -> float:
		return float(s.fx.get(k, 0.0))
	func has(st: String) -> bool:
		return statuses.has(st)
	func interval() -> float:
		return RpgBattleManager.TICK / maxf(1.0, s.agilidad)
	func hp_ratio() -> float:
		return float(hp) / maxf(1.0, max_hp)
	func up() -> bool:
		return not down and not dead
	func name() -> String:
		return c.full_name()

var fighters: Array = []
var now := 0.0
var current: Fighter = null
var round_num := 1
var turns := 0
var ended := false
var result := {}
var to_the_death := false
var can_flee := true
var item_hook := Callable()
var loot_hook := Callable()
var rng := RandomNumberGenerator.new()

## opts: to_the_death, can_flee, auto_learn ([bandos] que gastan sus puntos solos), seed, item_hook, loot_hook
func setup(side_a: Array, side_b: Array, opts: Dictionary = {}) -> void:
	to_the_death = opts.get("to_the_death", false)
	can_flee = opts.get("can_flee", true)
	item_hook = opts.get("item_hook", Callable())
	loot_hook = opts.get("loot_hook", Callable())
	if opts.has("seed"):
		rng.seed = int(opts.seed)
	var auto: Array = opts.get("auto_learn", [1])
	for side in 2:
		var list: Array = side_a if side == 0 else side_b
		for i in list.size():
			var c: Character = list[i]
			SkillTreeCatalog.ensure_kit(c)
			if side in auto and not c.has_meta("enemy_type"):   # los enemigos genéricos llevan un kit fijo
				SkillTreeCatalog.auto_learn(c)
			var f := Fighter.new()
			f.c = c
			f.side = side
			f.s = RpgStats.compute(c)
			f.max_hp = f.s.pv
			f.hp = f.max_hp
			f.max_pt = f.s.pt
			f.pt = f.max_pt
			f.morale = clampi(MORALE_BASE + roundi(f.s.voluntad * MORALE_PER_WILL), 0, 100)
			f.active = i < MAX_ACTIVE
			f.participated = f.active
			f.next_time = f.interval() * (1.0 + rng.randf() * START_JITTER)
			fighters.append(f)
	_log("¡Comienza el combate!")

# --- Consultas ---

func side_fighters(side: int) -> Array:
	return fighters.filter(func(f: Fighter) -> bool: return f.side == side)

func active_of(side: int) -> Array:
	return fighters.filter(func(f: Fighter) -> bool: return f.side == side and f.active and f.up())

func reserve_of(side: int) -> Array:
	return fighters.filter(func(f: Fighter) -> bool: return f.side == side and not f.active and f.up())

func fighter_of(c: Character) -> Fighter:
	for f: Fighter in fighters:
		if f.c == c:
			return f
	return null

## Próximos n turnos (la línea de turnos de la interfaz).
func timeline(n: int) -> Array:
	var times := {}
	var live := fighters.filter(func(f: Fighter) -> bool: return f.active and f.up())
	for f: Fighter in live:
		times[f] = f.next_time
	var out := []
	if live.is_empty():
		return out
	if current != null and current.actions_left > 0:
		out.append(current)
	while out.size() < n:
		var best: Fighter = live[0]
		for f: Fighter in live:
			if times[f] < times[best]:
				best = f
		out.append(best)
		times[best] += best.interval()
	return out

## Afinidad que tendría un golpe (para la IA y para mostrar Débil/Resiste en la interfaz).
func affinity_of(att: Fighter, def: Fighter, dt: int, fx: Dictionary = {}) -> int:
	if def.has("derribado"):
		return RpgStats.Affinity.DEBIL
	if def.has("desequilibrado") and dt == RpgStats.DamageType.CONTUNDENTE:
		return RpgStats.Affinity.DEBIL
	var a := RpgStats.affinity(dt, def.s.armor, def.s.shield)
	if a == RpgStats.Affinity.RESISTE and fx.get("pierce", 0):
		a = RpgStats.Affinity.NORMAL
	return a

func hit_chance(att: Fighter, def: Fighter, fx: Dictionary = {}) -> float:
	if def.has("derribado") or (att.fx("first_sure") > 0 and not att.first_sure_used):
		return 1.0
	var h: float = HIT_BASE + (att.s.punteria - def.s.agilidad) * HIT_PER_POINT + float(fx.get("acc", 0.0))
	if att.has("inspirado"):
		h += INSPIRADO_HIT
	if att.has("cegado"):
		h -= CEGADO_HIT
	var ev: float = def.s.evasion
	if def.has("guardia_esgrima"):
		ev += ESGRIMA_EVASION
	if def.has("oculto"):
		ev += OCULTO_EVASION
	return clampf(h - ev, OCULTO_HIT_MIN if def.has("oculto") else HIT_MIN, HIT_MAX)

func crit_chance(att: Fighter, fx: Dictionary = {}) -> float:
	var c: float = CRIT_BASE + att.s.punteria * CRIT_PER_AIM + att.s.crit + float(fx.get("crit", 0.0))
	if att.has("oculto"):
		c += OCULTO_CRIT
	return clampf(c, 0.0, CRIT_MAX)

## Daño sin azar (ni crítico ni varianza) de un golpe.
func base_damage(att: Fighter, def: Fighter, pow: float, dt: int, fx: Dictionary = {}) -> float:
	var str_: float = att.s.fuerza
	if att.has("desarmado"):
		str_ *= DESARMADO_STR
	if att.has("debilitado"):
		str_ *= DEBILITADO_MULT
	var dfn: float = def.s.defensa
	if def.has("fortaleza"):
		dfn *= FORTALEZA_DEF
	if def.has("furia"):
		dfn *= FURIA_DEF
	if def.has("debilitado"):
		dfn *= DEBILITADO_MULT
	var mult := 1.0 + att.fx("dmg_t%d" % dt) + _side_fx(att.side, "ally_dmg")
	if att.has("furia"):
		mult += FURIA_DMG
	if att.has("inspirado"):
		mult += INSPIRADO_DMG
	if att.hp_ratio() < LOW_HP:
		mult += att.fx("low_hp_dmg")
	mult += att.fx("avenge") * side_fighters(att.side).filter(func(f: Fighter) -> bool: return not f.up()).size()
	if att.morale < MORALE_LOW:
		mult *= MORALE_LOW_DMG
	if fx.has("exec") and def.hp_ratio() < LOW_HP:
		mult *= float(fx.exec)
	if fx.has("scale_missing"):
		mult *= 2.0 - att.hp_ratio()
	if fx.has("vs_status") and def.statuses.keys().any(func(k) -> bool: return k in NEGATIVE):
		mult *= float(fx.vs_status)
	if fx.has("per_ally"):
		mult *= active_of(att.side).size()
	var taken: float = 1.0 + def.s.taken + maxf(ALLY_TAKEN_CAP, _side_fx(def.side, "ally_taken"))
	if def.has("marcado"):
		taken += MARCADO_TAKEN
	if def.hp_ratio() < LOW_HP:
		taken += def.fx("low_hp_taken")
	if def.has("guardia"):
		taken *= maxf(DEFEND_MIN, DEFEND_MULT - def.fx("guard") * DEFEND_GUARD_FACTOR)
	var aff := RpgStats.affinity_mult(affinity_of(att, def, dt, fx))
	return maxf(1.0, str_ * pow * DMG_SCALE * DEF_K / (DEF_K + dfn) * mult * maxf(0.1, taken) * aff)

func _side_fx(side: int, key: String) -> float:
	var t := 0.0
	for f: Fighter in active_of(side):
		t += f.fx(key)
	return t

func techniques_of(f: Fighter) -> Array:
	return SkillTreeCatalog.available_techniques(f.c)

func usable_techniques(f: Fighter) -> Array:
	return techniques_of(f).filter(func(n: Dictionary) -> bool: return f.pt >= int(n.get("pt", 0)) and not valid_targets(f, n).is_empty())

func valid_targets(f: Fighter, n: Dictionary) -> Array:
	match n.get("tgt", "enemy"):
		"enemy", "enemies", "random3":
			return active_of(1 - f.side)
		"ally", "allies":
			return active_of(f.side)
		"self":
			return [f]
		"ko_ally":
			if to_the_death:
				return []
			return side_fighters(f.side).filter(func(o: Fighter) -> bool: return o.down and not o.dead)
	return []

# --- Turnos ---

## Avanza la línea de turnos y devuelve quién actúa (null si terminó). Si le queda una acción extra, repite.
func next_turn() -> Fighter:
	if ended:
		return null
	if current != null and current.actions_left > 0 and current.up() and current.active:
		return current
	current = null
	while not ended:
		var live := fighters.filter(func(f: Fighter) -> bool: return f.active and f.up())
		if live.is_empty():
			_check_end()
			return null
		var f: Fighter = live[0]
		for o: Fighter in live:
			if o.next_time < f.next_time:
				f = o
		now = f.next_time
		turns += 1
		_mark_round(f)
		if turns > MAX_TURNS or round_num > MAX_ROUNDS:
			_finish(-1)
			return null
		f.statuses.erase("guardia")
		f.statuses.erase("derribado")
		if f.has("sangrado"):
			var b: Dictionary = f.statuses.sangrado
			var dmg := maxi(1, roundi(f.max_hp * BLEED_FRAC * (1.0 + float(b.get("power", 0.0)))))
			_log("%s sangra (−%d)." % [f.name(), dmg])
			_damage(f, dmg, null)
			if not f.up():
				continue
		f.pt = mini(f.max_pt, f.pt + PT_REGEN + roundi(f.fx("pt_regen")))
		if f.has("aturdido"):
			f.statuses.erase("aturdido")
			_log("%s está aturdido y pierde el turno." % f.name())
			_end_turn(f)
			continue
		f.actions_left = int(f.s.actions)
		f.extra_used = 0
		f.action_index = 0
		current = f
		turn_started.emit(f)
		return f
	return null

func _mark_round(f: Fighter) -> void:
	f.acted = true
	var live := fighters.filter(func(o: Fighter) -> bool: return o.active and o.up())
	if live.all(func(o: Fighter) -> bool: return o.acted):
		round_num += 1
		for o: Fighter in fighters:
			o.acted = false

func _end_turn(f: Fighter) -> void:
	f.actions_left = 0
	for k in f.statuses.keys():
		if k in ["guardia", "derribado", "sangrado_tick"]:
			continue
		f.statuses[k].turns -= 1
		if f.statuses[k].turns <= 0:
			f.statuses.erase(k)
	f.next_time = now + f.interval()
	if current == f:
		current = null

## Ejecuta una acción del luchador que tiene el turno. action: {type, target?, node?, reserve?, mode?}
func act(f: Fighter, action: Dictionary) -> Dictionary:
	var info := {"actor": f, "type": action.get("type", "atacar"), "good": 0, "bad": 0, "hits": []}
	if ended or f != current:
		return info
	f.actions_left -= 1
	f.action_index += 1
	var ends_turn := false
	match info.type:
		"atacar":
			var t: Fighter = _redirect(f, action.get("target", null))
			if t != null:
				_log("%s ataca a %s." % [f.name(), t.name()])
				_strike(f, t, 1.0, int(f.s.weapon), {}, info)
				f.pt = mini(f.max_pt, f.pt + PT_ON_ATTACK)
		"tecnica":
			var n: Dictionary = SkillTreeCatalog.node(str(action.get("node", "")))
			if n.is_empty() or f.pt < int(n.get("pt", 0)):
				f.actions_left += 1
				f.action_index -= 1
				return info
			f.pt -= int(n.get("pt", 0))
			_log("%s usa %s." % [f.name(), n.name])
			_technique(f, n, action.get("target", null), info)
		"defender":
			_add_status(f, "guardia", 1, f)
			f.pt = mini(f.max_pt, f.pt + DEFEND_PT)
			_log("%s se pone en guardia." % f.name())
			ends_turn = true
		"objeto":
			if item_hook.is_valid():
				item_hook.call(self, f, action)
			else:
				_log("%s no tiene objetos a mano." % f.name())
			ends_turn = true
		"cambiar":
			var out_f: Fighter = action.get("out", f)
			var in_f: Fighter = action.get("reserve", null)
			if in_f == null or in_f.active or not in_f.up() or in_f.side != f.side:
				f.actions_left += 1
				f.action_index -= 1
				return info
			_swap(out_f, in_f)
			ends_turn = true
		"abandonar":
			_abandon(f, str(action.get("mode", "retirarse")))
			ends_turn = true
	if f.has("oculto") and info.type in ["atacar", "tecnica"] and not info.hits.is_empty():
		f.statuses.erase("oculto")
	# Turno extra: solo con la pasiva «brecha», al conectar debilidad o crítico, una vez por turno.
	if not ended and not ends_turn and f.up() and f.fx("brecha") > 0:
		if info.good > 0 and f.extra_used < EXTRA_ACTIONS_MAX:
			f.extra_used += 1
			f.actions_left += 1
			info["extra"] = true
			_log("¡Aprovecha la brecha! %s actúa de nuevo." % f.name())
	if ends_turn or f.actions_left <= 0 or not f.up() or not f.active:
		if f.up():
			_end_turn(f)
		elif current == f:
			current = null
	action_done.emit(info)
	_check_end()
	return info

func _redirect(f: Fighter, t: Fighter) -> Fighter:
	var foes := active_of(1 - f.side)
	if foes.is_empty():
		return null
	if f.has("provocado"):
		var src: Fighter = f.statuses.provocado.src
		if src != null and src.up() and src.active:
			t = src
	if t == null or not t in foes:
		t = foes[0]
	if t.has("cubierto"):
		var cov: Fighter = t.statuses.cubierto.src
		if cov != null and cov != t and cov.up() and cov.active and cov.side == t.side:
			_log("%s cubre a %s." % [cov.name(), t.name()])
			t = cov
	return t

## Un golpe: acierto, afinidad, crítico, daño, efectos al conectar y respuesta.
func _strike(att: Fighter, def: Fighter, pow: float, dt: int, fx: Dictionary, info: Dictionary, can_counter := true) -> bool:
	var h := {"target": def, "hit": false, "crit": false, "aff": RpgStats.Affinity.NORMAL, "dmg": 0}
	info.hits.append(h)
	if rng.randf() > hit_chance(att, def, fx):
		info.bad += 1
		_log("  ¡%s esquiva!" % def.name())
		return false
	att.first_sure_used = true
	h.hit = true
	h.aff = affinity_of(att, def, dt, fx)
	var dmg := base_damage(att, def, pow, dt, fx) * (1.0 + rng.randf_range(-VARIANCE, VARIANCE))
	if rng.randf() < crit_chance(att, fx):
		if def.fx("crit_ward") > 0 and not def.crit_ward_used:
			def.crit_ward_used = true
			_log("  La armadura de %s detiene el crítico." % def.name())
		else:
			h.crit = true
			dmg *= CRIT_MULT + att.s.crit_mult
	var amount := maxi(1, roundi(dmg))
	h.dmg = amount
	if h.aff == RpgStats.Affinity.DEBIL or h.crit:
		info.good += 1
	elif h.aff == RpgStats.Affinity.RESISTE:
		info.bad += 1
	var tag := " ¡Débil!" if h.aff == RpgStats.Affinity.DEBIL else (" Resiste." if h.aff == RpgStats.Affinity.RESISTE else "")
	_log("  %s recibe %d%s%s" % [def.name(), amount, " (crítico)" if h.crit else "", tag])
	if h.aff == RpgStats.Affinity.DEBIL:
		def.morale = maxi(0, def.morale - 5)
	_damage(def, amount, att)
	if att.fx("lifesteal") > 0:
		att.hp = mini(att.max_hp, att.hp + roundi(amount * att.fx("lifesteal")))
	if def.fx("reflect") > 0 and att.up():
		_damage(att, maxi(1, roundi(amount * def.fx("reflect"))), def)
	if att.fx("on_hit_bleed") > 0 and def.up():
		_try_status(att, def, "sangrado", 1.0, 2)
	if can_counter and def.up() and att.up() and dt != RpgStats.DamageType.PROYECTIL:
		var cc := def.fx("counter") + (ESGRIMA_COUNTER if def.has("guardia_esgrima") else 0.0)
		if cc > 0 and rng.randf() < cc:
			_log("  %s responde." % def.name())
			_strike(def, att, COUNTER_POW, int(def.s.weapon), {}, {"good": 0, "bad": 0, "hits": []}, false)
	return true

func _technique(f: Fighter, n: Dictionary, target: Variant, info: Dictionary) -> void:
	var fx: Dictionary = n.get("fx", {})
	var pow := float(n.get("pow", 0.0))
	var dt := int(n.get("dt", -1))
	if dt < 0:
		dt = int(f.s.weapon)
	var targets: Array = []
	var valid := valid_targets(f, n)
	match n.get("tgt", "enemy"):
		"enemy":
			targets = [_redirect(f, target)]
		"enemies", "allies":
			targets = valid
		"random3":
			for i in int(n.get("hits", 3)):
				if not active_of(1 - f.side).is_empty():
					targets.append(active_of(1 - f.side).pick_random())
		"self":
			targets = [f]
		"ally", "ko_ally":
			targets = [target if target in valid else (valid[0] if not valid.is_empty() else null)]
	for t in targets:
		if t == null or (t.side != f.side and not t.up()):
			continue
		var landed := true
		if pow > 0.0:
			landed = _strike(f, t, pow, dt, fx, info)
		if landed:
			for st in n.get("st", []):
				if t.side == f.side:
					_add_status(t, st[0], int(st[2]), f)
				else:
					_try_status(f, t, st[0], float(st[1]), int(st[2]))
		if n.has("heal") and t.up():
			var amt := roundi(t.max_hp * float(n.heal) * (1.0 + f.s.voluntad * HEAL_PER_WILL))
			t.hp = mini(t.max_hp, t.hp + amt)
			_log("  %s recupera %d." % [t.name(), amt])
		if fx.has("cleanse"):
			for k in t.statuses.keys():
				if k in NEGATIVE:
					t.statuses.erase(k)
		if fx.has("cover") and t != f:
			_add_status(t, "cubierto", 1, f)
		if fx.has("advance") and t != f:
			t.next_time = now + 0.001
		if fx.has("revive") and t.down and not t.dead:
			t.down = false
			t.hp = maxi(1, roundi(t.max_hp * float(fx.revive)))
			t.active = active_of(f.side).size() < MAX_ACTIVE
			t.next_time = now + t.interval()
			_log("  ¡%s se levanta!" % t.name())
		if fx.has("pt_drain") and t.side != f.side:
			var d := mini(t.pt, int(fx.pt_drain))
			t.pt -= d
			f.pt = mini(f.max_pt, f.pt + d)
		if fx.has("morale"):
			t.morale = mini(100, t.morale + int(fx.morale))
	for st in fx.get("self_st", []):
		_add_status(f, st[0], int(st[1]), f)

func _add_status(t: Fighter, st: String, turns_: int, src: Fighter) -> void:
	# Lo que se pone uno mismo en su turno dura turns_ turnos completos a partir del siguiente.
	var extra := 1 if t == current and st != "guardia" else 0
	t.statuses[st] = {"turns": turns_ + extra, "src": src, "power": src.fx("bleed_bonus") if src else 0.0}

func _try_status(att: Fighter, def: Fighter, st: String, chance: float, turns_: int) -> bool:
	if st in ["derribado", "desequilibrado"] and def.fx("immune_derribo") > 0:
		return false
	var res := clampf((def.s.voluntad - STATUS_WILL_REF) * STATUS_PER_WILL + def.fx("status_res"), 0.0, STATUS_RES_MAX)
	if rng.randf() >= chance * (1.0 - res):
		return false
	_add_status(def, st, turns_, att)
	if st == "derribado":
		def.next_time += def.interval() * DOWN_DELAY
	_log("  %s: %s." % [def.name(), STATUS_NAMES.get(st, st)])
	return true

func _damage(t: Fighter, amount: int, _src: Fighter) -> void:
	t.hp -= amount
	if t.hp > 0:
		return
	if t.fx("last_stand") > 0 and not t.last_stand_used:
		t.last_stand_used = true
		t.hp = 1
		_log("  ¡%s aguanta en pie!" % t.name())
		return
	t.hp = 0
	t.down = true
	t.dead = to_the_death
	t.statuses.clear()
	t.active = false
	_log("%s %s." % [t.name(), "muere" if t.dead else "cae"])
	fighter_down.emit(t)
	for o: Fighter in side_fighters(t.side):
		if o.up():
			o.morale = maxi(0, o.morale - MORALE_ALLY_DOWN)
	var res := reserve_of(t.side)
	if not res.is_empty():
		var r: Fighter = res[0]
		r.active = true
		r.participated = true
		r.next_time = now + r.interval()
		_log("%s entra al combate." % r.name())
		swapped.emit(t, r)
	if current == t:
		current = null

func _swap(out_f: Fighter, in_f: Fighter) -> void:
	out_f.active = false
	in_f.active = true
	in_f.participated = true
	in_f.next_time = now + in_f.interval()
	_log("%s se retira y entra %s." % [out_f.name(), in_f.name()])
	swapped.emit(out_f, in_f)

func _abandon(f: Fighter, mode: String) -> void:
	if mode == "rendirse":
		if to_the_death:
			_log("En una lucha a muerte no se acepta la rendición.")
			return
		_log("%s se rinde." % ("Tu grupo" if f.side == 0 else "El rival"))
		result["surrendered"] = f.side
		_finish(1 - f.side)
		return
	if not can_flee:
		_log("No hay escapatoria.")
		return
	var mine := active_of(f.side)
	var foes := active_of(1 - f.side)
	var diff := _avg(mine, "agilidad") - _avg(foes, "agilidad")
	var best_fx := 0.0
	for o: Fighter in mine:
		best_fx = maxf(best_fx, o.fx("retreat"))
	var chance := clampf(RETREAT_BASE + diff * RETREAT_PER_AGI + best_fx, RETREAT_MIN, RETREAT_MAX)
	if rng.randf() < chance:
		_log("%s se retira del combate." % ("Tu grupo" if f.side == 0 else "El rival"))
		result["retreated"] = f.side
		_finish(1 - f.side)
	else:
		_log("¡La retirada falla!")

func _avg(list: Array, stat: String) -> float:
	if list.is_empty():
		return 0.0
	var t := 0.0
	for f: Fighter in list:
		t += float(f.s[stat])
	return t / list.size()

func _check_end() -> void:
	if ended:
		return
	var a := side_fighters(0).any(func(f: Fighter) -> bool: return f.up())
	var b := side_fighters(1).any(func(f: Fighter) -> bool: return f.up())
	if not a or not b:
		_finish(0 if a else (1 if b else -1))

func _finish(winner: int) -> void:
	if ended:
		return
	ended = true
	current = null
	var ko: Array[Character] = []
	var dead: Array[Character] = []
	var hp := {}
	var xp_pool := 0
	for f: Fighter in fighters:
		hp[f.c] = [f.hp, f.max_hp]
		if f.dead:
			dead.append(f.c)
		elif f.down:
			ko.append(f.c)
		if f.side == 1 and f.down:
			xp_pool += EnemyCatalog.xp_value(f.c) if f.c.has_meta("enemy_type") else f.c.level * XP_PER_NAMED_LEVEL
	var xp := {}
	for f: Fighter in side_fighters(0):
		if f.participated and not f.dead:
			xp[f.c] = xp_pool if winner == 0 else roundi(xp_pool * XP_LOSS_FRAC)
	result.merge({"winner": winner, "rounds": round_num, "turns": turns, "ko": ko, "dead": dead,
		"hp": hp, "xp": xp, "loot": [], "to_the_death": to_the_death})
	result.merge({"retreated": -1, "surrendered": -1})
	if winner == 0 and loot_hook.is_valid():
		loot_hook.call(result)
	_log("Fin del combate.")
	battle_ended.emit(result)

func _log(t: String) -> void:
	log_line.emit(t)

# --- IA ---

## Elige la acción del luchador según su personalidad; aprovecha debilidades, remata y apoya.
func ai_choose(f: Fighter) -> Dictionary:
	var prof: Array = AI_PROFILE.get(f.c.personality, [1.0, 1.0, 1.0, 1.0])
	var aggr: float = prof[0]
	var caution: float = prof[1]
	var cunning: float = prof[2]
	var support: float = prof[3]
	var foes := active_of(1 - f.side)
	if foes.is_empty():
		return {"type": "defender"}
	if f.side == 1 and can_flee and f.c.personality == P.COBARDE and f.hp_ratio() < AI_COWARD_FLEE_HP \
			and rng.randf() < AI_COWARD_FLEE_CHANCE:
		return {"type": "abandonar", "mode": "retirarse"}
	var ref := _avg_hit(f, foes)   # un golpe normal: unidad de valor
	var best := {"type": "atacar", "target": foes[0]}
	var best_score := -INF
	for t: Fighter in foes:
		var sc := _score_hit(f, t, 1.0, int(f.s.weapon), {}, cunning) * aggr
		if sc > best_score:
			best_score = sc
			best = {"type": "atacar", "target": t}
	for n: Dictionary in usable_techniques(f):
		var fx: Dictionary = n.get("fx", {})
		var pow := float(n.get("pow", 0.0))
		var dt := int(n.get("dt", -1))
		if dt < 0:
			dt = int(f.s.weapon)
		var pt_cost := float(n.get("pt", 0)) / maxf(1.0, f.max_pt) * ref * 0.5
		var tgts := valid_targets(f, n)
		var cands: Array = tgts if n.tgt in ["enemy", "ally", "ko_ally"] else [null]
		for t in cands:
			var sc := 0.0
			var group: Array = [t] if t != null else (tgts if n.tgt != "random3" else [])
			if n.tgt == "random3":
				for o: Fighter in foes:
					sc += _score_hit(f, o, pow, dt, fx, cunning) * int(n.get("hits", 3)) / foes.size()
			for o in group:
				if o == null:
					continue
				if o.side != f.side:
					if pow > 0:
						sc += _score_hit(f, o, pow, dt, fx, cunning)
					for st in n.get("st", []):
						if not o.has(st[0]):
							sc += float(st[1]) * ref * AI_STATUS_VALUE * cunning * (2.0 if st[0] in ["aturdido", "derribado"] else 1.0)
				else:
					if n.has("heal"):
						var miss: float = 1.0 - o.hp_ratio()
						if o.hp_ratio() < AI_HEAL_THRESHOLD:
							sc += miss * o.max_hp * float(n.heal) * 4.0 * support
					if fx.has("revive"):
						sc += ref * 3.0 * support
					if fx.has("cover") and o != f and o.hp_ratio() < 0.4 and not o.has("cubierto"):
						sc += ref * 0.8 * support
					if fx.has("advance") and o != f:
						sc += ref * 0.7 * support
					for st in n.get("st", []):
						if not o.has(st[0]):
							var w := caution if st[0] in ["fortaleza", "guardia_esgrima", "oculto"] else aggr
							sc += ref * AI_STATUS_VALUE * w * (1.5 if o == f else 1.0)
			if fx.has("self_st") and not f.has("fortaleza"):
				sc += ref * 0.3 * caution
			sc = (sc - pt_cost) * aggr if pow > 0 else sc - pt_cost
			if sc > best_score:
				best_score = sc
				best = {"type": "tecnica", "node": n.id, "target": t}
	var defend := ref * caution * (1.0 - f.hp_ratio()) * 0.8
	if defend > best_score:
		best = {"type": "defender"}
	return best

func _score_hit(f: Fighter, t: Fighter, pow: float, dt: int, fx: Dictionary, cunning: float) -> float:
	var hitp := hit_chance(f, t, fx)
	var dmg := base_damage(f, t, pow, dt, fx) * (1.0 + crit_chance(f, fx) * 0.5)
	var sc := minf(dmg, t.hp) * hitp
	var aff := affinity_of(f, t, dt, fx)
	if aff == RpgStats.Affinity.DEBIL and f.fx("brecha") > 0:
		sc *= 1.0 + AI_WEAK_BONUS * cunning
	elif aff == RpgStats.Affinity.RESISTE:
		sc *= 1.0 - AI_RESIST_PENALTY * minf(1.0, cunning)
	if dmg >= t.hp:
		sc *= 1.0 + AI_KILL_BONUS * cunning
	return sc * (1.0 + rng.randf_range(-AI_NOISE, AI_NOISE))

func _avg_hit(f: Fighter, foes: Array) -> float:
	var t := 0.0
	for o: Fighter in foes:
		t += base_damage(f, o, 1.0, int(f.s.weapon))
	return t / maxf(1.0, foes.size())

## Combate entero con IA en ambos bandos (simulaciones, «Resolver»). Devuelve el resultado.
func run_auto() -> Dictionary:
	while not ended:
		var f := next_turn()
		if f == null:
			break
		act(f, ai_choose(f))
	return result
