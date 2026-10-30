class_name CampalEncounters
extends RefCounted

# Fase 4: cada choque cuerpo a cuerpo entre pelotones es un combate RPG jefe+oficiales contra jefe+oficiales.
# Las tropas del pelotón dan estadísticas a sus personajes; el resultado se traduce en bajas, moral o retirada.

const MAX_OFFICERS := 3
const MAX_PARTY := 5                  # jefe + oficiales + escolta genérica
const ESCORT_SOLDIERS := 10           # un escolta genérico por cada 10 soldados del pelotón...
const MIN_ESCORT := 1                 # ...con al menos uno
const GENERIC_LEVEL := 3              # nivel de la escolta si nadie con nombre da referencia
const CAPTAIN_TYPE := "sargento_veterano"
const ESCORT_BY_TYPE := {
	BattleEnums.UnitType.INFANTERIA: "soldado", BattleEnums.UnitType.INFANTERIA_PESADA: "infanteria_pesada",
	BattleEnums.UnitType.ARQUEROS: "arquero", BattleEnums.UnitType.BALLESTEROS: "ballestero",
	BattleEnums.UnitType.CABALLERIA: "caballero_montado", BattleEnums.UnitType.CABALLERIA_PESADA: "caballero_pesado",
	BattleEnums.UnitType.PIQUEROS: "piquero", BattleEnums.UnitType.LANCEROS: "piquero",
}

# Bonos de la tropa a los personajes de su pelotón.
const TROOP_PV_PER_SOLDIER := 0.015   # +1,5% de PV por soldado...
const TROOP_PV_CAP := 0.6             # ...hasta +60%
const TROOP_STR_PER_SOLDIER := 0.008  # +0,8% de Fuerza por soldado...
const TROOP_STR_CAP := 0.3            # ...hasta +30%
const CAV_AGI := 4.0                  # caballería: más rápida...
const CAV_CHARGE_STR := 0.1           # ...y su carga pega más
const PIKE_DEF_VS_CAV := 6.0          # picas contra caballería
const INF_DEF := 2.0
const ARCHER_AIM := 4.0
const TROOP_MORALE_PIVOT := 50        # la moral del pelotón sube o baja la del personaje
const TROOP_MORALE_DIV := 3

# Del combate a los pelotones.
const WIN_DMG := 1.35                 # bajas que causa quien gana el choque (× las del tablero)
const LOSS_DMG := 0.5                 # bajas que aún causa quien lo pierde
const LOSER_TAKEN := 1.5              # bajas que recibe quien pierde (× la respuesta normal)
const FLEE_TAKEN := 0.8               # quien se retira a tiempo recibe menos que si pierde
const WIN_MORALE := 4
const LOSS_MORALE := 12
const FLEE_MORALE := 6
const LEADER_DOWN_MORALE := 10        # ver caer al jefe hunde al pelotón
const KO_HP_FLOOR := 0.3              # un caído vuelve al siguiente choque con esta parte de sus PV

# Traición y abandono.
const ABANDON_CHANCE := 0.35          # un miembro desleal del grupo puede dejarte solo en un choque
const DEFECT_CHANCE := 0.12           # por turno, un pelotón con jefe desleal puede pasarse al enemigo...
const DEFECT_MAX_RATIO := 1.0         # ...solo si su bando no va ganando (fuerza propia / rival ≤ esto)
const OFFICER_DEFECT_CHANCE := 0.1

# Botín.
const LOOT_GOLD_PER_ENEMY := 2        # oro por soldado enemigo caído o huido
const LOOT_SHARE := 0.3               # parte que repartes con tu séquito
const LOOT_ITEM_CHANCE := 0.5         # objeto tras un choque ganado por tu grupo
const CONSUMABLES := "res://scripts/resources/consumable_catalog.gd"

# --- Grupos ---

static func is_generic(c: Character) -> bool:
	return c == null or c.has_meta("captain") or c.has_meta("enemy_type")

static func _level_ref(bm: BattleManager, a: BattleUnit, b: BattleUnit) -> int:
	var total := 0
	var n := 0
	for u: BattleUnit in [a, b]:
		for c: Character in [u.leader()] + u.officers:
			if not is_generic(c):
				total += c.level
				n += 1
	return maxi(1, roundi(float(total) / n)) if n > 0 else GENERIC_LEVEL

## Jefe + oficiales con nombre + escolta genérica según los soldados (hasta MAX_PARTY).
static func party_of(u: BattleUnit, level: int) -> Array:
	var out := []
	var lead := u.leader()
	if lead != null and not lead.has_meta("captain"):
		out.append(lead)
	else:
		var cap := EnemyCatalog.make_enemy(CAPTAIN_TYPE, level)
		cap.first_name = lead.full_name() if lead != null else cap.first_name
		out.append(cap)
	for o: Character in u.officers:
		if out.size() < MAX_OFFICERS + 1 and o != null and not o in out:
			out.append(o)
	var escort := clampi(ceili(float(u.soldiers) / ESCORT_SOLDIERS), MIN_ESCORT, MAX_PARTY)
	var used := {}
	var t: String = ESCORT_BY_TYPE.get(u.type, "soldado")
	while out.size() < MAX_PARTY and escort > 0:
		var e := EnemyCatalog.make_enemy(t, level, 0, used)
		e.last_name = char(65 + escort)
		out.append(e)
		escort -= 1
	return out

static func set_troops(chars: Array, u: BattleUnit, foe: BattleUnit) -> void:
	for c: Character in chars:
		c.set_meta("campal_troops", {"soldiers": u.soldiers, "type": u.type, "family": u.family(),
			"morale": u.morale, "foe_family": foe.family()})

static func clear_troops(chars: Array) -> void:
	for c: Character in chars:
		if c.has_meta("campal_troops"):
			c.remove_meta("campal_troops")

## Lo llama RpgBattleManager.setup: suma a un luchador lo que le da la tropa de su pelotón.
static func apply_troop_bonus(f) -> void:
	var t: Dictionary = f.c.get_meta("campal_troops", {})
	if t.is_empty():
		return
	var n := int(t.soldiers)
	var fam := int(t.family)
	f.max_hp = maxi(1, roundi(f.max_hp * (1.0 + minf(TROOP_PV_CAP, n * TROOP_PV_PER_SOLDIER))))
	f.hp = f.max_hp
	var str_mult := 1.0 + minf(TROOP_STR_CAP, n * TROOP_STR_PER_SOLDIER)
	match fam:
		BattleEnums.Family.CABALLERIA:
			f.s.agilidad = float(f.s.agilidad) + CAV_AGI
			str_mult += CAV_CHARGE_STR
		BattleEnums.Family.PIQUEROS:
			if int(t.foe_family) == BattleEnums.Family.CABALLERIA:
				f.s.defensa = float(f.s.defensa) + PIKE_DEF_VS_CAV
		BattleEnums.Family.INFANTERIA:
			f.s.defensa = float(f.s.defensa) + INF_DEF
		BattleEnums.Family.ARQUERIA:
			f.s.punteria = float(f.s.punteria) + ARCHER_AIM
	f.s.fuerza = float(f.s.fuerza) * str_mult
	f.morale = clampi(f.morale + (int(t.morale) - TROOP_MORALE_PIVOT) / TROOP_MORALE_DIV, 0, 100)

## Técnicas con «req_troops» o «req_morale»: solo si el pelotón del personaje los cumple (fuera de campales no cuentan).
static func technique_allowed(c: Character, n: Dictionary) -> bool:
	if not n.has("req_troops") and not n.has("req_morale"):
		return true
	var t: Dictionary = c.get_meta("campal_troops", {})
	if t.is_empty():
		return true
	return int(t.soldiers) >= int(n.get("req_troops", 0)) and int(t.morale) >= int(n.get("req_morale", 0))

# --- Choques ---

## Prepara el choque: grupos de ambos lados (A = atacante), con su tropa. Un miembro desleal del grupo puede abandonarlo.
static func make(bm: BattleManager, attacker: BattleUnit, target: BattleUnit, dist: int) -> Dictionary:
	var lv := _level_ref(bm, attacker, target)
	var a := party_of(attacker, lv)
	var b := party_of(target, lv)
	var notes: Array[String] = []
	for list: Array in [a, b]:
		for c: Character in list.duplicate():
			if c != list[0] and not is_generic(c) and c != bm.player_leader and _disloyal(c) and randf() < bm.abandon_chance():
				list.erase(c)
				notes.append("%s abandona el choque." % c.full_name())
	set_troops(a, attacker, target)
	set_troops(b, target, attacker)
	return {"attacker": attacker, "target": target, "dist": dist, "a": a, "b": b, "notes": notes}

static func _disloyal(c: Character) -> bool:
	var loy = _autoload("LoyaltyData")
	return loy != null and loy.is_disloyal(c)

static func _autoload(n: String) -> Node:
	var loop := Engine.get_main_loop()
	return loop.root.get_node_or_null(n) if loop is SceneTree else null

## ¿Está en el choque tu personaje o alguien de tu grupo?
static func involves_player(bm: BattleManager, enc: Dictionary) -> bool:
	var mine := player_party(bm)
	for c in enc.a + enc.b:
		if c in mine:
			return true
	return false

static func player_party(bm: BattleManager) -> Array:
	var out := [bm.player_leader]
	var pd = _autoload("PartyData")
	if pd != null:
		out.append_array(pd.members())
	return out

## Lado del jugador en el choque: 0 = el atacante, 1 = el objetivo.
static func friendly_index(bm: BattleManager, enc: Dictionary) -> int:
	return 1 if bm.is_friendly(enc.target) else 0

## Salud dentro de la batalla (no toca la del personaje): los caídos vuelven con poca vida.
static func apply_hp(bm: BattleManager, mgr: RpgBattleManager) -> void:
	for f in mgr.fighters:
		if bm.encounter_hp.has(f.c):
			f.hp = clampi(roundi(f.max_hp * float(bm.encounter_hp[f.c])), 1, f.max_hp)

static func store_hp(bm: BattleManager, result: Dictionary) -> void:
	for c in result.get("hp", {}):
		if is_generic(c):
			continue
		var pair: Array = result.hp[c]
		bm.encounter_hp[c] = maxf(KO_HP_FLOOR, float(pair[0]) / maxf(1.0, pair[1]))

## Resuelve el choque solo, con las reglas del RPG.
static func auto_fight(bm: BattleManager, enc: Dictionary) -> Dictionary:
	var mgr := RpgBattleManager.new()
	mgr.setup(enc.a, enc.b, {"auto_learn": [0, 1]})
	apply_hp(bm, mgr)
	return mgr.run_auto()

## Traduce el resultado (bando 0 = atacante) en bajas, moral y retirada. Devuelve el texto del registro.
static func apply(bm: BattleManager, enc: Dictionary, result: Dictionary) -> String:
	var att: BattleUnit = enc.attacker
	var tgt: BattleUnit = enc.target
	store_hp(bm, result)
	clear_troops(enc.a + enc.b)
	var fled := int(result.get("retreated", -1))
	var winner := int(result.get("winner", -1))
	if fled >= 0:
		winner = 1 - fled
	var base_out: int = bm._compute_casualties(att, tgt, enc.dist, true)
	var base_back: int = maxi(1, int(bm._compute_casualties(tgt, att, enc.dist, true) * bm._retaliation(tgt)))
	var to_tgt: float = base_out * (WIN_DMG if winner == 0 else LOSS_DMG)
	var to_att: float = base_back * (LOSER_TAKEN if winner == 1 else LOSS_DMG)
	if fled == 0:
		to_att = base_back * FLEE_TAKEN
	elif fled == 1:
		to_tgt = base_out * FLEE_TAKEN
	var k_tgt := roundi(to_tgt)
	var k_att := roundi(to_att)
	bm._apply_casualties(tgt, k_tgt)
	bm._apply_casualties(att, k_att)
	var who := ["%s (%s)" % [BattleEnums.unit_type_name(att.type), bm._side_label(att.side)],
		"%s (%s)" % [BattleEnums.unit_type_name(tgt.type), bm._side_label(tgt.side)]]
	var text := "Choque: %s contra %s. " % who
	var units := [att, tgt]
	if winner in [0, 1]:
		var w: BattleUnit = units[winner]
		var l: BattleUnit = units[1 - winner]
		w.morale = mini(100, w.morale + WIN_MORALE)
		if fled == 1 - winner:
			l.morale = maxi(0, l.morale - FLEE_MORALE)
			text += "%s se retira a tiempo. " % who[1 - winner]
		else:
			l.morale = maxi(0, l.morale - LOSS_MORALE)
			text += "Gana %s. " % who[winner]
		var lead: Character = (enc.a if winner == 1 else enc.b)[0]
		if lead in result.get("ko", []) or lead in result.get("dead", []):
			l.morale = maxi(0, l.morale - LEADER_DOWN_MORALE)
			text += "¡Cae su jefe! "
			bm._wound_companion(l, BattleManager.WOUND_CHANCE_ROUTED)
	text += "Bajas: %d y %d." % [k_tgt, k_att]
	if winner == friendly_index(bm, enc) and involves_player(bm, enc) and randf() < LOOT_ITEM_CHANCE:
		var got := grant_item()
		if not got.is_empty():
			text += " " + got
	for n: String in enc.get("notes", []):
		text = n + " " + text
	return text

# --- Botín ---

## Un objeto consumible para tu bolsa (si existe el sistema de objetos).
static func grant_item() -> String:
	var gm := _autoload("GameManager")
	var player: Character = gm.player_character if gm != null else null
	if player == null or not ResourceLoader.exists(CONSUMABLES) or not "consumables" in player:
		return ""
	var cat = load(CONSUMABLES)
	return cat.grant_random(player.consumables, 1) if cat.has_method("grant_random") else ""

## Tras ganar la batalla: oro por los enemigos caídos, parte repartida con tu séquito, y quizá un objeto.
static func battle_loot(bm: BattleManager, won: bool) -> String:
	var gm := _autoload("GameManager")
	var player: Character = gm.player_character if gm != null else null
	if not won or player == null:
		return ""
	var foe := bm._other_side(bm.player_side)
	var lost: int = maxi(0, int(bm._initial_soldiers.get(foe, 0)) - bm.total_soldiers(foe))
	var gold := lost * LOOT_GOLD_PER_ENEMY
	var lines: Array[String] = []
	if gold > 0:
		player.gold += gold
		lines.append("Botín: %d de oro." % gold)
		var loy := _autoload("LoyaltyData")
		var rel := _autoload("RelationsData")
		var share := roundi(gold * LOOT_SHARE)
		if loy != null and rel != null and not rel.retinue.is_empty() and share > 0:
			lines.append(loy.share_loot(share))
	var got := grant_item()
	if not got.is_empty():
		lines.append(got)
	return " ".join(lines)
