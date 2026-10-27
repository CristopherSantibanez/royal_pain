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

## Color heráldico de cada reino (se usa en el mapa, la diplomacia y las fichas).
static func kingdom_color(k: int) -> Color:
	match k:
		Kingdom.HIELO: return Color("b8d4e6")
		Kingdom.BOSQUE: return Color("4f8a3c")
		Kingdom.DORADO: return Color("d9b44a")
		Kingdom.CUMBRES: return Color("8a6fb0")
		Kingdom.AZUL: return Color("3d6fb5")
		Kingdom.CARMESI: return Color("b5332b")
		Kingdom.NEUTRAL: return Color("9a9a8c")
		Kingdom.ESMERALDA: return Color("2fa37a")
		Kingdom.DESIERTO: return Color("d6a86a")
		Kingdom.AMBAR: return Color("d9822b")
		Kingdom.GRIS: return Color("7b7f86")
		Kingdom.OLIVA: return Color("8a8f3c")
	return Color.GRAY

# Nombres del mundo actual (los pone MapData a partir de sus castillos). Vacío = nombres fijos de serie,
# los de las partidas guardadas antes de que los reinos tuvieran nombre propio.
static var custom_names := {}

static func kingdom_name(k: int) -> String:
	if custom_names.has(k):
		return custom_names[k]
	return default_kingdom_name(k)

static func default_kingdom_name(k: int) -> String:
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
