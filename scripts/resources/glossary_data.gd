extends RefCounted
# Textos del glosario (escena res://scenes/glossary/glossary.tscn).
# Cada categoría tiene entradas fijas [título, texto]. Las categorías marcadas en DYNAMIC
# además se rellenan solas con el catálogo del juego (habilidades, rasgos, equipo,
# personalidades), así el contenido nuevo aparece sin tocar este archivo.
# Para abrir el glosario desde cualquier pantalla: GlossaryData.open(get_tree(), "res://ruta/de/vuelta.tscn")

const SCENE := "res://scenes/glossary/glossary.tscn"
const MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"

static var return_scene := ""     # escena a la que vuelve el botón «Volver»
static var start_category := ""   # categoría con la que se abre (opcional)

static func open(tree: SceneTree, from_scene: String, category: String = "") -> void:
	return_scene = from_scene
	start_category = category
	tree.change_scene_to_file(SCENE)

const CATEGORIES := [
	"Duelo", "Batalla", "Personaje y roles", "Atributos", "Personalidades", "Habilidades",
	"Rasgos y desventajas", "Equipamiento", "Economía y castillo", "Ejércitos y asedios",
	"Reinos y diplomacia", "Relaciones e intimidad", "Rivalidad", "Romance y matrimonio",
	"Séquito y compañeros", "Encargos", "Eventos y noticias", "Fama y honor",
	"Nivel y dinastía", "Obras y exploración", "Viaje", "Camino mercenario",
	"Prisioneros", "Intrigas e historias", "Hazañas y final", "Interfaz y atajos",
]

const DYNAMIC := ["Personalidades", "Habilidades", "Rasgos y desventajas", "Equipamiento"]

const ENTRIES := {
	"Duelo": [
		["Finta", "Amagas un golpe (10 de aliento). Si el rival espera para contraatacar, su parada se pierde y tu próximo ataque no se puede parar y hace +25%. Si no, es un golpe flojo (−50%)."],
		["Posturas que comprometen", "Cada postura cierra alguna acción: Ofensiva no deja Guardia; Defensiva y Esgrima no dejan Empujar; Desesperada solo deja Atacar, Empujar y Abandonar. En Esgrima desarmas un 10% mejor."],
		["Leer al rival", "Al empezar tu turno, tu Estrategia frente a la suya te da una probabilidad (15% a la par, +4% por punto de ventaja, hasta 60%) de adivinar su próxima jugada: 👁 «Parece que va a desarmarte». Si la adivinas, la mantendrá. Lectura del Rival y Mente Analítica ayudan; Rostro de Piedra te hace ilegible; Previsible te delata."],
		["Experiencia en duelos", "Todo duelo enseña: de campaña, de torneo, de evento, a muerte o el duelo singular en mitad de una batalla (30 si vences, 10 si pierdes)."],
		["Combos del duelo", "Encadenar bien da ventaja. Si paras un golpe, tu siguiente ataque es una contra devastadora: +50% de daño y no se puede parar. Si esquivas, quedas al acecho: +25% de crítico. Si empujas con éxito, el rival queda desequilibrado: tu próximo desarme tiene +25% y su próximo golpe hace −20%. Atacar tres veces seguidas es previsible (−15%), salvo en Ofensiva o Desesperada."],
		["Duelo a muerte", "Se avisa antes de empezar y se marca «☠ A MUERTE». Quien cae con la vida a 0 muere. Si eres tú, tu heredero toma el relevo; si lucha un campeón, es su vida la que arriesga. Rendirse o retirarse salva la vida, a costa del honor."],
		["Cómo funciona un turno", "Cada turno eliges una postura (opcional, se mantiene) y una acción. Luego actúa tu rival. Quién empieza se decide al azar, con ventaja para quien tiene más Combate."],
		["Daño", "Un golpe hace 24 × A / (A + D), con ±20% de azar. A es tu Combate más la bonificación ofensiva de tu postura (×1,5) y D la Defensa del rival más su bonificación defensiva (×1,5). Con atributos iguales cada golpe quita unos 12 puntos de vida."],
		["Posturas", "Ofensiva: más daño, sin Guardia.
Defensiva: recibes menos daño y tu Guardia es más firme; sin Empujar.
Esgrima: tu Guardia esquiva más y desarmas mejor; sin Empujar.
Desesperada: gran daño, defensa por los suelos; solo Atacar y Empujar."],
		["Atacar", "Golpea al rival y gasta 15 de aliento. Puede ser esquivado, parado o amortiguado por la guardia del rival. Un 10% de los golpes son críticos (×1,75)."],
		["Guardia", "Reduce a la mitad el próximo golpe y a veces lo evita entero (5% en Defensiva, 40% en Esgrima, más si superas en Combate al rival). Recupera aliento. Si esquivas del todo, quedas al acecho. Empujar la rompe."],
		["Abandonar", "Rendirte (derrota segura, sin herida) o intentar retirarte (puede fallar y cuesta honor)."],
		["Contraatacar (parada)", "Esperas el golpe para pararlo: 55% (± diferencia de Combate) de no recibir nada y devolver un golpe ×1,25. Si falla, recibes el golpe normal. Es la respuesta a un rival que solo ataca."],
		["Empujar", "Rompe la guardia del rival (anula su Guardia o su parada) y le quita 20 de aliento y algo de moral. Gasta 12 de aliento. Es la respuesta a un rival que se esconde."],
		["Desarmar", "Gasta 15 de aliento. Si sale bien, el rival no puede atacar durante 2 turnos. La probabilidad depende de tu Combate frente a su Defensa."],
		["Aliento y fatiga", "Recuperas 5 de aliento al comienzo de cada turno. Por debajo del 20% estás Fatigado: tu daño baja un 30%, esquivas la mitad y no puedes desarmar ni empujar."],
		["Moral y estados", "Herido (menos del 30% de vida), Fatigado, Desmoralizado (moral baja: −20% daño), Inspirado (moral alta: +20% daño) y Desarmado. Cada golpe recibido baja la moral."],
		["Rendirse y huir", "Rendirse termina el duelo como derrota, pero evitas la herida de caer: pierdes 3 de honor extra y pagas 25 de oro de rescate. Huir puede fallar; si sale bien pierdes 3 de honor."],
		["Personalidad del rival", "Cada rival pelea según su carácter (un arrogante ataca sin pausa, un prudente se cubre y para, un astuto desarma y empuja...) y se adapta: si solo atacas, aprenderá a esperarte con una parada."],
		["Campeones", "Puedes nombrar a un miembro de tu séquito (o un compañero de tu facción) para que luche en tu lugar. Lo controlas tú; sus atributos y habilidades son los suyos."],
		["Heridas", "Quien termina un duelo con poca vida queda herido de gravedad y no podrá batirse durante unos meses. La vida se recupera poco a poco cada mes."],
	],
	"Batalla": [
		["Llamada a filas", "Si estás junto a un castillo a punto de ser asediado, o donde se prepara una batalla campal, tu señor, un señor que te aprecia o un amigo de su corte puede llamarte a filas. Mueves solo tu pelotón (azul); sus tropas (verde) las mueve su señor. Si vencéis, te paga y gana su afecto. Negarte a tu señor cuesta afinidad. Si su jefe es mediocre, sus pelotones cometen algún error (dudan, eligen mal el objetivo o tardan en usar sus habilidades); con Liderazgo y Estrategia altos (28 entre ambos) luchan tan bien como el enemigo."],
		["Campesinos y guerra", "Un campesino no va a la batalla por su cuenta, solo si alguien que lo conoce lo llama a filas. Lleva una pequeña milicia."],
		["Lazos de batalla", "Quienes luchan a tu lado (séquito, compañeros, jefes aliados) te aprecian más: +5 de intimidad si vencéis, +2 si no."],
		["Duelo singular", "En campo abierto, un jefe con 40 de honor puede retar al jefe de un pelotón enemigo a tiro, y gasta su turno. Quien pierde se retira del campo con su pelotón. Rehusar cuesta moral a todo el bando (−8). Los duelos de tus pelotones los juegas tú; los demás se deciden solos."],
		["Traición", "Luchando por otro (llamado a filas o defendiendo el castillo de tu señor), puedes pasarte al enemigo con tus pelotones y tu séquito. Pierdes 25 de honor y 5 de fama, y quienes lo vieron desde tu bando te odiarán. Tras la batalla juras lealtad al señor del otro bando."],
		["Órdenes de batalla", "Mantener posición [H]: el pelotón no se mueve y recibe un 23% menos de bajas. Cargar [C]: su primer golpe cuerpo a cuerpo hace +30%, pero se cansa más (no vale para arqueros). Replegarse [R]: retrocede hasta 2 casillas, recupera 10 de moral y gasta su turno."],
		["Clima y hora", "Cada batalla tiene su clima y su hora, según el reino y la estación. Lluvia: los arqueros causan un 30% menos de bajas. Nieve: la caballería avanza una casilla menos. Niebla o noche: los arqueros disparan una casilla menos y solo ves a los enemigos cercanos (3 casillas con niebla, 4 de noche)."],
		["Habilidades de mando", "Una vez por batalla, el comandante y cada compañero pueden dar una orden especial según sus habilidades de batalla: Grito de guerra, Lluvia de flechas, Carga de caballería, Muro de escudos, Reagrupar filas, Emboscada o Ataque coordinado (teclas 1–9). El enemigo también las usa."],
		["Campos de batalla", "El terreno depende de la región. Solo los asedios tienen muralla, y además un río con puente y vados (el asedio dura 2 turnos más), una aldea (defensa +30%), un bosque espeso o una loma. En el vado se defiende peor (−20%). Las escaramuzas son en campo abierto."],
		["Muerte en batalla", "Si mandas tú y todo tu bando cae o huye, puedes morir (1 de cada 4 veces). Retirarte a tiempo nunca te mata."],
		["El campo", "Un tablero de 12 × 8 casillas. El atacante despliega a la izquierda y el defensor a la derecha, normalmente tras su muralla."],
		["Familias de tropa", "Infantería, Arquería, Caballería y Piqueros, cada una con su versión avanzada: Infantería pesada (aguanta las flechas), Ballesteros (atraviesan armaduras, menos alcance), Caballería pesada (carga brutal, más lenta) y Lanceros (más defensa). En el tablero, ★ marca la tropa avanzada."],
		["Círculo de ventajas", "Caballería > arqueros > infantería > piqueros > caballería: quien ataca a su presa hace un 30% más, y a su depredador un 20% menos. Caballería contra infantería y arqueros contra piqueros luchan sin ventaja."],
		["Comandancia", "Tienes un nivel de mando (1–10) en cada familia. Sube al ganar batallas mandándola y con «Entrenar con la Tropa» y «Estudiar Táctica» en el castillo. Da más soldados y moral a tu pelotón, hace más probable que te la asignen y, desde el nivel 5, llevas su versión avanzada."],
		["El general", "Cada bando tiene un general: lo elige su señor por fama, mando y rango (si el ejército es tuyo, eres tú). Su escolta es la más fuerte y protegida, pero si su pelotón cae, su bando pierde. Solo él ordena la retirada. Su escolta lucha siempre cuerpo a cuerpo: un general de arqueros manda más arqueros, pero lo guarda infantería. Una escolta de caballería protege algo menos que una de a pie: su fuerza está en la movilidad."],
		["Cubrir la retirada", "Si tu general ordena retirarse, puedes irte con el ejército o quedarte con tus hombres 2 turnos cubriendo la huida: si sobrevives, +12 de honor y +8 de fama. Abandonar el campo sin orden del general es desertar (−10 de honor)."],
		["Negociar tu tropa", "Antes de la batalla puedes pedir al general otra familia de tropa, una vez. Cuentan tu mando en ella, tu Carisma, tu fama, tu Estrategia y tu relación con él; si se niega, la relación se resiente un poco."],
		["Consejo de guerra", "Desde Nobleza Baja asignas la tropa de los personajes de tu facción (séquito, caballeros y señores de tu reino), en el castillo o antes de la batalla si eres el general. A los demás se la asigna el general."],
		["Estrategia en batalla", "Lees al rival: ves más lejos con niebla o de noche, adivinas lo que harán los pelotones enemigos cercanos (flechas naranjas, desde Estrategia 8), tus habilidades de mando rinden más y el terreno te defiende mejor (+3% por punto sobre 10, hasta +12%; en el vado, la penalización se reduce)."],
		["Terreno", "Llano: sin efecto. Bosque: +25% de defensa. Colina: +20% de defensa y los arqueros alcanzan 1 casilla más. Muralla: +50% de defensa."],
		["Respuesta", "Si atacas cuerpo a cuerpo y el pelotón enemigo sigue en pie, responde con parte de su fuerza (40%). Los arqueros nunca responden."],
		["Moral y huida", "Cada baja baja la moral. Un pelotón con moral por debajo de 25 rompe filas y huye; ver huir a los compañeros desmoraliza al resto del bando."],
		["Fatiga", "Moverse y atacar cansa. Un pelotón que descansa un turno (sin moverse ni atacar) recupera fatiga y algo de moral."],
		["Turnos", "La batalla dura como mucho 12 turnos. En un asedio, si el castillo no ha caído, gana el defensor salvo que su guarnición esté diezmada (menos del 38% en pie): entonces se rinde. En campo abierto, al caer la noche se queda el campo quien ha sufrido menos bajas (la moral desempata)."],
		["Comandantes y compañeros", "El comandante de cada bando mejora a sus tropas según su Liderazgo y Estrategia, y sus habilidades de batalla. Los compañeros de tu séquito pueden encabezar pelotones."],
		["Bajas previstas", "Al pasar el ratón sobre un objetivo ves las bajas que causarías y las que recibirías en respuesta."],
	],
	"Personaje y roles": [
		["Roles", "Campesino → Soldado → Caballero → Nobleza Baja → Nobleza Alta → Duque → Regente, o el camino mercenario (Mercenario → Capitán de compañía → Condotiero). Cada rol tiene sus propias acciones en el castillo y más acciones por mes."],
		["Alistarse (Soldado)", "Campesino o no afiliado: 150 de oro para las armas, o Combate 12 (entonces no pagas)."],
		["No afiliado", "Sin tierra ni señor: va donde quiere, vive de jornales y puede ofrecerse en guerras ajenas. No trabaja la tierra. Puede asentarse en un castillo (pasa a campesino) o alistarse (soldado)."],
		["Abandonar tus tierras", "El campesino puede dejar su tierra y a su señor para quedar como no afiliado. El soldado que abandona a su señor también."],
		["Trabajo a jornal", "Cargador, jornalero, guardia de caravana o escolta: un día de trabajo por oro según tu Defensa, Carisma o Combate y el mercado del castillo. Hasta 2 al mes; la guardia y la escolta pueden acabar en pelea."],
		["Caballero", "Requiere 4 duelos ganados y 60 de honor."],
		["Nobleza Baja", "Requiere 75 de honor y 500 de oro."],
		["Nobleza Alta", "Requiere Liderazgo 12 y 2000 de oro. «Ejercer el Mando» y ganar batallas al mando suben el Liderazgo."],
		["Duque", "Entre la Nobleza Alta y el Regente. Necesitas gobernar 2 castillos de tu reino, 70 de honor y 14 de liderazgo. Tienes 4 acciones, 5 plazas de séquito, «Gobernar el Ducado» (recaudas en todos tus castillos) y puedes ordenar las grandes obras de nivel 3."],
		["Regente", "Desde Duque: requiere honor 80 y heredar la corona por matrimonio con la casa de tu soberano, o controlar 4 castillos de tu reino para usurparla."],
		["La corona vacante", "Si eres Duque y el rey muere sin hijos, puedes reclamar el trono: te haces Regente y los castillos de la Corona pasan a ti, pero el pariente que lo heredaba no lo olvidará. También puedes jurarle lealtad."],
		["Deshonra", "Un Caballero o superior con menos de 20 de honor desciende de rango."],
		["Acciones por mes", "Cada acción del castillo, de las relaciones o de la diplomacia gasta una acción. Al avanzar el turno se recuperan."],
	],
	"Atributos": [
		["Liderazgo", "Mejora la moral y la fuerza de tus tropas, y es necesario para la Nobleza Alta."],
		["Carisma", "Ayuda en el trato con la gente: regalos, conversaciones, eventos que se resuelven hablando."],
		["Estrategia", "Mejora a tus tropas en batalla y algunas tiradas de eventos."],
		["Combate", "Tu fuerza ofensiva en el duelo y tu probabilidad de esquivar, parar y desarmar."],
		["Defensa", "Reduce el daño que recibes en el duelo y dificulta que te desarmen."],
		["Vida, aliento y moral", "Vida: si llega a 0 caes. Aliento: lo gastan las acciones del duelo. Moral: afecta al daño en el duelo y a la huida de las tropas."],
	],
	"Personalidades": [
		["Qué es la personalidad", "Define cómo habla y se comporta cada personaje: sus frases, su forma de pelear en duelo, los regalos que agradece y los eventos que le ocurren."],
	],
	"Habilidades": [
		["Tipos de habilidad", "Generales (gobierno, viajes, economía), de Combate (duelo) y de Batalla (mando de tropas)."],
	],
	"Rasgos y desventajas": [
		["Rasgos", "Las ventajas y desventajas modifican atributos y a veces el comportamiento. Al crear un personaje eliges al menos 3 ventajas y 2 desventajas."],
	],
	"Equipamiento": [
		["Piezas únicas", "Piezas legendarias (★★★★) con una habilidad propia: Durandal, la Misericordia de Toledo, la Loriga de Covadonga, el Escudo de Teodorico, el Yelmo de Sutton Hoo, la Oriflama, el Olifante, Babieca, el Anillo de Teodolinda, la Capa del Peregrino, el Relicario de Aquisgrán y el Sello del Emperador. Son raras, pero puede haber varias en el mundo."],
		["Cómo conseguirlas", "Explorando (la Torre del Desafío siempre da una), a veces como premio de campeón de torneo, forjándola en una herrería de nivel 3 (a precio de rey) o como trofeo al vencer en duelo a quien la lleva: reclamarla cuesta 5 de honor y el vencido no lo olvidará."],
		["Equipo", "Cada personaje lleva hasta 2 piezas de equipo que modifican sus atributos."],
	],
	"Economía y castillo": [
		["Armería", "En tu castillo puedes comprar y vender equipo. El surtido cambia cada mes y mejora con tu rango (los Campesinos y Soldados solo encuentran piezas comunes). Tu Carisma rebaja o encarece el precio; al vender recuperas el 40%. Una pieza por ranura: la nueva sustituye a la anterior, que se entrega a cuenta."],
		["Oro propio y oro del castillo", "Tu oro es tuyo; el tesoro del castillo paga la tropa y lo usan las acciones de gobierno."],
		["Recaudar y gobernar", "Lo recaudado se reparte: 60% para ti y 40% para el castillo."],
		["Mantenimiento", "Cada mes el castillo recauda impuestos, paga a la guarnición y consume comida. Sin comida o sin paga, la guarnición pierde soldados."],
		["Mejorar las tierras", "Inviertes 100 de oro y ganas una renta permanente de 10 de oro al mes (hasta 50)."],
		["Mercenarios", "Desde Caballero: 4 de oro por soldado, hasta 40 por contrato. Se unen a tu ejército del castillo."],
		["Entrenar y ejercer el mando", "Entrenar cuesta 15 de oro, una vez al mes, y cuesta más mejorar cuanto más Combate tienes. Ejercer el Mando (40 de oro) puede subir el Liderazgo."],
		["Edictos", "El Regente puede dictar un edicto que afecta a todo su reino cada mes."],
	],
	"Ejércitos y asedios": [
		["Movilizar", "Convierte el 40% de la guarnición (60% siendo Regente) en un ejército que marcha por el mapa. Se suma al ejército que ya tengas en ese castillo."],
		["Reunir ejércitos", "Tus ejércitos en el mismo castillo pueden juntarse en uno, o volver a la guarnición."],
		["Marchar", "Un ejército se mueve a un castillo vecino por turno (en invierno tarda más, salvo con Paso Invernal)."],
		["Batalla pendiente", "Al llegar a un castillo enemigo queda una batalla pendiente: puedes librarla tú mismo o seguir asediando."],
		["Asedio", "Cada mes que tu ejército asedia, el castillo pierde un 8% de su guarnición (15% sin comida). Pagas 1 de oro al mes por cada 10 sitiadores; sin paga, desertan."],
		["Fuerza necesaria", "Para tomar un castillo amurallado suele hacer falta 1,5 veces su guarnición."],
	],
	"Reinos y diplomacia": [
		["Reinos", "Doce castillos repartidos entre reinos con su señor. La IA de cada reino recluta, ataca, declara guerras y firma paces."],
		["Alianzas", "Con 40 de afinidad y rango de Nobleza puedes pactar una alianza: sus ejércitos no atacan tus castillos."],
		["Guerra y paz", "La Nobleza Alta puede declarar la guerra. La paz cuesta un tributo y requiere que el enemigo no te odie demasiado."],
		["Traición", "Marchar contra un aliado rompe la alianza, cuesta mucho honor y los demás señores desconfían de ti."],
		["Amenazas", "Los reinos hostiles o en guerra contigo atacan tus castillos con más frecuencia; los vecinos no aliados hacen incursiones."],
	],
	"Relaciones e intimidad": [
		["Trato con señores", "Un campesino o un soldado no puede dirigirse a ningún señor, ni siquiera al suyo: solo responder cuando él lo llama (órdenes, encargos, invitaciones). El mercenario sí puede, porque vive de sus contratos."],
		["Afinidad", "Lo que un señor piensa de ti (−100 a 100). Sube con presentes (50 de oro) y favores; baja con agresiones. Con los señores se trata por diplomacia."],
		["Intimidad", "Lo cercano que es alguien contigo (0 a 100): Desconocido (0–19), Conocido (20–39), Amigo (40–59), Confidente (60–79) e Íntimo o Íntima (80+). Cambia cómo te habla y lo que está dispuesto a hacer por ti."],
		["Conversar", "Abre una charla con alguien de tu zona. Eliges la actitud: Amable, Halagador, Franco, Amenazante o, si cabe romance, Charla íntima. Cuesta 1 acción y solo una vez al mes por persona."],
		["Actitudes y carácter", "Cada personalidad reacciona distinto. Los arrogantes y ambiciosos adoran el halago; los leales, honorables y prudentes valoran la franqueza; los arrogantes la toman como ofensa. El Carisma mejora el halago y la charla íntima, y el honor hace creíble la franqueza."],
		["Amenazar", "Requiere 40 de honor o un rango superior. Siempre baja la intimidad. Al pueblo asustado le sacas 10–20 de oro a costa de 3 de honor; un cortesano amedrentado puede soltar un rumor."],
		["Rumores", "Un Confidente con quien hablas amable o francamente puede contarte cuántos hombres y cuánto oro tiene un castillo de otro reino."],
		["Regalo", "30 de oro: sube la intimidad 12 según su carácter; a algunos (piadosos, prudentes) los regalos caros les sientan mal."],
		["Enfriamiento", "Si pasan más de 2 meses sin trato, la amistad baja 1 al mes y el amor 3 (5 con los leales)."],
		["Tu zona y el pueblo", "La pestaña «Tu zona» reúne a la gente de tu reino: cortesanos, campesinos y soldados. Puedes tratar con todos, no solo con la corte."],
		["Perfiles", "Pulsa el retrato de cualquier personaje conocido para ver su ficha: carácter, atributos, habilidades, rasgos, equipo y vuestra relación. Puedes guardarlo en el editor de personajes."],
		["Retar a duelo", "Puedes retar a quien esté en tu zona. Los campesinos no se baten; quien te supera en 2 rangos o más solo acepta si tienes 20 de fama por rango de diferencia; quien te teme (4+ puntos de combate y defensa por debajo) puede negarse, salvo los arrogantes. Ganar da fama: 3, más 3 por cada rango que te supere el rival."],
	],
	"Rivalidad": [
		["Retos a muerte", "Cuando un némesis te reta, puedes aceptar un duelo a muerte: solo uno sale con vida."],
		["Rencor", "Cada duelo deja huella: vencer a alguien aumenta su rencor (más si es arrogante o ambicioso); perder lo calma."],
		["Etapas", "Conocido → Rival (40 de rencor) → Némesis (70). Los leales y piadosos vencidos dos veces pueden acabar respetándote."],
		["Iniciativas", "Los rivales te retan en público, difunden rumores, roban (los astutos) o reaccionan a tus victorias. Rechazar un reto cuesta honor."],
		["Revanchas", "Vencer de nuevo a un rival da honor extra: +3 (conocido), +6 (rival), +10 (némesis)."],
	],
	"Romance y matrimonio": [
		["Romance", "Solo entre un hombre y una mujer, y nace de la confianza: la «Charla íntima» solo se puede intentar con 40 de intimidad y sin estar casado con otra persona. Si sale bien, nace el romance; si no, la relación se enfría."],
		["Pretendientes rivales", "Otra persona puede cortejar a quien amas. Puedes retarla a duelo, superarla en regalos o dejarlo estar."],
		["Boda por amor", "Con un romance y 80 de intimidad puedes pedir la mano (50 de oro). Si te precipitas, puede decir que aún no."],
		["Matrimonio político", "Con un señor amistoso (60 de afinidad, Caballero o más) puedes casarte con alguien de su casa: su familia se vuelve aliada. Como Caballero, tu señor también puede ofrecértelo."],
		["Cónyuge", "Tu cónyuge tiene ficha y carácter propios y te propondrá asuntos cada cierto tiempo."],
		["Sucesión al trono", "Casarte con la casa de tu soberano te pone en la línea de sucesión al trono."],
	],
	"Séquito y compañeros": [
		["Quién te acompaña", "Antes de la batalla eliges qué miembros del séquito van contigo. Cada uno lleva un pelotón que mueves tú, aunque vayas como invitado o seas campesino."],
		["Hombres por pelotón", "Antes de la batalla repartes tus hombres entre tu pelotón y el de cada compañero: como mínimo 15, como máximo 10 + 2 × su Liderazgo. En una batalla ajena los hombres se contratan: 2 de oro cada uno (tus primeros 15 son tus allegados y no cobran); si vencéis, tu anfitrión paga a tu gente. Tu propio ejército, tu guarnición o tu compañía ya cobran: repartirlos es gratis."],
		["Íntimos", "Con 80 de intimidad alguien pasa a ser tu íntimo (o íntima). Un íntimo —y tu cónyuge— te sigue sea cual sea tu rol y sin pedir fama ni honor, en 2 plazas de séquito extra; si están llenas, ocupa una normal libre."],
		["Ocupaciones", "Con «Gestionar» das a tu cónyuge y a cada miembro del séquito una ocupación para el mes: Administrar (oro según Carisma y Estrategia), Entrenar (experiencia y a veces +1 Combate), Estudiar (experiencia y a veces +1 Estrategia) o Descansar (cura antes las heridas). No gasta tus acciones; quien está herido descansa por fuerza. Al subir de nivel reparten solos sus puntos."],
		["Equipar a los tuyos", "Desde «Gestionar» pasas piezas de equipo entre tú y tu compañero, ranura por ranura (máximo 3 piezas cada uno), incluidas las únicas."],
		["Duelo de práctica", "Una vez al mes con cada compañero (1 acción): sin heridas ni honor en juego. Los dos ganáis experiencia (15 quien vence, 8 quien pierde) y +3 de intimidad."],
		["Campeón designado", "Elige a un miembro de tu séquito como campeón: será el primero en ofrecerse cuando alguien pueda batirse por ti (retos, juicios, duelos de evento). Si lo eliges, lo controlas tú en el duelo."],
		["Séquito", "Personajes que te siguen por lealtad: Soldado 1 plaza, Caballero 2, Nobleza Baja 3, Nobleza Alta 4, Duque y Regente 5 (Mercenario 1, Capitán 3, Condotiero 4), más 2 plazas extra para íntimos. Piden 50 de intimidad y la fama y el honor que exige su rango (un caballero, 15 de fama y 40 de honor; un noble, 35 y 60). Cada uno cobra 5 de oro al mes: si no le pagas, se aleja y puede marcharse."],
		["En batalla", "Los miembros del séquito encabezan pelotones y los mejoran con sus atributos y habilidades. Si su pelotón huye, pueden salir heridos."],
		["Compañeros de facción", "Si no tienes séquito, tu señor te presta a los mejores combatientes de tu reino. Son menos leales (menos moral) y no te presta a nadie si tu afinidad con él es muy baja."],
		["Campeones", "En los duelos de campaña (no en torneos) puedes elegir a un miembro sano del séquito para que luche por ti y controlarlo tú. Si vence, ganas 3 de honor y 2 de fama; si cae, pierdes 2 de honor, y las heridas son suyas."],
	],
	"Encargos": [
		["Encargos", "Según tu rol recibirás tareas (de tu señor, del pueblo o de tu reino) con un plazo en meses. Cumplirlas a tiempo da recompensas; fallarlas tiene consecuencias."],
		["Duelos de exhibición", "Como Caballero pueden asignarte duelos de exhibición contra caballeros de otros reinos."],
	],
	"Eventos y noticias": [
		["Eventos con combate", "Algunas decisiones se resuelven peleando de verdad: un duelo contra un rival (un cabecilla, un caballero errante, un provocador, el campeón de un juicio) o una escaramuza en campo abierto con parte de tu guarnición y tu séquito. Las bajas salen de tu guarnición y el desenlace depende de si ganas o pierdes. Algunos encargos (como cazar bandidos) también se cumplen combatiendo."],
		["Crónica completa", "Menú ▸ Crónica (tecla C) guarda todas las noticias y tus decisiones desde el comienzo de la partida, mes a mes. Solo aparece lo que ocurre en castillos que puedes ver."],
		["Frecuencia", "Alrededor de la mitad de los meses traen una decisión: el suceso del mes, una iniciativa de un rival o un amor, un encargo o un suceso global."],
		["Eventos del mes", "Casi cada mes ocurre algo que requiere una decisión. Algunas opciones dependen del azar y de tus atributos (se muestra el % de éxito)."],
		["Eventos globales", "Pestes, buenas cosechas, rutas comerciales... afectan a todo el mundo; a veces puedes decidir cómo te afectan a ti."],
		["Noticias de otros reinos", "Bodas, muertes y declaraciones de guerra de otros señores aparecen en la crónica; las importantes se anuncian en pantalla."],
		["Eventos con protagonista", "Rivales, amores y tu cónyuge toman la iniciativa: verás su retrato y lo que dicen."],
	],
	"Fama y honor": [
		["Honor", "Tu reputación moral (0 a 100). Se gana con victorias justas y buenas decisiones; se pierde con huidas, traiciones y abusos. Es necesario para ascender."],
		["Fama", "Lo conocido que eres (0 a 100). Crece con duelos, torneos, batallas y encargos. Atrae más eventos y seguidores, y hace que te acepten más retos."],
		["Duelos y honor", "Vencer a alguien más fuerte da más honor que vencer a alguien débil."],
	],
	"Nivel y dinastía": [
		["Experiencia por tipo de luchador", "Cada tipo aprende distinto: el Duelista en duelos (×1,3), el Estratega estudiando (×1,35) y en batalla (×1,3), el Tanque entrenando (×1,25), el Defensor en batalla (×1,2), el Berserker en duelos (×1,25) y el Asesino en encargos y exploración (×1,2). Lo ves en la ventana de Nivel."],
		["Entrenar", "En tu castillo, 1 acción y 15 de oro: 30 de experiencia (según tu tipo de luchador), hasta 2 veces al mes. La primera sesión del mes puede subirte el Combate."],
		["Experiencia y nivel", "Duelos, batallas, torneos, encargos y exploraciones dan experiencia. Cada nivel (máximo 20) da 2 puntos de atributo que repartes en la ventana de Nivel; cada 3 niveles eliges una habilidad nueva entre tres."],
		["Edad y vejez", "Cada enero todos cumplen un año. Desde los 55, cada año hay una probabilidad de morir de viejo: 4% a los 55 y 3% más por cada año extra."],
		["Sin envejecimiento", "Al empezar la partida puedes desactivar «Los personajes envejecen»: los adultos no cumplen años ni mueren de viejos, pero los hijos sí crecen hasta la mayoría de edad."],
		["Hijos", "Casado o casada, y con la madre menor de 45, cada enero puede nacer un hijo (hasta 6). Hereda rasgos y atributos de sus padres y es adulto a los 16."],
		["Sucesión", "Si mueres (de vejez, en un duelo a muerte o en batalla), eliges qué hijo adulto continúa la casa: hereda tu oro, tus castillos, tu séquito, tu rango y parte de tu honor y tu fama."],
		["Fin del linaje", "Si mueres sin hijos adultos, nadie hereda tu nombre y la partida termina. Cásate pronto si quieres una dinastía."],
	],
	"Obras y exploración": [
		["Obras del castillo", "Solo la nobleza (desde Nobleza Baja) ordena obras en sus castillos. Se construye una cosa a la vez, tarda varios meses y se paga con el tesoro del castillo. Ordenarla gasta una acción."],
		["Edificios", "Herrería (mejor equipo y más barato), Establos (caballería más fuerte), Murallas (defensa en asedios), Mercado (más oro al mes), Capilla (curación y honor) y Cuartel (más reclutas y reclutar más barato). Cada uno tiene 3 niveles."],
		["Edificios de tu señor", "Los caballeros y soldados no construyen, pero disfrutan de los edificios del castillo donde sirven."],
		["Lugares para explorar", "Cada pocos meses aparece un lugar junto a un castillo (ruinas, cuevas, campamentos, minas…). Dura unos meses y luego desaparece. Explorarlo gasta una acción y da experiencia."],
		["Torre del Desafío", "Un guerrero sin nombre que solo se bate a muerte. Si lo vences, ganas gran fama y su armadura. Si pierdes, tu personaje muere."],
	],
	"Viaje": [
		["Culturas y nombres", "Cada reino tiene una cultura (franca, anglonormanda, castellanoleonesa, aragonesa y catalana, imperial, romana, prusiana, italiana o borgoñona) y su gente se llama según ella: casas nobles, apellidos de oficio, patronímicos («Díaz», «Fitzgerald») y sobrenombres («el Bravo»). Los reinos también reciben nombre propio en cada mundo."],
		["Cartas", "Con el señor de la tierra donde estás tratas en persona. A los demás solo puedes escribirles (✉): presentes con mensajero (10 de oro más), alianza, guerra, paz o pedir noticias, con 1 acción más. Pedir una mano, conversar, cortejar o retar exige estar allí; tu séquito viaja contigo y tu cónyuge vive en tu castillo."],
		["Viajar", "Tu ficha viaja de castillo en castillo por las rutas del mapa. Cada tramo cuesta 1 acción (2 en invierno, salvo con Paso Invernal). Elige un castillo y pulsa «Viajar»: si está lejos, avanzas un tramo hacia él."],
		["Encuentros en el camino", "En cada tramo puede salirte algo al paso: salteadores, mercaderes, peregrinos o un caballero errante; en tierra en guerra, patrullas y desertores; en invierno, lobos y ventiscas. Es más probable en invierno y en zonas de guerra. Algunos terminan en duelo o escaramuza."],
		["Tu zona", "Es la gente del lugar donde estás, no solo la de tu reino. Viaja para conocer, tratar o retar a la gente de otros reinos."],
		["Castillos ajenos", "De visita puedes ver a la gente del lugar, comprar en su armería, justar en su torneo (uno por castillo y año) y pedir audiencia a su señor. Las acciones de gobierno solo se hacen en tu castillo."],
		["Audiencia", "Gasta 1 acción, una vez al mes por señor. Puedes presentar tus respetos (sube la afinidad), pedir noticias de su reino, pedir un encargo o jurarle lealtad. No te recibe si estáis en guerra, si te odia, o si estás por debajo de Caballero sin 15 de fama."],
		["Jurar lealtad", "En persona, a un señor de otro reino que confíe en ti (10 de afinidad o 40 de fama). Su castillo pasa a ser tu hogar y su reino el tuyo, y tus castillos van contigo. Romper tu juramento cuesta 15 de honor (30 si te pasas al enemigo en guerra) y la enemistad de tu antiguo señor. No puedes volver a cambiar en 12 meses. Los campesinos simplemente se establecen allí, sin coste."],
		["Gobernar desde lejos", "Lejos de tu castillo solo puedes hacer gestiones por carta (✉): recaudar, gobernar, edictos, diplomacia, movilizar. Cada una cuesta una acción más. Entrenar, reclutar, justar o contratar exige estar allí."],
	],
	"Camino mercenario": [
		["Camino mercenario", "Mercenario → Capitán de compañía → Condotiero. Sin señor fijo: vendes tu espada a quien pague. Se elige al empezar, o se llega abandonando a tu señor (Soldado o Caballero) o al perder tu último castillo."],
		["Contratos", "Los señores te ofrecen contratos cada mes o cuando les ofreces tus servicios en su castillo (firmar gasta 1 acción). Cumplirlos da oro, fama y cuenta para ascender; tu rango sube la paga."],
		["Infamia y traición", "Romper un contrato da 10 de infamia; dejarlo vencer, 5. Firmar con el enemigo de quien te paga es traición: rompes su contrato, ganas 30 de infamia, pierdes honor y fama, y su reino no te contrata en un año. Con 40 de infamia nadie te contrata; se olvida 2 puntos al mes."],
		["Compañía", "Al ser Capitán levantas tu compañía (150 de oro, 30 soldados). Cada mes cobra su soldada: medio oro por soldado. Si no hay paga, deserta una cuarta parte. En la barra superior ves su tamaño, la soldada y tu infamia."],
		["Condotiero", "La cima del camino mercenario. Puede tomar castillos a su nombre y gobernarlos; si jura lealtad a un señor, se ennoblece como Nobleza Baja."],
	],
	"Prisioneros": [
		["Prisioneros", "Tras una batalla, los jefes vencidos pueden caer presos: más si su pelotón fue aniquilado o huyó, casi nunca si se retiraron a tiempo. También quien pierde un duelo hostil (eventos, rivales, enemigos en guerra)."],
		["Tus presos", "En Relaciones › Prisioneros: reclutarlo (si acepta), esclavizarlo, venderlo a los suyos, liberarlo (+honor) o ejecutarlo (−honor; su casa no lo olvida). Un señor no se recluta ni se esclaviza."],
		["Siervos", "Van con tu séquito sin ocupar plaza ni cobrar, te dan oro cada mes y se les puede ganar como a cualquiera. Se pueden vender o liberar. Si te detestan, pueden fugarse."],
		["Rescates", "Si capturan a alguien de tu séquito o a tu cónyuge, su captor te pide rescate. Si no pagas, puede soltarlo con el tiempo… o ejecutarlo."],
		["Cautiverio", "Si te capturan, tu captor decide según su carácter: rescate (con tu oro y el de tu castillo), mazmorra unos meses con intentos de fuga, libertad bajo palabra o ejecución. Preso no tienes acciones. Si te ejecutan, hereda tu hijo; sin heredero, termina la partida."],
	],
	"Intrigas e historias": [
		["Ambiciones", "Los señores y la gente de la corte persiguen sus propias metas: poder y rango, amor y familia, venganza y rivalidad, o riqueza y fe. Cada carácter tira hacia lo suyo: los ambiciosos conspiran, los piadosos fundan capillas, los crueles se vengan."],
		["Complots y ofertas", "A veces te buscan como aliado o como víctima: una conjura, una boda entre casas, un negocio, un torneo o un chantaje. Puedes unirte, delatarlos, aprovecharte o mantenerte al margen. Como mucho llega uno al mes."],
		["Conjuras", "Si te unes y triunfa, te recompensan; si fracasa, tu nombre sale a relucir. Delatarla da honor y un enemigo jurado; su cabecilla puede acabar en el cadalso."],
		["Chantaje", "Si tu honor cae de golpe, alguien puede saber lo que hiciste. Pagar entierra el secreto; negarte lo hace público."],
		["Intrigas ajenas", "Bodas, ascensos, duelos, conjuras y algún crimen ocurren entre otros personajes: los verás en la Crónica."],
		["Historias", "De vez en cuando (unas tres por década) empieza una historia en varios pasos, separados por meses: herejías, pretendientes al trono, la peste, una boda envenenada… Lo que decides se recuerda y abre o cierra caminos."],
		["Finales que cambian el mundo", "Cada historia termina de una forma según tus decisiones y combates: puedes ganar un castillo o una pieza única, salvar o perder a un señor, o dejar una comarca diezmada. Queda escrito en la crónica."],
		["Viajes de historia", "Algunos pasos te piden ir a otro castillo. Verás «📜 Viaja a…» en «Tu destino»; si no llegas a tiempo, la historia termina sin ti. La historia en curso aparece en Encargos."],
	],
	"Hazañas y final": [
		["Libro de hazañas", "Unas 27 hazañas por partida (Destino, Armas, Gobierno, Linaje, Fama, Riqueza y Viaje). Cada una da su recompensa: oro, fama, honor, experiencia, puntos de atributo o, rara vez, una pieza única. No terminan la partida. Ábrelo con L."],
		["Destino", "La hazaña propia de tu rol inicial (Campeón, Conquistador, La Corona…). Se muestra siempre la primera en «Tu destino»."],
		["Fin de la partida", "Solo termina si tu reino domina todos los castillos del mundo (lo gobiernes tú o tu señor), si unes por matrimonio los dos últimos reinos en pie, o si mueres —en combate, de viejo o ejecutado— sin un heredero adulto. Perder tu último castillo no la termina: huyes y sigues como mercenario."],
		["Deshonra", "Si tu honor llega a 0 pierdes un rango y 10 de fama, y tu honor vuelve a 15. Si servías sin tierras, tu señor te expulsa y quedas como mercenario."],
		["Ejecución", "Si te capturan y te ejecutan, tu heredero toma el relevo; sin heredero, tu linaje se extingue."],
		["Seguir jugando", "Tras una victoria (conquista del mundo o unificación por matrimonio) puedes seguir jugando la misma partida."],
	],
	"Interfaz y atajos": [
		["Duelo", "Teclas 1–7: acciones. Q, W, E, R: posturas. Pasa el ratón sobre una orden para ver su efecto y sus probabilidades. Con mando: cruceta y A."],
		["Mapa", "Rueda del ratón (hacia el cursor), +/− o L1/R1: zoom; alejándote ves el mapa entero. Botón derecho, WASD o stick izquierdo: mover la cámara, hasta los bordes del mapa. H: ocultar o mostrar los paneles inferiores. Pasa el ratón por un castillo para ver su reino, señor y guarnición. Si te quedan acciones, «Avanzar Turno» pide confirmación. Tab o clic del stick derecho: recorrer castillos. T o Y: avanzar turno. R o X: relaciones. E: encargos. C: crónica. Esc, M o Start: menú."],
		["Batalla", "Con el tablero enfocado, flechas o cruceta mueven un cursor (con la previsión de bajas) e Intro o A actúa en la casilla. T o Y: terminar turno."],
		["Teclado y mando", "Todas las pantallas abren con un botón enfocado: flechas o cruceta para moverse, Intro o A para aceptar, Esc o B para volver."],
		["Caras y retratos", "En listas, mapa y batallas se ve la cara de cada personaje; al pulsarla aparece su retrato completo (o su ficha, en Relaciones)."],
		["Opciones", "Volumen por separado de música, ambiente y efectos, y pantalla completa. Sacudida de pantalla: Normal, Suave o Sin sacudida. Efectos reducidos: quita las pausas de impacto, la cámara lenta, los destellos fuertes y las partículas."],
		["Guardado", "La partida se guarda sola cada mes (autoguardado) y puedes usar tres ranuras manuales. Las partidas y los personajes se guardan como datos (JSON): un archivo modificado o compartido no puede ejecutar nada. Si un guardado se daña, se recupera la copia anterior."],
	],
}

## Entradas de una categoría: las fijas más las que salen del catálogo del juego.
static func entries(category: String) -> Array:
	var result: Array = ENTRIES.get(category, []).duplicate()
	if category in DYNAMIC:
		result.append_array(_dynamic(category))
	return result

static func _dynamic(category: String) -> Array:
	var out: Array = []
	var tree := Engine.get_main_loop() as SceneTree
	var data: Node = tree.root.get_node_or_null("GameData") if tree != null else null
	match category:
		"Personalidades":
			var dc = load("res://scripts/resources/dialogue_catalog.gd")
			for key in Character.Personality.keys():
				var value: int = Character.Personality[key]
				var title: String = dc.personality_name(value) if dc != null else key.capitalize()
				var text := "Personalidad %s." % title.to_lower()
				if dc != null and dc.has_method("personality_description"):
					text = dc.personality_description(value)
				out.append([title, text])
		"Habilidades":
			if data != null:
				for pair in [["general_skills", "General"], ["combat_skills", "Combate"], ["battle_skills", "Batalla"]]:
					for s in data.get(pair[0]):
						out.append(["%s (%s)" % [s.skill_name, pair[1]], s.description])
		"Rasgos y desventajas":
			if data != null:
				for t in data.advantages:
					out.append(["%s (ventaja)" % t.trait_name, _with_mods(t.description, t)])
				for t in data.disadvantages:
					out.append(["%s (desventaja)" % t.trait_name, _with_mods(t.description, t)])
		"Equipamiento":
			if data != null:
				for e in data.equipment_catalog:
					out.append([e.equipment_name, _with_mods(e.description, e)])
	return out

static func _with_mods(text: String, item: Object) -> String:
	var parts: Array[String] = []
	for pair in [["combat_mod", "Combate"], ["defense_mod", "Defensa"], ["leadership_mod", "Liderazgo"],
			["charisma_mod", "Carisma"], ["strategy_mod", "Estrategia"]]:
		var v = item.get(pair[0])
		if v != null and int(v) != 0:
			parts.append("%s %+d" % [pair[1], int(v)])
	return text if parts.is_empty() else "%s (%s)" % [text, ", ".join(parts)]
