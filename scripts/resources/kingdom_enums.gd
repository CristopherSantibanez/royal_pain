class_name KingdomEnums

enum Kingdom {
	HIELO,
	BOSQUE,
	DORADO,
	CUMBRES,
	AZUL,
	CARMESI,
	NEUTRAL,
	ESMERALDA,
	DESIERTO,
	AMBAR,
	GRIS,
	OLIVA
}

static func kingdom_name(k: int) -> String:
	match k:
		Kingdom.HIELO: return "Reino de Hielo"
		Kingdom.BOSQUE: return "Reino del Bosque"
		Kingdom.DORADO: return "Reino Dorado"
		Kingdom.CUMBRES: return "Reino de las Cumbres"
		Kingdom.AZUL: return "Reino Azul"
		Kingdom.CARMESI: return "Reino Carmesí"
		Kingdom.NEUTRAL: return "Isla Neutral"
		Kingdom.ESMERALDA: return "Reino Esmeralda"
		Kingdom.DESIERTO: return "Reino del Desierto"
		Kingdom.AMBAR: return "Reino Ámbar"
		Kingdom.GRIS: return "Reino Gris"
		Kingdom.OLIVA: return "Reino Oliva"
	return "?"
