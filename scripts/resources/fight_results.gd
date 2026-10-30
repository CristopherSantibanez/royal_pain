class_name FightResults
extends RefCounted
# Desenlace de un combate de campaña (duelo de honor 1v1 o combate de grupo): lo que antes hacía el
# final de scenes/combat/combat.gd. La escena del combate (scenes/rpg_battle) solo pinta; aquí se
# aplican honor, oro, récord de duelos, deshonra, muerte, experiencia (XpRules), campeón, torneo,
# capturas (CaptureData), práctica sin heridas y heridas al terminar.

const XpRules = preload("res://scripts/resources/xp_rules.gd")
const UniqueItems = preload("res://scripts/resources/unique_items.gd")
const RETREAT_HONOR_COST := 3            # huir (como en el duelo antiguo)
const SURRENDER_EXTRA_HONOR_COST := 3    # rendirse: además de la derrota (−5)
const SURRENDER_RANSOM := 25
const TOURNAMENT_FAME := 10
const CHAMPION_WIN_HONOR := 3
const CHAMPION_WIN_FAME := 2
const CHAMPION_LOSS_HONOR := -2
const CHAMPION_OWNER_XP_SHARE := 0.25    # parte de la experiencia del campeón que recibe su señor

var owner: Character          # el personaje del jugador (aunque luche un campeón por él)
var fighter: Character        # quien lucha por el jugador (él mismo o su campeón)
var enemy: Character          # el rival (jefe del grupo enemigo)
var champion: Character       # campeón del séquito o null
var companions: Array = []    # compañeros que lucharon a tu lado (combate de grupo)
var practice := false
var practice_snapshot := {}   # Character -> estado previo
var honor_before := 0
var gold_before := 0
var demotion_text := ""
var log_lines: Array[String] = []   # líneas extra para el registro de la escena

func _init(owner_: Character = null, fighter_: Character = null, enemy_: Character = null) -> void:
	owner = owner_
	fighter = fighter_
	enemy = enemy_
	if owner != null:
		honor_before = owner.honor
		gold_before = owner.gold

func snapshot_practice(chars: Array) -> void:
	practice = true
	for c: Character in chars:
		practice_snapshot[c] = {"honor": c.honor, "gold": c.gold, "role": c.role, "health": c.current_health,
			"won": c.duels_won, "lost": c.duels_lost, "wounds": c.wound_months}

## Pasa los PV del combate RPG a la vida del personaje (la de los enemigos genéricos no importa).
static func sync_health(mgr: RpgBattleManager) -> void:
	for f in mgr.fighters:
		var c: Character = f.c
		if c.has_meta("enemy_type") or c.max_health <= 0:
			continue
		c.current_health = 0 if f.hp <= 0 else clampi(roundi(c.max_health * float(f.hp) / maxf(1.0, f.max_hp)), 1, c.max_health)

## PV de partida según la vida que traiga cada personaje con nombre (heridas, torneo…).
static func apply_start_health(mgr: RpgBattleManager) -> void:
	for f in mgr.fighters:
		var c: Character = f.c
		if c.has_meta("enemy_type") or c.max_health <= 0:
			continue
		f.hp = clampi(roundi(f.max_hp * float(c.current_health) / c.max_health), 1, f.max_hp)

## Ganador como personaje (null = huida o nadie) a partir del resultado del RpgBattleManager.
func winner_of(result: Dictionary) -> Character:
	if int(result.get("retreated", -1)) >= 0:
		return null
	match int(result.get("winner", -1)):
		0: return fighter
		1: return enemy
	return null

## Récord, honor, rescate y deshonra (lo que hacía DuelManager al terminar). Devuelve líneas de registro.
func apply_record(result: Dictionary) -> void:
	var fled := int(result.get("retreated", -1))
	if fled >= 0:
		var who: Character = fighter if fled == 0 else enemy
		who.honor = clampi(who.honor - RETREAT_HONOR_COST, 0, 100)
		log_lines.append("%s logra huir del combate (−%d de honor)." % [who.full_name(), RETREAT_HONOR_COST])
		return
	var winner := winner_of(result)
	if winner == null:
		return
	var loser: Character = enemy if winner == fighter else fighter
	var power_gap := (loser.combat + loser.defense) - (winner.combat + winner.defense)
	winner.register_duel_win(clampi(6 + 2 * power_gap, 3, 14))
	loser.register_duel_loss()
	if int(result.get("surrendered", -1)) >= 0:
		loser.honor = clampi(loser.honor - SURRENDER_EXTRA_HONOR_COST, 0, 100)
		var ransom: int = mini(SURRENDER_RANSOM, loser.gold)
		loser.gold -= ransom
		winner.gold += ransom
		log_lines.append("%s paga %d de oro como rescate." % [loser.full_name(), ransom])
	if RoleProgression.check_dishonor_demotion(loser):
		var old_role := loser.role
		RoleProgression.apply_dishonor_demotion(loser)
		log_lines.append("%s cae en deshonra y desciende de %s a %s." % [loser.full_name(), Character.role_name_for(old_role), loser.role_name()])
		if loser == fighter:
			demotion_text = "Caes en deshonra: de %s a %s." % [Character.role_name_for(old_role), Character.role_name_for(loser.role)]

## Duelo dentro de una batalla: solo récord y experiencia del luchador.
func finish_embedded(result: Dictionary) -> Character:
	apply_record(result)
	var winner := winner_of(result)
	if winner != null and fighter.is_alive():
		var xp := xp_line(fighter, XpRules.BATTLE_DUEL_WIN if winner == fighter else XpRules.BATTLE_DUEL_LOSS)
		if not xp.is_empty():
			log_lines.append(xp)
	return winner

## Práctica: se deshace lo que el combate haya cambiado; solo quedan experiencia y confianza.
func finish_practice(result: Dictionary) -> String:
	var winner := winner_of(result)
	for c: Character in practice_snapshot:
		var s: Dictionary = practice_snapshot[c]
		c.honor = s.honor
		c.gold = s.gold
		c.role = s.role
		c.current_health = s.health
		c.duels_won = s.won
		c.duels_lost = s.lost
		c.wound_months = s.wounds
	demotion_text = ""
	var text := RelationsData.finish_practice(winner == fighter, winner == null)
	CombatSetup.last_result_text = text
	return text

## Desenlace completo de un combate de campaña. Devuelve {text, trophy (bool), next_round (bool), death_owner (bool)}.
func finish_campaign(result: Dictionary) -> Dictionary:
	apply_record(result)
	var winner := winner_of(result)
	var out := {"text": "", "trophy": false, "next_round": false, "death_owner": false}
	var event_foe: bool = CombatSetup.pending_outcome.get("no_rival", false)
	var event_fight := not CombatSetup.pending_outcome.is_empty()
	var death := resolve_death(result, winner)
	out.death_owner = not owner.is_alive() or owner in result.get("dead", [])
	var rivalry := "" if event_foe else RelationsData.register_duel(enemy, winner == fighter, winner == null)
	var outcome := CombatSetup.apply_outcome(winner == fighter)
	if not outcome.is_empty():
		rivalry = (rivalry + " " + outcome).strip_edges()
	rivalry += champion_outcome(winner)
	if MissionData.has_method("on_duel_finished"):
		MissionData.on_duel_finished(enemy, winner == fighter)
	rivalry = " ".join([rivalry, death, award_xp(winner, event_fight)]).strip_edges()
	var loot: Array = result.get("loot", [])
	if not loot.is_empty():
		rivalry += " Botín: %s." % ", ".join(loot.map(func(id) -> String: return ConsumableCatalog.item_name(str(id))))
	if not CombatSetup.is_tournament():
		var caught := CaptureData.after_duel(owner, fighter, enemy, winner, event_fight or hostile_foe())
		if not caught.is_empty():
			rivalry = (rivalry + " " + caught).strip_edges()
			if CaptureData.is_captive():
				CombatSetup.return_scene = "res://scenes/map/map.tscn"
	if CombatSetup.is_tournament():
		var t := tournament_round_ended(winner, rivalry)
		out.text = t.text
		out.next_round = t.next_round
		return out
	# Las heridas no se curan solas al terminar: la vida se recupera con los meses.
	var wound := fighter.after_fight_recovery() if champion == null and fighter.is_alive() else ""
	for c: Character in companions:
		if c != fighter and c.is_alive():
			c.after_fight_recovery()
	CombatSetup.last_result_text = " ".join([campaign_summary(winner), rivalry, wound]).strip_edges()
	out.text = CombatSetup.last_result_text
	out.trophy = winner == fighter and not event_foe
	return out

## ¿Es un enemigo de verdad (rival enconado, némesis o de un reino en guerra con el tuyo)?
func hostile_foe() -> bool:
	var r := RelationsData.get_relation(enemy.full_name())
	if r == null:
		return false
	if r.at_war or r.rivalry_stage() in [Relationship.RivalryStage.RIVAL, Relationship.RivalryStage.NEMESIS]:
		return true
	return r.kingdom >= 0 and GameManager.player_kingdom >= 0 \
		and KingdomDiplomacy.at_war(RelationsData.kingdom_wars, r.kingdom, GameManager.player_kingdom)

## Lucha a muerte: quien cae muere. Rendirse o huir salva la vida.
func resolve_death(result: Dictionary, winner: Character) -> String:
	if not CombatSetup.duel_to_death:
		return ""
	var lines: Array[String] = []
	var killer := winner.full_name() if winner != null else "sus enemigos"
	for c: Character in result.get("dead", []):
		if c.has_meta("enemy_type"):
			continue
		c.current_health = 0
		var cause := "en un duelo a muerte contra %s" % killer if c == owner or c == fighter or c in companions else "en un duelo a muerte"
		if c == owner:
			if DynastyData.has_method("on_player_died"):
				DynastyData.on_player_died(cause)
			CombatSetup.return_scene = "res://scenes/map/map.tscn"   # el mapa abre la sucesión
			log_lines.append("☠ %s muere %s." % [c.full_name(), cause])
			lines.append("☠ Has muerto %s. Tu dinastía buscará un heredero." % cause)
			continue
		if RelationsData.has_method("on_character_died"):
			RelationsData.on_character_died(c.full_name(), "duelo a muerte")
		log_lines.append("☠ %s muere %s." % [c.full_name(), cause])
		if c == champion:
			lines.append("☠ Tu campeón %s muere en el duelo." % c.full_name())
		elif c in companions:
			lines.append("☠ %s muere a tu lado." % c.full_name())
		else:
			lines.append("☠ %s muere a tus pies." % c.full_name() if champion == null else "☠ %s muere a manos de tu campeón." % c.full_name())
	return " ".join(lines)

## Experiencia (XpRules): para quien luchó y sus compañeros; si fue un campeón, su señor recibe una parte.
func award_xp(winner: Character, event_fight: bool) -> String:
	if winner == null or not fighter.is_alive():
		return ""
	var won := winner == fighter
	var amount: int
	if CombatSetup.is_tournament():
		amount = XpRules.TOURNAMENT_ROUND if won else XpRules.DUEL_LOSS
		if won and CombatSetup.is_final_round():
			amount += XpRules.TOURNAMENT_CHAMPION
	elif won:
		amount = XpRules.DUEL_WIN + XpRules.DUEL_RANK_BONUS * maxi(0, enemy.rank() - fighter.rank())
		if event_fight:
			amount += XpRules.EVENT_FIGHT_WIN
	else:
		amount = XpRules.DUEL_LOSS
	var text := xp_line(fighter, amount)
	for c: Character in companions:
		if c != fighter and c.is_alive():
			text += " " + xp_line(c, amount)
	if champion != null and owner.is_alive():
		text += " " + xp_line(owner, roundi(amount * CHAMPION_OWNER_XP_SHARE))
	return text.strip_edges()

func xp_line(c: Character, amount: int) -> String:
	if amount <= 0:
		return ""
	var levels := c.gain_xp(amount, XpRules.SOURCE_DUEL)
	amount = c.last_xp_gained
	if amount <= 0:
		return ""
	var who := "" if c == owner else c.first_name + ": "
	if levels > 0:
		return "%sExperiencia +%d. ¡Sube a nivel %d!" % [who, amount, c.level]
	return "%sExperiencia +%d." % [who, amount]

## Si luchó un campeón, el jugador recibe parte de la gloria (o de la vergüenza).
func champion_outcome(winner: Character) -> String:
	if champion == null:
		return ""
	champion.after_fight_recovery()
	champion.remove_meta("champion")
	if winner == champion:
		owner.gain_honor(CHAMPION_WIN_HONOR)
		owner.add_fame(CHAMPION_WIN_FAME)
		return " Tu campeón %s vence en tu nombre (honor %+d, fama %+d)." % [champion.full_name(), CHAMPION_WIN_HONOR, CHAMPION_WIN_FAME]
	if winner != null:
		owner.gain_honor(CHAMPION_LOSS_HONOR)
		return " Tu campeón %s cae derrotado (honor %+d)." % [champion.full_name(), CHAMPION_LOSS_HONOR]
	return ""

## Final de una ronda de torneo. Devuelve {text, next_round}.
func tournament_round_ended(winner: Character, rivalry: String) -> Dictionary:
	var p := fighter
	var round_num := CombatSetup.tournament_round
	var total := CombatSetup.tournament_opponents.size()
	var won := winner == p
	var badly_hurt := p.current_health < p.max_health * Character.SEVERE_WOUND_RATIO
	if won:
		p.honor = clampi(p.honor + CombatSetup.TOURNAMENT_ROUND_HONOR, 0, 100)
	if won and not CombatSetup.is_final_round() and not badly_hurt:
		return {"text": "¡Pasas a la ronda %d!" % (round_num + 1), "next_round": true}
	var text: String
	if won and CombatSetup.is_final_round():
		p.gold += CombatSetup.TOURNAMENT_PRIZE_GOLD
		p.honor = clampi(p.honor + CombatSetup.TOURNAMENT_PRIZE_HONOR, 0, 100)
		text = "¡Campeón del torneo! Vences las %d rondas y ganas %d de oro y %d de honor." % [
			total, CombatSetup.TOURNAMENT_PRIZE_GOLD, CombatSetup.TOURNAMENT_PRIZE_HONOR]
		p.add_fame(TOURNAMENT_FAME)
		text += " Fama %+d." % TOURNAMENT_FAME
		if randf() < UniqueItems.TOURNAMENT_CHANCE:   # a veces el premio del campeón es una pieza única
			var prize := UniqueItems.grant(p)
			if not prize.is_empty():
				text += " " + prize
		var reactions := RelationsData.rival_reactions()
		if not reactions.is_empty():
			text += " " + reactions
	elif won:
		text = "Ganas la ronda %d, pero tus heridas te obligan a retirarte del torneo." % round_num
	else:
		text = "Quedas eliminado en la ronda %d del torneo." % round_num
	text += " Balance del torneo: honor %+d, oro %+d." % [
		p.honor - CombatSetup.tournament_honor_start, p.gold - CombatSetup.tournament_gold_start]
	var wound := p.after_fight_recovery()
	CombatSetup.last_result_text = " ".join([text, rivalry, demotion_text, wound]).strip_edges()
	return {"text": text, "next_round": false}

func campaign_summary(winner: Character) -> String:
	var outcome: String
	if winner == fighter:
		outcome = "Venciste a %s." % enemy.full_name() if champion == null else "Tu campeón venció a %s." % enemy.full_name()
	elif winner == null:
		outcome = "El combate contra %s terminó con una huida." % enemy.full_name()
	else:
		outcome = "%s te derrotó." % enemy.full_name()
	var text := "%s Honor %+d, oro %+d. Duelos: %d ganados / %d perdidos." % [
		outcome, owner.honor - honor_before, owner.gold - gold_before, owner.duels_won, owner.duels_lost]
	if not demotion_text.is_empty():
		text += " " + demotion_text
	return text
