extends RefCounted
# Ambiciones de los PNJ (ver AmbitionData). Datos puros: tipos, impulsos por personalidad, curvas de
# utilidad y frases. Uso: const AmbitionCatalog = preload("res://scripts/resources/ambition_catalog.gd")
#
# IA de utilidad: cada PNJ puntúa todas las ambiciones posibles con curvas sobre su estado (rango, oro,
# rencor, familia, fe) multiplicadas por el impulso de su personalidad, y persigue la de mayor nota.

const P := Character.Personality

const KIND_POWER := "poder"
const KIND_LOVE := "amor"
const KIND_REVENGE := "venganza"
const KIND_WEALTH := "riqueza"
const KIND_NAMES := {KIND_POWER: "Poder y rango", KIND_LOVE: "Amor y familia",
	KIND_REVENGE: "Venganza y rivalidad", KIND_WEALTH: "Riqueza y fe"}

# id -> {kind, title (corto, para la ficha), months: [mín, máx] hasta madurar}
const AMBITIONS := {
	"ascender": {"kind": KIND_POWER, "title": "Ascender", "months": [8, 16]},
	"usurpar": {"kind": KIND_POWER, "title": "Conspirar", "months": [10, 20]},
	"casarse": {"kind": KIND_LOVE, "title": "Casarse", "months": [6, 14]},
	"casar_hijos": {"kind": KIND_LOVE, "title": "Casar a sus hijos", "months": [8, 16]},
	"vengarse": {"kind": KIND_REVENGE, "title": "Vengarse de ti", "months": [4, 9]},
	"rivalidad": {"kind": KIND_REVENGE, "title": "Hundir a un rival", "months": [6, 14]},
	"enriquecerse": {"kind": KIND_WEALTH, "title": "Enriquecerse", "months": [6, 12]},
	"fe": {"kind": KIND_WEALTH, "title": "Obras de fe", "months": [8, 16]},
	"torneo": {"kind": KIND_WEALTH, "title": "Patrocinar un torneo", "months": [6, 12]},
	"chantaje": {"kind": KIND_WEALTH, "title": "Chantajearte", "months": [3, 6]},
}

# Impulso de cada personalidad por tipo de ambición (1.0 = normal).
const DRIVE := {
	P.AMBICIOSO: {KIND_POWER: 1.6, KIND_LOVE: 0.7, KIND_REVENGE: 0.9, KIND_WEALTH: 1.0},
	P.LEAL: {KIND_POWER: 0.4, KIND_LOVE: 1.3, KIND_REVENGE: 0.7, KIND_WEALTH: 0.8},
	P.PRUDENTE: {KIND_POWER: 0.7, KIND_LOVE: 1.0, KIND_REVENGE: 0.5, KIND_WEALTH: 1.4},
	P.ARROGANTE: {KIND_POWER: 1.3, KIND_LOVE: 0.6, KIND_REVENGE: 1.4, KIND_WEALTH: 0.9},
	P.PIADOSO: {KIND_POWER: 0.4, KIND_LOVE: 1.0, KIND_REVENGE: 0.4, KIND_WEALTH: 1.3},
	P.ASTUTO: {KIND_POWER: 1.3, KIND_LOVE: 0.6, KIND_REVENGE: 1.0, KIND_WEALTH: 1.4},
	P.VALIENTE: {KIND_POWER: 1.0, KIND_LOVE: 0.9, KIND_REVENGE: 1.1, KIND_WEALTH: 0.9},
	P.CRUEL: {KIND_POWER: 1.3, KIND_LOVE: 0.4, KIND_REVENGE: 1.7, KIND_WEALTH: 0.9},
	P.GENEROSO: {KIND_POWER: 0.6, KIND_LOVE: 1.3, KIND_REVENGE: 0.4, KIND_WEALTH: 1.1},
	P.COBARDE: {KIND_POWER: 0.6, KIND_LOVE: 1.0, KIND_REVENGE: 0.7, KIND_WEALTH: 1.3},
	P.ROMANTICO: {KIND_POWER: 0.6, KIND_LOVE: 1.7, KIND_REVENGE: 0.8, KIND_WEALTH: 0.7},
	P.HONORABLE: {KIND_POWER: 0.7, KIND_LOVE: 1.2, KIND_REVENGE: 0.6, KIND_WEALTH: 1.0},
}
# Fe (dentro de «Riqueza y fe»): quién funda capillas o peregrina.
const FAITH := {P.PIADOSO: 1.6, P.HONORABLE: 1.0, P.GENEROSO: 1.0, P.LEAL: 0.8}
# Quién patrocina torneos.
const PAGEANTRY := {P.VALIENTE: 1.3, P.ARROGANTE: 1.2, P.ROMANTICO: 1.2, P.GENEROSO: 1.1, P.AMBICIOSO: 1.0}
# Quién conspira contra su soberano.
const SCHEMERS := {P.AMBICIOSO: 1.0, P.CRUEL: 1.0, P.ASTUTO: 1.0, P.ARROGANTE: 0.7}
# Quién vive del chantaje.
const BLACKMAILERS := {P.ASTUTO: 1.5, P.CRUEL: 1.1, P.AMBICIOSO: 0.6}

static func drive(personality: int, kind: String) -> float:
	return DRIVE.get(personality, {}).get(kind, 1.0)

static func kind_of(id: String) -> String:
	return AMBITIONS.get(id, {}).get("kind", "")

static func title_of(id: String) -> String:
	return AMBITIONS.get(id, {}).get("title", id)

static func months_range(id: String) -> Array:
	return AMBITIONS.get(id, {}).get("months", [6, 12])

# --- Curvas de respuesta (0..1) ---

## Rampa lineal: 0 por debajo de lo, 1 por encima de hi.
static func ramp(x: float, lo: float, hi: float) -> float:
	if hi <= lo:
		return 1.0 if x >= hi else 0.0
	return clampf((x - lo) / (hi - lo), 0.0, 1.0)

## Curva logística centrada en mid (pendiente k): sube rápido alrededor de mid.
static func logistic(x: float, mid: float, k: float) -> float:
	return 1.0 / (1.0 + exp(-k * (x - mid)))

# --- Frases (formato de DialogueCatalog: {a:m|f} se refiere a quien escucha, {s:m|f} a quien habla) ---

const ANY := -1
const LINES := {
	"plot_usurp": {
		ANY: ["{victim} ya no merece el trono que ocupa. Únete a mí y no lo lamentarás.", "Somos pocos, pero bien escogidos. Te quiero de nuestro lado, {rank}."],
		P.CRUEL: ["Cuando caiga {victim}, recordaré quién estuvo conmigo… y quién no.", "Elige bando, {player}. Los indecisos acaban colgados."],
		P.ASTUTO: ["Nadie tiene que saber nada. Solo necesito tus ojos y, quizá, tu espada.", "Todo está calculado. Solo me falta alguien de tu talla."],
	},
	"plot_against_you": {
		ANY: ["Os sirvo, {rank}, por eso os aviso: {plotter} trama quedarse con lo vuestro.", "Hay una conjura en vuestra casa. La encabeza {plotter}."],
	},
	"plot_marry_children": {
		ANY: ["Nuestras casas ganarían mucho uniéndose. ¿Qué me dices, {player}?", "Un buen enlace vale más que mil lanzas."],
		P.ROMANTICO: ["He visto cómo se miran nuestros jóvenes. ¿Por qué no bendecirlo?"],
		P.AMBICIOSO: ["Una alianza de sangre nos haría temibles. Piénsalo bien."],
	},
	"plot_marry_self": {
		ANY: ["No sé fingir más: quiero compartir mi vida contigo, {player}.", "Llevo tiempo pensándolo. ¿Me dejarías estar a tu lado?"],
		P.ROMANTICO: ["Cada día sin ti es un día perdido. Dime que sí.", "Te escribiría mil cartas, pero prefiero decírtelo a la cara: te quiero."],
		P.PRUDENTE: ["Lo he pensado mucho, y no encuentro a nadie mejor que tú."],
	},
	"plot_rise": {
		ANY: ["Una palabra tuya ante tu señor me abriría muchas puertas, {player}.", "Sé que confías en mí. Ayúdame a subir y no te fallaré."],
		P.AMBICIOSO: ["Voy a llegar lejos, contigo o sin ti. Mejor contigo."],
	},
	"plot_rival": {
		ANY: ["{rival} me ha ofendido y pagará. ¿Estás conmigo?", "Necesito un aliado contra {rival}. Pensé en ti primero."],
		P.CRUEL: ["Voy a destrozar a {rival}. Puedes mirar… o ayudar."],
	},
	"plot_revenge": {
		ANY: ["No he olvidado lo que me hiciste, {player}.", "Esto no ha terminado, {player}. Ni de lejos."],
		P.CRUEL: ["Voy a quitarte todo lo que quieres, poco a poco.", "Disfruta mientras puedas, {player}."],
		P.ASTUTO: ["La venganza se sirve fría. La tuya ya está en la mesa."],
		P.COBARDE: ["No me mires así… yo no he sido. O quizá sí."],
	},
	"plot_invest": {
		ANY: ["Tengo un negocio entre manos: lana, sal y buenas rutas. Falta un socio.", "Pon algo de oro y en unos meses tendrás el doble. O casi."],
		P.PRUDENTE: ["Es un negocio seguro, dentro de lo que cabe. Lo he calculado todo."],
	},
	"plot_faith": {
		ANY: ["Quiero levantar una capilla. Tu ayuda sería bendecida.", "Parto en peregrinación. ¿Me acompañas, {player}?"],
		P.PIADOSO: ["Dios nos ha dado mucho. Devolvámosle algo, {player}."],
	},
	"plot_tourney": {
		ANY: ["Celebro un torneo. Quiero a {a:los mejores|las mejores} en la liza, y tú eres uno de ellos.", "Habrá justas, banquete y música. No faltes, {player}."],
		P.ARROGANTE: ["Ven a mi torneo, si te atreves a perder en público."],
	},
	"plot_blackmail": {
		ANY: ["Sé lo que hiciste, {player}. Mi silencio tiene un precio.", "Hay cosas que la corte no debería saber… ¿verdad?"],
		P.CRUEL: ["Paga, o todo el reino sabrá quién eres de verdad."],
		P.ASTUTO: ["No soy {s:un hombre|una mujer} codicioso. Solo prudente. Y tú vas a ser generoso."],
	},
	"plot_denounced": {
		ANY: ["Me has vendido, {player}. Te arrepentirás.", "Traidor{a:|a}. No lo olvidaré."],
	},
}

## Frase para un tema y una personalidad, con marcadores de género y valores ({player}, {victim}…).
static func line(topic: String, speaker: Character, listener: Character, ctx: Dictionary = {}) -> String:
	var table: Dictionary = LINES.get(topic, {})
	if table.is_empty():
		return ""
	var pool: Array = table.get(speaker.personality if speaker != null else ANY, table.get(ANY, []))
	if pool.is_empty():
		pool = table.get(ANY, [])
	if pool.is_empty():
		return ""
	var values := ctx.duplicate()
	if not values.has("rank"):
		values["rank"] = DialogueCatalog.rank_address(listener)
	return DialogueCatalog._apply_gender(str(pool.pick_random()), speaker, listener).format(values)
