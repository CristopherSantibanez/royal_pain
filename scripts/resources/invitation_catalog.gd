extends RefCounted
# Llamadas a filas: un señor (o alguien de su corte que te conoce) te pide que te unas a su ejército.
# Son eventos pendientes normales (GameManager.pending_event): la opción de aceptar lleva un combate
# "invited" que prepara CombatSetup.begin_invited_battle; la de declinar, "invite_decline".
# Uso: const InvitationCatalog = preload("res://scripts/resources/invitation_catalog.gd")

const DECLINE_LIEGE_AFFINITY := -8      # no acudir a la llamada de tu propio señor
const DECLINE_OTHER_AFFINITY := -2

## Evento de llamada a filas para el asedio de "castle" por el ejército "army".
## side: bando al que te unirías (BattleEnums.Side). lord: quien manda ese bando; inviter: quien te llama.
static func army_event(army: Army, castle: Castle, side: int, lord: String, inviter: String, is_liege: bool) -> Dictionary:
	var attacking := side == BattleEnums.Side.ATACANTE
	var enemy := castle.owner_name if attacking else army.owner_name
	var deed := "tomar %s, en manos de %s" % [castle.castle_name, enemy] if attacking \
		else "defender %s del asedio de %s" % [castle.castle_name, enemy]
	var text := _who(inviter, lord) + " Va a %s y necesita cada espada. Pelearías con tu gente bajo su estandarte: tú mueves tu pelotón y sus tropas, las suyas." % deed
	if is_liege:
		text += " Es tu señor: negarte no le hará gracia."
	return _event("Llamada a filas", text, inviter, lord,
		{"type": "invited", "kind": "army", "army_id": army.army_id, "side": side, "lord": lord, "inviter": inviter,
			"castle_id": castle.castle_id},
		"Te unes a las tropas de %s ante %s." % [lord, castle.castle_name],
		{"invite_decline": army.army_id}, is_liege)

## Batalla campal entre dos castillos de reinos en guerra (en campo abierto: hay duelos de jefes).
static func field_event(ally_castle: Castle, enemy_castle: Castle, lord: String, inviter: String, is_liege: bool) -> Dictionary:
	var text := _who(inviter, lord) + " Sus hombres saldrán de %s al encuentro de las tropas de %s (%s) en campo abierto. En campo abierto los jefes pueden retarse a duelo singular." % [
		ally_castle.castle_name, enemy_castle.owner_name, KingdomEnums.kingdom_name(enemy_castle.kingdom)]
	if is_liege:
		text += " Es tu señor: negarte no le hará gracia."
	return _event("Batalla campal", text, inviter, lord,
		{"type": "invited", "kind": "field", "side": BattleEnums.Side.ATACANTE, "lord": lord, "inviter": inviter,
			"ally_castle_id": ally_castle.castle_id, "enemy_castle_id": enemy_castle.castle_id},
		"Te unes a las tropas de %s camino de la batalla." % lord, {}, is_liege)

static func _who(inviter: String, lord: String) -> String:
	if inviter == lord:
		return "%s te manda llamar." % lord
	return "%s, que sirve a %s, te busca de su parte." % [inviter, lord]

static func _event(title: String, text: String, inviter: String, lord: String, fight: Dictionary, accept_text: String,
		decline_extra: Dictionary, is_liege: bool) -> Dictionary:
	var decline := {"label": "Declinar la llamada",
		"result": "Te excusas como puedes. %s tendrá que arreglárselas sin ti." % lord,
		"effects": {"affinity": DECLINE_LIEGE_AFFINITY if is_liege else DECLINE_OTHER_AFFINITY}}
	decline.merge(decline_extra)
	return {"id": "llamada_a_filas", "title": title, "text": text, "speaker": inviter, "target": lord,
		"quote": "Hace falta gente de valor. ¿Vienes con nosotros?",
		"options": [
			{"label": "Unirte a su ejército", "result": accept_text, "fight": fight},
			decline,
		]}
