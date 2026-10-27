class_name DialogueCatalog
extends RefCounted
# Frases de los personajes según su personalidad. Lógica pura (sin autoloads).
#
# Uso: DialogueCatalog.line("duel_open", rival, jugador, {"player": jugador.full_name()})
# Cada tema tiene frases por personalidad; si una personalidad no tiene frases para un tema,
# se usa "any". Marcadores: {player} {rival} {name} {count} {rank}.
#   {rank}: tratamiento de quien escucha según su rango ("mi señor", "dama"...); si no se pasa en
#   ctx, se calcula solo con rank_address(listener).
# Género: {a:masculino|femenino} concuerda con quien escucha (listener) y
# {s:masculino|femenino} con quien habla. Ej.: "Vuelve cuando seas {a:digno|digna}".
# Para añadir frases basta con sumarlas a las listas: no hace falta tocar código.

const P := Character.Personality
const ANY := -1

const LINES := {
	# --- Duelo ---
	"duel_open": {
		P.AMBICIOSO: ["Tu derrota me abrirá puertas, {player}. Nada personal.", "Hoy subo un peldaño, y tú serás el escalón, {a:muchacho|muchacha}."],
		P.LEAL: ["Lucho por el honor de mi señor, no por el mío. En guardia.", "Que gane quien mejor sirva a su casa."],
		P.PRUDENTE: ["Midamos fuerzas sin prisa. El primero en errar, pierde.", "He estudiado tu guardia, {player}. Veamos si te conozco bien."],
		P.ARROGANTE: ["¿Tú? Ni mi escudero sudaría contra ti.", "Arrodíllate ahora y te ahorraré la vergüenza."],
		P.PIADOSO: ["Que Dios juzgue quién tiene la razón.", "Rezaré por tu alma cuando esto termine, {player}."],
		P.ASTUTO: ["Vigila tus manos, {player}… y tu bolsa.", "Sonríe. La gente mira, y a mí me gusta el público."],
		P.VALIENTE: ["¡Por fin un rival que merece la pena! ¡A por ello!", "No he venido a hablar. ¡Desenvaina!"],
		P.CRUEL: ["Voy a disfrutar esto más que tú, {player}.", "Cuando acabe contigo, nadie recordará tu nombre."],
		P.GENEROSO: ["Que sea un combate limpio. Después, invito yo al vino.", "Te deseo suerte, {player}. De verdad."],
		P.COBARDE: ["¿No podríamos… resolverlo hablando?", "Ve despacio, ¿eh? Que esto es solo una prueba."],
		P.ROMANTICO: ["Que los juglares canten este duelo, {player}.", "Lucharé como si me mirara la persona que amo."],
		P.HONORABLE: ["Sin trucos ni bajezas. Que gane el mejor.", "Te saludo con la espada, {player}. Defiéndete."],
	},
	"duel_open_rival": {
		P.AMBICIOSO: ["Otra vez tú. Esta vez no te llevarás los laureles.", "Me has costado un ascenso, {player}. Hoy cobro la deuda."],
		P.LEAL: ["Nos volvemos a ver. Mi casa no olvida las afrentas.", "Prometí a mi señor que limpiaría su nombre. Hoy cumplo."],
		P.PRUDENTE: ["Ya conozco tus trucos, {player}. No me sorprenderás dos veces.", "He tenido tiempo de pensar en nuestro último duelo. Mucho tiempo."],
		P.ARROGANTE: ["La última vez fue suerte. Hoy te lo demuestro.", "Toda la corte se ríe de mí por tu culpa. Estoy {s:harto|harta}."],
		P.PIADOSO: ["He rezado para no odiarte. No siempre lo consigo.", "Que este duelo cierre por fin nuestra cuenta."],
		P.ASTUTO: ["He pagado a medio reino para saber cómo peleas, {player}.", "Esta vez tengo un as bajo la manga. O dos."],
		P.VALIENTE: ["¡La revancha! Llevaba semanas esperándola.", "Esta vez no retrocederé ni un paso."],
		P.CRUEL: ["Me humillaste. Hoy sangrarás por ello.", "He soñado con tu cara llena de barro, {player}."],
		P.GENEROSO: ["Sin rencor, pero esta vez pienso ganar.", "La última vez fuiste mejor. Veamos hoy."],
		P.COBARDE: ["Otra vez tú… Bueno. Acabemos rápido.", "Esta vez me he entrenado. Un poco."],
		P.ROMANTICO: ["Nuestra historia merece un segundo acto, {player}.", "Esta vez lucho por recuperar mi honra."],
		P.HONORABLE: ["Me venciste con justicia. Hoy busco lo mismo.", "La revancha es un derecho. Gracias por concedérmela."],
	},
	"duel_open_nemesis": {
		ANY: ["Llevo meses soñando con este momento, {player}.", "Solo uno de los dos saldrá de aquí con la cabeza alta.", "Tu nombre me quita el sueño. Hoy lo borro."],
		P.PIADOSO: ["Que el Cielo me perdone lo que voy a hacerte."],
		P.ARROGANTE: ["Hoy te devuelvo cada humillación, una por una."],
		P.CRUEL: ["Hoy no habrá piedad. Ni la pidas."],
		P.COBARDE: ["Me has quitado todo. Hasta el miedo."],
	},
	"duel_open_respect": {
		ANY: ["Será un honor medirme contigo otra vez, {player}.", "Pocos me han vencido. Tú lo hiciste con justicia. Adelante."],
		P.LEAL: ["Mi espada te saluda, {a:amigo|amiga}. Sin rencor."],
		P.PIADOSO: ["Que ambos salgamos de aquí con honra, sea cual sea el resultado."],
		P.HONORABLE: ["Es un privilegio cruzar aceros contigo."],
	},
	"taunt_hit": {
		P.AMBICIOSO: ["¡Así se gana una reputación!", "Cada golpe me acerca a lo que merezco."],
		P.LEAL: ["¡Por mi señor!", "Eso va por mi casa."],
		P.PRUDENTE: ["Justo donde dejaste el hueco.", "Paciencia… y precisión."],
		P.ARROGANTE: ["¿Eso te dolió? Ni siquiera lo intentaba.", "¡Mira, tiemblas!"],
		P.PIADOSO: ["Perdóname, pero debía hacerlo.", "Que esto te enseñe humildad."],
		P.ASTUTO: ["¿No lo viste venir? Nadie lo ve.", "Un truco viejo. Siempre funciona."],
		P.VALIENTE: ["¡Eso es luchar!", "¡Otra vez, si te atreves!"],
		P.CRUEL: ["Grita. Me gusta oírlo.", "Y aún me queda lo mejor."],
		P.GENEROSO: ["¿Estás bien? Puedo esperar a que te repongas.", "Buen intento el tuyo; mejor el mío."],
		P.COBARDE: ["¡Le di! ¡Le di de verdad!", "Uf… perdona, ¿te hice daño?"],
		P.ROMANTICO: ["¡Un golpe digno de una balada!", "Ese fue por los que me miran."],
		P.HONORABLE: ["Golpe limpio. Levanta la guardia.", "Te advertí que no bajaras el escudo."],
	},
	"taunt_hurt": {
		P.AMBICIOSO: ["No… no he llegado hasta aquí para esto.", "Un rasguño. Mi ambición sangra más despacio."],
		P.LEAL: ["Aguantaré. Mi señor cuenta conmigo.", "He sufrido peores heridas por mi casa."],
		P.PRUDENTE: ["Bien jugado. Me adaptaré.", "Error mío. No se repetirá."],
		P.ARROGANTE: ["¡¿Cómo te atreves?!", "¡Suerte! ¡Pura suerte!"],
		P.PIADOSO: ["Señor, dame fuerzas.", "Acepto el dolor como penitencia."],
		P.ASTUTO: ["Ah… esto no estaba en el plan.", "Hmm. Interesante. Muy interesante."],
		P.VALIENTE: ["¡Ja! ¡Eso es lo que quería!", "¡La sangre me despierta!"],
		P.CRUEL: ["Me las pagarás. Con creces.", "Acabas de firmar tu sentencia."],
		P.GENEROSO: ["Bien hecho. Me lo merecía.", "Golpeas fuerte, {player}."],
		P.COBARDE: ["¡Ay! ¡Basta, basta!", "Esto duele más de lo que pensaba…"],
		P.ROMANTICO: ["Una herida más que contar.", "¡Hasta el dolor tiene su belleza!"],
		P.HONORABLE: ["Bien merecido. Continúa.", "Reconozco el golpe."],
	},
	"taunt_low": {
		P.AMBICIOSO: ["Todavía puedo ganar esto. ¡Todavía!", "No me arrebatarás mi futuro."],
		P.LEAL: ["Si caigo, que me recuerden {s:honrado|honrada}.", "Mi casa sabrá que luché hasta el final."],
		P.PRUDENTE: ["Quizá sea el momento de pensar en rendirse…", "Calma. Una buena parada puede cambiarlo todo."],
		P.ARROGANTE: ["¡Jamás me rendiré ante alguien como tú!", "¡Esto no ha terminado!"],
		P.PIADOSO: ["Hágase tu voluntad.", "Si es mi hora, estoy en paz."],
		P.ASTUTO: ["¿Y si lo dejamos en empate? Te daría algo a cambio…", "Tengo un último truco. Creo."],
		P.VALIENTE: ["¡Mientras respire, lucharé!", "¡Ven! ¡Aún me tengo en pie!"],
		P.CRUEL: ["Si caigo, te llevo conmigo.", "Aún puedo hacerte mucho daño."],
		P.GENEROSO: ["Has luchado mejor que yo. Lo admito.", "Si caigo, cuida de los míos, ¿quieres?"],
		P.COBARDE: ["¡Me rindo! Bueno… casi.", "Por favor, no tan fuerte…"],
		P.ROMANTICO: ["Si he de caer, que sea con estilo.", "Un último baile, {player}."],
		P.HONORABLE: ["No pediré clemencia. Termina tu obra.", "Lucharé hasta el último aliento, como debe ser."],
	},
	"duel_win": {
		P.AMBICIOSO: ["Recordarán este día. Recordarán mi nombre.", "Un paso más hacia arriba."],
		P.LEAL: ["Por el honor de mi casa. Levántate, has luchado bien.", "Mi señor estará orgulloso."],
		P.PRUDENTE: ["Tal como lo había previsto.", "Aprende de esto, {player}. Yo lo hice."],
		P.ARROGANTE: ["Como era de esperar. Vuelve cuando seas {a:digno|digna}.", "Que lo canten los juglares: otra víctima más."],
		P.PIADOSO: ["Dios ha decidido. Que te cuiden esas heridas.", "Sin rencor. Rezaré por tu pronta cura."],
		P.ASTUTO: ["Te lo advertí: vigila tus manos.", "Un placer hacer negocios contigo."],
		P.VALIENTE: ["¡Qué combate! Repitámoslo cuando quieras.", "¡Victoria! Pero me hiciste sudar."],
		P.CRUEL: ["Arrástrate. Te queda bien.", "Esto es lo que les pasa a los que me desafían."],
		P.GENEROSO: ["Toma mi mano, levántate. Lo hiciste bien.", "Gané hoy, pero el vino lo pago yo."],
		P.COBARDE: ["¿He… he ganado? ¡He ganado!", "No me lo creo ni yo."],
		P.ROMANTICO: ["¡Que lo sepa todo el reino!", "Una victoria digna de un poema."],
		P.HONORABLE: ["Combatiste con honor. Levántate.", "Victoria justa. Que no haya rencor."],
	},
	"duel_lose": {
		P.AMBICIOSO: ["Esto no ha terminado. Volveré más fuerte.", "Disfruta tu victoria. Será la última."],
		P.LEAL: ["Has vencido con justicia. Mi espada te reconoce.", "He fallado a mi señor… pero no a mi palabra."],
		P.PRUDENTE: ["Aprenderé de esta derrota.", "Bien. Ahora sé lo que debo corregir."],
		P.ARROGANTE: ["¡Trampa! ¡Esto ha sido una trampa!", "Lo pagarás, {player}. Lo juro."],
		P.PIADOSO: ["Acepto el juicio de Dios.", "La humildad también es una victoria."],
		P.ASTUTO: ["Me has ganado hoy. Mañana… ya veremos.", "Muy bien. Tomo nota de tu deuda."],
		P.VALIENTE: ["¡Bien luchado! Quiero la revancha.", "Hoy fuiste mejor. Mañana, ya veremos."],
		P.CRUEL: ["Esto lo vas a lamentar.", "No olvido. Nunca olvido."],
		P.GENEROSO: ["Enhorabuena, {player}. Te lo has ganado.", "Una derrota honrosa. Brindemos igual."],
		P.COBARDE: ["Al menos sigo vivo… ¿no?", "Lo sabía. Lo sabía."],
		P.ROMANTICO: ["Una derrota bella sigue siendo una derrota…", "Hasta mi caída tendrá su canción."],
		P.HONORABLE: ["Reconozco tu victoria sin reservas.", "Has sido mejor. Así lo diré en la corte."],
	},

	# --- Rivalidad ---
	"rival_challenge": {
		P.AMBICIOSO: ["Te reto ante toda la corte, {player}. Si te niegas, todos sabrán por qué."],
		P.LEAL: ["Exijo satisfacción por el honor de mi casa. Elige el día."],
		P.PRUDENTE: ["He esperado el momento oportuno. Ha llegado: batámonos."],
		P.ARROGANTE: ["¡{player}! ¡Sal a la plaza si no eres {a:un cobarde|una cobarde}!"],
		P.PIADOSO: ["Que un duelo justo ponga fin a esta enemistad."],
		P.ASTUTO: ["Un duelo amistoso, {player}. Con apuesta, claro."],
		P.VALIENTE: ["¡Te reto, {player}! Mañana al alba, en el patio de armas."],
		P.CRUEL: ["Te espero en la plaza. Trae a alguien que recoja lo que quede."],
		P.GENEROSO: ["Resolvamos esto como es debido, y luego hagamos las paces."],
		P.COBARDE: ["Te… te reto. Ya está, ya lo he dicho."],
		P.ROMANTICO: ["¡Que el reino entero vea nuestro duelo, {player}!"],
		P.HONORABLE: ["Te reto formalmente, {player}, según las leyes de la caballería."],
	},
	"rival_news": {
		P.AMBICIOSO: ["{name} rechina los dientes al saber de tu victoria: «Le llegará su hora»."],
		P.LEAL: ["{name} reconoce tu hazaña a regañadientes: «Al menos lucha de frente»."],
		P.PRUDENTE: ["{name} toma nota de tu victoria y cambia de táctica."],
		P.ARROGANTE: ["{name} jura en la taberna que tu victoria fue pura suerte."],
		P.PIADOSO: ["{name} enciende una vela «por tu humildad, que tanta falta te hará»."],
		P.ASTUTO: ["{name} sonríe al oír la noticia: «Cuanto más alto suba, más dura la caída»."],
		P.VALIENTE: ["{name} brinda por tu victoria: «¡Así me gusta! Más gloria para cuando te venza»."],
		P.CRUEL: ["{name} rompe una copa al oír tu nombre."],
		P.GENEROSO: ["{name} reconoce en público que tu victoria fue merecida."],
		P.COBARDE: ["{name} palidece al saber de tu victoria y evita cruzarse contigo."],
		P.ROMANTICO: ["{name} compone versos amargos sobre tu victoria."],
		P.HONORABLE: ["{name} te felicita por carta, con letra firme y sin una queja."],
	},
	"rival_respect": {
		ANY: ["{name} te envía un mensaje: «Ya no te guardo rencor. Eres un rival digno»."],
	},
	"rival_rumor": {
		P.AMBICIOSO: ["Dicen que compraste tus victorias. Lo dice {name}, claro."],
		P.ARROGANTE: ["{name} va contando que huyes de los duelos como una gallina."],
		P.ASTUTO: ["Corre un rumor muy bien tejido sobre tus deudas. Huele a {name}."],
		P.CRUEL: ["{name} difunde que maltratas a tus criados. Es mentira, pero corre."],
		ANY: ["{name} murmura contra ti en los salones del castillo."],
	},

	# --- Trato personal: el saludo cambia con la intimidad ---
	"greet_stranger": {
		P.AMBICIOSO: ["¿Y tú quién eres? ¿Alguien que me convenga conocer?"],
		P.LEAL: ["Saludos. ¿A quién sirves?"],
		P.PRUDENTE: ["Buenos días. No creo que nos conozcamos."],
		P.ARROGANTE: ["¿Te he dado permiso para hablarme?"],
		P.PIADOSO: ["Dios te guarde, {a:forastero|forastera}."],
		P.ASTUTO: ["Una cara nueva… Qué interesante."],
		P.VALIENTE: ["¡Hola! ¿Luchas? Tienes pinta de luchar."],
		P.CRUEL: ["Apártate de mi camino."],
		P.GENEROSO: ["¡{a:Bienvenido|Bienvenida} seas! ¿Puedo ayudarte en algo?"],
		P.COBARDE: ["Eh… hola. No busco problemas."],
		P.ROMANTICO: ["Vaya, una presencia que no pasa desapercibida."],
		P.HONORABLE: ["Bien hallado, {rank}. Dime tu nombre."],
	},
	"greet_acquaintance": {
		P.AMBICIOSO: ["Ah, {player}. ¿Qué noticias traes?"],
		P.LEAL: ["Buen día, {player}."],
		P.PRUDENTE: ["De nuevo por aquí, {player}."],
		P.ARROGANTE: ["Ah, eres tú. Habla rápido."],
		P.PIADOSO: ["La paz sea contigo, {player}."],
		P.ASTUTO: ["{player}, justo pensaba en ti. Casualidad, claro."],
		P.VALIENTE: ["¡{player}! ¿Algún combate a la vista?"],
		P.CRUEL: ["Tú otra vez. ¿Qué quieres?"],
		P.GENEROSO: ["¡{player}! Siéntate, que traigan algo de beber."],
		P.COBARDE: ["Ah, eres tú. Menos mal."],
		P.ROMANTICO: ["{player}, qué alegría verte de nuevo."],
		P.HONORABLE: ["Bien hallado otra vez, {player}."],
	},
	"greet_friend": {
		P.AMBICIOSO: ["{player}, {a:amigo|amiga}. Tú y yo llegaremos lejos."],
		P.LEAL: ["Siempre es bueno ver una cara amiga, {player}."],
		P.PRUDENTE: ["Me alegra verte, {player}. Tengo algo que contarte."],
		P.ARROGANTE: ["Eres de los pocos con quien vale la pena hablar."],
		P.PIADOSO: ["Bendita la hora en que te conocí, {player}."],
		P.ASTUTO: ["A ti te cuento los secretos buenos, {player}."],
		P.VALIENTE: ["¡{player}! ¡Mi {a:compañero de armas favorito|compañera de armas favorita}!"],
		P.CRUEL: ["Tú no me molestas. Eso ya es mucho."],
		P.GENEROSO: ["¡{a:Amigo mío|Amiga mía}! Lo que necesites, pídelo."],
		P.COBARDE: ["Contigo cerca me siento más seguro.|Contigo cerca me siento más segura."],
		P.ROMANTICO: ["Tu amistad es de las cosas bellas de esta vida."],
		P.HONORABLE: ["Mi espada está a tu servicio, {a:amigo|amiga}."],
	},
	"greet_close": {
		P.AMBICIOSO: ["Contigo no necesito fingir, {player}."],
		P.LEAL: ["Por ti cruzaría el reino a pie, {player}."],
		P.PRUDENTE: ["Eres la única persona a quien escucho sin desconfiar."],
		P.ARROGANTE: ["Admito que te he echado de menos. No se lo digas a nadie."],
		P.PIADOSO: ["Rezo por ti cada noche, {player}."],
		P.ASTUTO: ["Contigo bajo la guardia. No sabes lo raro que es eso."],
		P.VALIENTE: ["¡{a:Hermano|Hermana} de armas!"],
		P.CRUEL: ["A ti no te haría daño. A nadie más le digo eso."],
		P.GENEROSO: ["Mi casa es tu casa, {player}. Siempre."],
		P.COBARDE: ["Si estás tú, ya no tengo tanto miedo."],
		P.ROMANTICO: ["Tus visitas son lo mejor de mis días."],
		P.HONORABLE: ["Te confiaría mi vida, {player}. Y mi honor."],
	},
	"greet_lover": {
		P.AMBICIOSO: ["Mi amor. Juntos seremos invencibles."],
		P.LEAL: ["Mi corazón es tuyo, {player}. Para siempre."],
		P.PRUDENTE: ["Te he esperado toda la tarde. No me hagas esperar tanto."],
		P.ARROGANTE: ["Llegas tarde. Pero te perdono… por esta vez."],
		P.PIADOSO: ["Doy gracias al Cielo por tenerte."],
		P.ASTUTO: ["Mi persona favorita del reino. Y conozco a todo el reino."],
		P.VALIENTE: ["¡Ven aquí! ¡Que me abraces, que no muerdo!"],
		P.CRUEL: ["Eres lo único que me ablanda. Que no se entere nadie."],
		P.GENEROSO: ["Todo lo mío es tuyo, {player}. Hasta el último suspiro."],
		P.COBARDE: ["Contigo me atrevo a todo."],
		P.ROMANTICO: ["¡Mi luz! Cada día sin ti es un invierno."],
		P.HONORABLE: ["Te he jurado amor como se jura lealtad: hasta el final."],
	},
	# --- Siervos (presos esclavizados), según cuánto te han llegado a apreciar ---
	"serf_greet_hostile": {
		ANY: ["¿Qué quieres ahora, {a:amo|ama}?", "Trabajo, como ordenaste. No esperes más."],
		P.ARROGANTE: ["Algún día serás tú quien me sirva."],
		P.CRUEL: ["Duermo con un ojo abierto. Tú también deberías."],
		P.HONORABLE: ["Me quitaste la libertad, no la dignidad."],
		P.COBARDE: ["S-sí, {a:amo|ama}. Lo que mandes."],
		P.ASTUTO: ["Sonrío, trabajo… y espero."],
		P.PIADOSO: ["Rezo por tu alma, que buena falta le hace."],
	},
	"serf_greet_resigned": {
		ANY: ["Al menos aquí no paso hambre.", "Hago mi parte. Tú haz la tuya."],
		P.LEAL: ["Sirvo bien a quien me trata bien."],
		P.AMBICIOSO: ["Si me dieras una oportunidad, te sería más útil libre."],
		P.ROMANTICO: ["Hay cadenas peores que las tuyas, {player}."],
		P.GENEROSO: ["Los demás siervos te respetan. Algo harás bien."],
	},
	"serf_greet_loyal": {
		ANY: ["Si me liberaras, seguiría a tu lado.", "Ya no te veo como {a:mi amo|mi ama}, {player}."],
		P.LEAL: ["Te serviré aunque no me lo pidas."],
		P.HONORABLE: ["Me ganaste con justicia. Te debo lealtad."],
		P.CRUEL: ["Que nadie te toque mientras yo viva."],
	},
	"serf_freed": {
		ANY: ["¿Libre? No lo olvidaré, {player}.", "Gracias. De verdad."],
		P.LEAL: ["Libre… y aun así me quedaría a tu servicio."],
		P.ARROGANTE: ["Era lo justo. Pero gracias."],
		P.ROMANTICO: ["¡Libre! Cantaré tu nombre por los caminos."],
	},
	# --- Presos en tus manos ---
	"prisoner_join": {
		ANY: ["Mejor servirte que pudrirme aquí.", "Trato hecho. Te serviré."],
		P.AMBICIOSO: ["Contigo hay más futuro que con mi antiguo señor."],
		P.COBARDE: ["¡Sí, sí! Lo que sea antes que la horca."],
		P.ASTUTO: ["Un cambio de bando a tiempo es una victoria."],
	},
	"prisoner_refuse": {
		ANY: ["No traicionaré a los míos.", "Antes la mazmorra."],
		P.LEAL: ["Mi señor vendrá a por mí. No le fallaré."],
		P.HONORABLE: ["Tengo un juramento. Haz conmigo lo que quieras."],
		P.ARROGANTE: ["¿Servirte yo? Ni encadenado."],
		P.CRUEL: ["Suéltame y te demostraré cómo sirvo."],
	},
	# --- Tu captor ---
	"captor_execute": {
		ANY: ["Al alba. Que Dios se apiade de ti, porque yo no.", "Has llegado al final del camino."],
		P.CRUEL: ["Disfrutaré viéndolo."],
		P.HONORABLE: ["Es la ley de la guerra. No lo hago por placer."],
	},
	"captor_ransom": {
		ANY: ["Tu libertad tiene un precio. Paga y vete.", "El oro abre todas las puertas. Hasta esta."],
		P.AMBICIOSO: ["Vales más vivo que muerto. Demuéstralo."],
		P.ASTUTO: ["Hagamos negocio, {a:amigo|amiga}."],
	},
	"captor_prison": {
		ANY: ["Una temporada a la sombra te enseñará modales.", "Aquí te quedas hasta que me plazca."],
		P.CRUEL: ["Las ratas te harán compañía."],
		P.PRUDENTE: ["Aún no sé qué hacer contigo. Mientras tanto, aquí."],
	},
	"captor_release": {
		ANY: ["Vete en paz. Pero no vuelvas a alzar la espada contra mí."],
		P.HONORABLE: ["Luchaste bien. Te dejo ir bajo palabra."],
		P.GENEROSO: ["Vete a casa. Hoy no ha de morir nadie más."],
	},
	"friendly_ok": {
		P.AMBICIOSO: ["Hablar contigo siempre me trae ideas."],
		P.LEAL: ["Es bueno hablar con alguien que cumple su palabra."],
		P.PRUDENTE: ["Hablas con sensatez. Eso escasea en la corte."],
		P.ARROGANTE: ["Admito que no eres tan {a:aburrido|aburrida} como los demás."],
		P.PIADOSO: ["Tu compañía es una bendición, {player}."],
		P.ASTUTO: ["Qué conversación tan… reveladora. Me caes bien."],
		P.VALIENTE: ["¡Ja! Me ha gustado esa historia. Cuéntame otra."],
		P.CRUEL: ["No ha estado mal. Para variar."],
		P.GENEROSO: ["¡Qué buena tarde! Repitámosla pronto."],
		P.COBARDE: ["Gracias por escucharme. No mucha gente lo hace."],
		P.ROMANTICO: ["Hablas como quien ha vivido mucho, {player}."],
		P.HONORABLE: ["Ha sido una conversación honesta. Te lo agradezco."],
	},
	"friendly_bad": {
		ANY: ["Perdona, me esperan en otra parte.", "Quizá otro día, {player}."],
		P.ARROGANTE: ["¿Ya terminaste? Bien."],
		P.ASTUTO: ["Te has dejado ver demasiado. Qué torpeza."],
		P.CRUEL: ["Me aburres."],
		P.COBARDE: ["Lo siento, tengo que… irme. Ya."],
	},
	"intimate_ok": {
		P.AMBICIOSO: ["Me gusta cómo me miras: como a alguien que llegará lejos."],
		P.LEAL: ["Nadie me había hablado así. Lo guardaré siempre."],
		P.PRUDENTE: ["No suelo dejarme llevar… pero contigo, sí."],
		P.ARROGANTE: ["Por fin alguien con buen gusto."],
		P.PIADOSO: ["Hay algo bueno en ti, {player}. Lo siento."],
		P.ASTUTO: ["Vaya. Eso no me lo esperaba. Me gusta."],
		P.VALIENTE: ["¡Dilo otra vez! ¡Más alto!"],
		P.CRUEL: ["Eres {a:el único|la única} que se atreve a acercarse tanto."],
		P.GENEROSO: ["Mi corazón es tuyo, si lo quieres."],
		P.COBARDE: ["Me tiemblan las piernas… pero de las buenas."],
		P.ROMANTICO: ["¡Por fin! Llevaba tanto tiempo esperando esto…"],
		P.HONORABLE: ["Tus intenciones son nobles. Lo sé. Y me alegra."],
	},
	"intimate_bad": {
		ANY: ["Vas demasiado deprisa, {player}.", "No… no es el momento."],
		P.PIADOSO: ["Eso no es decoroso, {player}."],
		P.ARROGANTE: ["¿Quién te has creído que eres?"],
		P.HONORABLE: ["Respétame, {player}. Así no."],
	},
	"intimate_refuse": {
		ANY: ["Te aprecio, {player}, pero no de esa manera.", "Prefiero que sigamos siendo amigos."],
		P.CRUEL: ["Ni lo sueñes."],
		P.ROMANTICO: ["Mi corazón ya pertenece a otra persona…"],
		P.PRUDENTE: ["No mezclemos las cosas. Valoro demasiado lo que tenemos."],
	},
	"gift_like": {
		P.AMBICIOSO: ["Exquisito. Tienes buen gusto… y bolsa."],
		P.ARROGANTE: ["Por fin alguien me trata como merezco."],
		P.ASTUTO: ["Un regalo con intención. Me gusta."],
		P.GENEROSO: ["¡No tenías por qué! Algún día te lo devolveré con creces."],
		P.ROMANTICO: ["¡Lo guardaré junto a mi corazón!"],
		P.CRUEL: ["No está mal. Lo acepto."],
		ANY: ["Qué detalle tan amable. Gracias, {player}."],
	},
	"gift_dislike": {
		P.PIADOSO: ["Estas riquezas estarían mejor en manos de los pobres."],
		P.PRUDENTE: ["Es demasiado. Me pregunto qué esperas a cambio."],
		P.HONORABLE: ["No acepto regalos que parezcan sobornos."],
		ANY: ["Oh. Gracias… supongo."],
	},
	"court_greet": {   # obsoleto: se mantiene por compatibilidad (usa friendly_ok)
		ANY: ["Es un placer hablar contigo, {player}."],
	},
	"court_cold": {    # obsoleto: se mantiene por compatibilidad (usa friendly_bad)
		ANY: ["Perdona, me esperan en otra parte."],
	},
	"proposal_yes": {
		P.AMBICIOSO: ["Sí. Juntos llegaremos muy lejos."],
		P.LEAL: ["Sí, {player}. Hasta el último de mis días."],
		P.PRUDENTE: ["Lo he pensado mucho. Sí, quiero."],
		P.ARROGANTE: ["Naturalmente. ¿Quién mejor que yo para ti?"],
		P.PIADOSO: ["Que Dios bendiga nuestra unión. Sí."],
		P.ASTUTO: ["Acepto. Y que conste que lo vi venir."],
		P.VALIENTE: ["¡Sí! ¡Mil veces sí!"],
		P.CRUEL: ["Sí. Y pobre de quien se interponga."],
		P.GENEROSO: ["Sí, y que lo celebre todo el pueblo, ¡invito yo!"],
		P.COBARDE: ["S-sí… sí. ¡Sí, quiero!"],
		P.ROMANTICO: ["¡Sí! Llevo toda la vida soñando con esto."],
		P.HONORABLE: ["Acepto, y te juro fidelidad ante Dios y los hombres."],
	},
	"proposal_no": {
		ANY: ["Aún no, {player}. Dame tiempo.", "Me halagas, pero aún no estoy {s:listo|lista}."],
		P.ARROGANTE: ["¿Casarme contigo? Tendrás que esforzarte más."],
		P.COBARDE: ["Es… es demasiado pronto."],
	},
	"suitor_rival": {
		P.ARROGANTE: ["{name} proclama que le arrebatará el corazón de tu amor «como quien recoge una flor»."],
		P.AMBICIOSO: ["{name} corteja a tu amor con regalos caros y promesas de grandeza."],
		P.ASTUTO: ["{name} ha empezado a frecuentar a tu amor. Siempre aparece justo después de ti."],
		P.ROMANTICO: ["{name} canta bajo la ventana de tu amor cada noche."],
		P.CRUEL: ["{name} ha dejado claro que nadie más cortejará a tu amor. Nadie."],
		ANY: ["{name} también pretende a tu amor, y no lo disimula."],
	},
	"love_letter": {
		P.AMBICIOSO: ["«Cuando subas al lugar que mereces, quiero estar a tu lado, {a:mi señor|mi señora}»."],
		P.LEAL: ["«Pienso en ti cada día. Vuelve pronto»."],
		P.PRUDENTE: ["«No suelo escribir estas cosas. Pero contigo, quiero hacerlo»."],
		P.ARROGANTE: ["«Considérate {a:afortunado|afortunada}: no escribo a cualquiera»."],
		P.PIADOSO: ["«Rezo por ti cada noche. Que Dios te guarde»."],
		P.ASTUTO: ["«He descubierto algo que te interesa. Ven a verme y te lo cuento… en persona»."],
		P.VALIENTE: ["«¡Ven a verme ya! Que la espera me mata más que cualquier espada»."],
		P.CRUEL: ["«Eres mío. Que nadie lo olvide»."],
		P.GENEROSO: ["«Te mando pan de mi horno y todo mi cariño»."],
		P.COBARDE: ["«No me atreví a decírtelo en persona, así que lo escribo: te echo de menos»."],
		P.ROMANTICO: ["«Cada estrella de esta noche lleva tu nombre»."],
		P.HONORABLE: ["«Mi palabra y mi afecto son tuyos. Ambos valen lo mismo»."],
	},
	"spouse_month": {
		P.AMBICIOSO: ["«¿Cuándo vas a pedir ese ascenso? No nos casamos para quedarnos quietos»."],
		P.LEAL: ["«Pase lo que pase, estoy contigo»."],
		P.PRUDENTE: ["«Escúchame antes de tomar la próxima decisión. Tengo una idea»."],
		P.ARROGANTE: ["«Nuestros vecinos nos miran por encima del hombro. Inaceptable»."],
		P.PIADOSO: ["«He repartido pan entre los pobres en tu nombre»."],
		P.ASTUTO: ["«Tengo oídos en todas las cocinas del reino. Te traigo noticias»."],
		P.VALIENTE: ["«¡Llévame contigo a la próxima batalla!»"],
		P.CRUEL: ["«Un criado me ha faltado al respeto. Que lo azoten»."],
		P.GENEROSO: ["«He invitado a medio pueblo a cenar. ¿Te importa?»"],
		P.COBARDE: ["«¿Tienes que ir otra vez a la guerra? Me muero de miedo»."],
		P.ROMANTICO: ["«Te he preparado una sorpresa para esta noche»."],
		P.HONORABLE: ["«Nuestra casa debe dar ejemplo. Cuidemos nuestro nombre»."],
	},

	# --- Retos de duelo a personajes de la zona ---
	"challenge_accept": {
		P.AMBICIOSO: ["Acepto. Me vendrá bien una victoria a tu costa."],
		P.LEAL: ["Acepto, si mi señor no lo prohíbe."],
		P.PRUDENTE: ["Acepto. Pero elegiré yo el terreno."],
		P.ARROGANTE: ["¿Me retas a mí? Encantado de humillarte.|¿Me retas a mí? Encantada de humillarte."],
		P.PIADOSO: ["Si ha de ser, que sea limpio."],
		P.ASTUTO: ["Acepto. Las condiciones, mañana."],
		P.VALIENTE: ["¡Por fin! ¡Acepto ahora mismo!"],
		P.CRUEL: ["Acepto. No te va a gustar."],
		P.GENEROSO: ["Acepto, pero sin mala sangre."],
		P.COBARDE: ["Bueno… si no hay más remedio."],
		P.ROMANTICO: ["¡Acepto! Será memorable."],
		P.HONORABLE: ["Acepto tu reto con honor."],
	},
	"challenge_refuse_rank": {
		P.ARROGANTE: ["¿Batirme con alguien de tu condición? Ni en sueños."],
		P.AMBICIOSO: ["No gano nada venciendo a alguien de tu rango."],
		P.HONORABLE: ["Las leyes de la caballería no me permiten batirme contigo."],
		P.CRUEL: ["Haré que te azoten por la insolencia."],
		ANY: ["No me bato con quien no es de mi rango, {player}.", "Busca rivales de tu condición."],
	},
	"challenge_refuse_fear": {
		P.COBARDE: ["¿Yo? ¡No, no, no! Busca a otro."],
		P.PRUDENTE: ["Conozco tu fama. No me conviene."],
		P.ASTUTO: ["No soy tan tonto como para aceptar.|No soy tan tonta como para aceptar."],
		ANY: ["Hoy no, {player}.", "Tu fama te precede. Paso."],
	},
	"champion_win": {
		ANY: ["Victoria en tu nombre, {player}.", "Te dije que podías confiar en mi espada."],
		P.VALIENTE: ["¡Ja! ¡Para eso estoy!"],
		P.LEAL: ["Mi brazo es tuyo. Siempre."],
		P.ARROGANTE: ["Naturalmente. ¿Acaso lo dudabas?"],
	},
	"champion_lose": {
		ANY: ["Lo siento, {player}. Te he fallado.", "Hice lo que pude…"],
		P.HONORABLE: ["Perdí con honor. No volverá a pasar."],
		P.CRUEL: ["La próxima vez no tendré piedad."],
	},
	"retinue_join": {
		P.AMBICIOSO: ["Contigo llegaré más lejos. Cuenta conmigo."],
		P.LEAL: ["Te seguiré a donde vayas, {player}."],
		P.PRUDENTE: ["He visto cómo actúas. Me uno a ti."],
		P.ARROGANTE: ["Me uniré a ti. Considéralo un honor."],
		P.PIADOSO: ["Si tu causa es justa, mi espada es tuya."],
		P.ASTUTO: ["Bien. Pero quiero mi parte del botín."],
		P.VALIENTE: ["¡Por fin una aventura! ¡Me apunto!"],
		P.CRUEL: ["Mientras haya sangre, iré contigo."],
		P.GENEROSO: ["¡Encantado de ayudarte!|¡Encantada de ayudarte!"],
		P.COBARDE: ["Contigo me siento a salvo. Iré."],
		P.ROMANTICO: ["¡Cabalgaremos juntos hacia la gloria!"],
		P.HONORABLE: ["Te juro lealtad como compañero de armas.|Te juro lealtad como compañera de armas."],
	},
	"retinue_refuse": {
		ANY: ["Aún no te conozco lo bastante, {player}.", "Todavía no. Demuéstrame quién eres."],
		P.ARROGANTE: ["¿Seguirte yo a ti? Al revés, en todo caso."],
		P.AMBICIOSO: ["Tu nombre aún no suena lo suficiente."],
		P.HONORABLE: ["Tu honor aún no está a la altura de mi juramento."],
	},
	"retinue_battle": {
		P.AMBICIOSO: ["Hoy ganaremos fama los dos."],
		P.LEAL: ["Estoy a tu lado, {player}. Pase lo que pase."],
		P.PRUDENTE: ["Mantén la formación y saldremos con vida."],
		P.ARROGANTE: ["Déjame la mejor parte. Te lo agradecerán."],
		P.PIADOSO: ["Que Dios guíe nuestras espadas."],
		P.ASTUTO: ["He visto un punto débil en su flanco. Confía en mí."],
		P.VALIENTE: ["¡A la carga! ¡Que nos recuerden!"],
		P.CRUEL: ["No dejaremos a ninguno en pie."],
		P.GENEROSO: ["Cuidaré de tus hombres como si fueran míos."],
		P.COBARDE: ["Yo… iré detrás. Por si acaso."],
		P.ROMANTICO: ["¡Una batalla digna de una canción!"],
		P.HONORABLE: ["Lucharemos con honor, ganemos o perdamos."],
	},
	"faction_companion": {
		ANY: ["Mi señor me envía a luchar a tu lado. Cumpliré mis órdenes.", "Vengo por orden de nuestro señor. No esperes más que eso."],
		P.LEAL: ["Nuestro señor me ordena acompañarte. Lo haré con gusto."],
		P.ARROGANTE: ["Me han mandado a hacerte de niñera. Qué remedio."],
		P.COBARDE: ["Me han enviado contigo… Espero que sepas lo que haces."],
	},

	# --- Señores ---
	"lord_gift": {
		P.AMBICIOSO: ["«Un gesto inteligente. Lo recordaré cuando convenga»."],
		P.LEAL: ["«Acepto tu presente como prenda de amistad»."],
		P.PRUDENTE: ["«Agradezco el regalo. Veremos si tus actos lo acompañan»."],
		P.ARROGANTE: ["«Es lo mínimo que se espera de alguien de tu rango»."],
		P.PIADOSO: ["«Lo destinaré a la capilla. Dios te lo pague»."],
		P.ASTUTO: ["«Qué generoso… ¿Qué necesitas?»"],
		P.VALIENTE: ["«¡Un buen regalo! Te debo una cacería»."],
		P.CRUEL: ["«Lo acepto. No esperes nada a cambio»."],
		P.GENEROSO: ["«¡Gracias! Te enviaré algo mejor aún»."],
		P.COBARDE: ["«Gracias… ¿esto no me compromete a nada, verdad?»"],
		P.ROMANTICO: ["«¡Qué detalle tan delicado!»"],
		P.HONORABLE: ["«Lo acepto como muestra de respeto, y así lo devolveré»."],
	},
	"lord_alliance_yes": {
		ANY: ["«Que nuestras espadas defiendan las mismas murallas»."],
		P.LEAL: ["«Mi palabra es mi ley. Cuenta conmigo»."],
		P.ASTUTO: ["«Una alianza beneficiosa… para ambos, por ahora»."],
		P.HONORABLE: ["«Juro defender tus tierras como las mías»."],
	},
	"lord_war": {
		P.ARROGANTE: ["«¿Guerra? Te aplastaré antes del invierno»."],
		P.PIADOSO: ["«Que Dios perdone la sangre que vas a derramar»."],
		P.PRUDENTE: ["«Lo lamentarás. Mis murallas son pacientes»."],
		P.CRUEL: ["«Quemaré tus campos y salaré la tierra»."],
		P.COBARDE: ["«¡¿Guerra?! ¡Reforzad las murallas!»"],
		ANY: ["«Recordaré esta traición»."],
	},
	"liege_marriage_offer": {
		P.AMBICIOSO: ["Te ofrezco la mano de alguien de mi casa. Nos conviene a los dos."],
		P.LEAL: ["Has servido bien. Quiero unir nuestras familias."],
		P.PRUDENTE: ["Un matrimonio sellaría tu lealtad. Piénsalo con calma."],
		P.ARROGANTE: ["Te concedo el honor de casarte con alguien de mi sangre. No lo rechaces."],
		P.PIADOSO: ["Que Dios bendiga la unión que te propongo."],
		P.ASTUTO: ["Tengo a la persona perfecta para ti. Perfecta para mí, también."],
		ANY: ["Mi casa te ofrece una alianza por matrimonio."],
	},
	"liege_task": {
		P.AMBICIOSO: ["Tengo un encargo que puede hacernos ganar a ambos."],
		P.LEAL: ["Confío en ti para esto, {player}."],
		P.PRUDENTE: ["Escucha bien, que no quiero errores."],
		P.ARROGANTE: ["Haz esto y no me hagas repetirlo."],
		P.PIADOSO: ["Es una tarea justa. Cúmplela con rectitud."],
		P.ASTUTO: ["Necesito discreción. Y resultados."],
		P.VALIENTE: ["¡Una misión digna de ti!"],
		P.CRUEL: ["Cumple, o atente a las consecuencias."],
		P.GENEROSO: ["Si lo logras, serás bien {a:recompensado|recompensada}."],
		P.COBARDE: ["Ve tú, que yo… coordino desde aquí."],
		P.ROMANTICO: ["¡Una gesta te espera, {player}!"],
		P.HONORABLE: ["Te encomiendo esta tarea con plena confianza."],
	},
	"exhibition_challenge": {
		ANY: ["Mi señor propone un duelo de exhibición entre nuestros reinos. ¿Aceptas?", "Que nuestros reinos midan su valía en la arena."],
		P.ARROGANTE: ["Vengo a demostrar que mi reino tiene mejores caballeros."],
		P.HONORABLE: ["Un duelo de exhibición, con honor y sin rencor entre reinos."],
		P.VALIENTE: ["¡He cruzado medio reino para batirme contigo!"],
	},

	# --- Pueblo llano: campesinos y soldados ---
	"commoner_greet": {
		P.AMBICIOSO: ["{rank}, si necesitáis a alguien dispuesto, aquí estoy."],
		P.LEAL: ["A vuestro servicio, {rank}."],
		P.PRUDENTE: ["Buenos días, {rank}. ¿En qué puedo serviros?"],
		P.ARROGANTE: ["Ah, {rank}. ¿Venís a ver cómo trabaja la gente de verdad?"],
		P.PIADOSO: ["Dios os bendiga, {rank}."],
		P.ASTUTO: ["{rank}, sé cosas que os interesarían… por un precio justo."],
		P.VALIENTE: ["¡{rank}! Si hay pelea, contad conmigo."],
		P.CRUEL: ["¿Qué queréis, {rank}?"],
		P.GENEROSO: ["¡{rank}! Tomad un poco de pan, recién hecho."],
		P.COBARDE: ["¡{rank}! Yo no he hecho nada, lo juro."],
		P.ROMANTICO: ["{rank}, qué honor que os paréis a hablar conmigo."],
		P.HONORABLE: ["{rank}. Os saludo con respeto."],
	},


	# --- Conversaciones por actitud (talk_<actitud>_good / _bad) ---
	"talk_amable_good": {
		P.AMBICIOSO: ["Una charla agradable. Y útil, quién sabe."],
		P.LEAL: ["Da gusto hablar con alguien de fiar, {player}."],
		P.PRUDENTE: ["Una conversación tranquila. Se agradece en esta corte."],
		P.ARROGANTE: ["Sabes comportarte. Eso ya es algo."],
		P.PIADOSO: ["Tu bondad se nota, {player}. Que Dios te la conserve."],
		P.ASTUTO: ["Qué {a:amable|amable}… casi sospecho. Casi."],
		P.VALIENTE: ["¡Bien dicho! Me caes bien, {player}."],
		P.CRUEL: ["Hm. Hoy no me molestas."],
		P.GENEROSO: ["¡Qué alegría charlar contigo! Vuelve cuando quieras."],
		P.COBARDE: ["Gracias por tratarme bien. No es lo habitual."],
		P.ROMANTICO: ["Tus palabras tienen algo cálido, {player}."],
		P.HONORABLE: ["Cortesía sincera. Te la devuelvo de corazón."],
	},
	"talk_amable_bad": {
		ANY: ["Sí, sí… muy amable. Tengo cosas que hacer.", "No estoy de humor, {player}."],
		P.CRUEL: ["Tanta dulzura me revuelve el estómago."],
		P.ARROGANTE: ["¿Buscas mi favor con buenos modales? Hará falta más."],
		P.ASTUTO: ["¿Qué quieres de mí con tanta amabilidad?"],
	},
	"talk_halagador_good": {
		P.AMBICIOSO: ["Por fin alguien que ve lo lejos que voy a llegar."],
		P.LEAL: ["Me halagas… pero lo agradezco."],
		P.PRUDENTE: ["Palabras bonitas. Las tomaré con moderación… y con gusto."],
		P.ARROGANTE: ["Naturalmente. Me alegra que lo reconozcas."],
		P.PIADOSO: ["No merezco tanto elogio, pero gracias."],
		P.ASTUTO: ["Sabes adular con arte. Eso me gusta."],
		P.VALIENTE: ["¡Ja! Lo dices porque me has visto pelear."],
		P.CRUEL: ["Adula cuanto quieras. Me divierte."],
		P.GENEROSO: ["¡Me vas a sonrojar, {player}!"],
		P.COBARDE: ["¿De verdad piensas eso de mí?"],
		P.ROMANTICO: ["Qué palabras tan bellas, {player}…"],
		P.HONORABLE: ["Agradezco el elogio, aunque prefiero los hechos."],
	},
	"talk_halagador_bad": {
		ANY: ["Ahórrate los halagos, {player}.", "Eso suena a lisonja barata."],
		P.PRUDENTE: ["Quien mucho halaga, algo busca."],
		P.HONORABLE: ["La adulación no es digna de ti."],
		P.LEAL: ["No me gustan las palabras huecas."],
	},
	"talk_franco_good": {
		P.AMBICIOSO: ["Directo. Sin rodeos. Así se hacen los negocios."],
		P.LEAL: ["Me gusta que me hables claro. Cuenta conmigo."],
		P.PRUDENTE: ["La verdad sin adornos. Lo valoro más que cualquier halago."],
		P.ARROGANTE: ["Tienes agallas para hablarme así. Respeto eso."],
		P.PIADOSO: ["La sinceridad es una virtud, {player}."],
		P.ASTUTO: ["Una persona sincera… qué rareza. Te creo."],
		P.VALIENTE: ["¡Así me gusta! Cara a cara."],
		P.CRUEL: ["Al menos no finges. Eso te honra."],
		P.GENEROSO: ["Gracias por ser {a:sincero|sincera} conmigo."],
		P.COBARDE: ["Me asusta un poco… pero tienes razón."],
		P.ROMANTICO: ["Tu franqueza también tiene su encanto."],
		P.HONORABLE: ["Palabra clara, alma limpia. Te estrecho la mano."],
	},
	"talk_franco_bad": {
		ANY: ["Eso ha sido demasiado directo, {player}.", "No te he pedido tu opinión."],
		P.ARROGANTE: ["¿Cómo te atreves a hablarme así?"],
		P.COBARDE: ["¿Por qué me dices algo así? Me ofendes."],
		P.ROMANTICO: ["Qué palabras tan frías…"],
	},
	"talk_amenazante_good": {
		ANY: ["Está bien, está bien… no quiero problemas.", "Entendido. Haré lo que dices."],
		P.COBARDE: ["¡Por favor! Toma lo que quieras, pero déjame en paz."],
		P.ASTUTO: ["Calma, {player}. Podemos llegar a un acuerdo."],
		P.AMBICIOSO: ["Tomo nota de tu fuerza. Quizá me convenga estar de tu lado."],
	},
	"talk_amenazante_bad": {
		ANY: ["¿Me amenazas? No lo olvidaré.", "Ten cuidado con lo que dices, {player}."],
		P.VALIENTE: ["¿Amenazas? ¡Saca la espada si te atreves!"],
		P.ARROGANTE: ["¿Tú, amenazarme a mí? Qué ridículo."],
		P.CRUEL: ["Cuidado. Yo también sé hacer daño."],
		P.HONORABLE: ["Las amenazas son el recurso de los cobardes."],
	},
	"talk_intima_good": {
		P.AMBICIOSO: ["Contigo podría subir muy alto… y no solo de rango."],
		P.LEAL: ["Puedes contar conmigo. Para lo que sea."],
		P.PRUDENTE: ["No suelo abrirme así. Pero contigo, sí."],
		P.ARROGANTE: ["Admito que me haces sentir… distinto. No se lo digas a nadie."],
		P.PIADOSO: ["Siento que Dios nos ha puesto en el mismo camino."],
		P.ASTUTO: ["Por una vez, no estoy calculando nada. Qué raro."],
		P.VALIENTE: ["Me late el corazón más fuerte que en cualquier batalla."],
		P.CRUEL: ["No te acostumbres… pero me gusta esto."],
		P.GENEROSO: ["Todo lo mío es tuyo, {player}."],
		P.COBARDE: ["Contigo no tengo miedo."],
		P.ROMANTICO: ["Llevaba tanto tiempo esperando oírte decir esto…"],
		P.HONORABLE: ["Mi palabra y mi corazón, si los quieres."],
	},
	"talk_intima_bad": {
		ANY: ["Vas demasiado deprisa, {player}.", "No… no estoy {s:preparado|preparada} para esto."],
		P.PIADOSO: ["Esto no es apropiado, {player}."],
		P.PRUDENTE: ["Démonos tiempo."],
		P.CRUEL: ["¿Esperabas que me derritiera? Qué ingenuidad."],
	},

	# --- Obsoletos (se mantienen vacíos de gestos eliminados) ---
}

# Descripción breve de cada personalidad: cómo se comporta en duelo y en el trato.
const PERSONALITY_DESCRIPTIONS := {
	P.AMBICIOSO: "Quiere subir a toda costa. Aprieta en duelo cuando va ganando y aprecia los regalos y las victorias.",
	P.LEAL: "Fiel a su señor y a sus amigos. Pelea con disciplina y valora la constancia en el trato.",
	P.PRUDENTE: "Calculador y paciente. Se cubre y para los golpes; desconfía de los regalos caros.",
	P.ARROGANTE: "Se cree superior. Ataca sin descanso y nunca se rinde; solo los gestos grandiosos le impresionan.",
	P.PIADOSO: "Devoto y compasivo. Pelea a la defensiva y le disgustan el lujo y la violencia gratuita.",
	P.ASTUTO: "Intrigante y oportunista. Desarma y empuja en duelo; todo trato es para él una negociación.",
	P.VALIENTE: "No conoce el miedo. Siempre al ataque, jamás huye, y admira a quien le planta cara.",
	P.CRUEL: "Disfruta del sufrimiento ajeno. Remata sin piedad y responde mal a la amabilidad.",
	P.GENEROSO: "Comparte lo que tiene. Prefiere desarmar a herir y agradece la amistad sincera.",
	P.COBARDE: "Teme el dolor. Se esconde tras el escudo, esquiva y huye si la cosa se pone fea.",
	P.ROMANTICO: "Vive para las grandes pasiones. Pelea con florituras y adora los gestos íntimos.",
	P.HONORABLE: "Sigue el código de la caballería. Nunca usa trucos sucios y prefiere la parada limpia.",
}

# Gusto por cada tipo de interacción (multiplicador: 1 neutral, ≤0.5 le disgusta).
const INTERACTION_LIKES := {
	P.AMBICIOSO: {"friendly": 1.0, "intimate": 1.0, "gift": 1.5},
	P.LEAL: {"friendly": 1.4, "intimate": 1.1, "gift": 0.9},
	P.PRUDENTE: {"friendly": 1.3, "intimate": 0.8, "gift": 0.5},
	P.ARROGANTE: {"friendly": 0.7, "intimate": 1.0, "gift": 1.6},
	P.PIADOSO: {"friendly": 1.3, "intimate": 0.6, "gift": 0.4},
	P.ASTUTO: {"friendly": 1.2, "intimate": 0.9, "gift": 1.2},
	P.VALIENTE: {"friendly": 1.2, "intimate": 1.2, "gift": 0.8},
	P.CRUEL: {"friendly": 0.5, "intimate": 0.8, "gift": 1.3},
	P.GENEROSO: {"friendly": 1.5, "intimate": 1.1, "gift": 0.7},
	P.COBARDE: {"friendly": 1.3, "intimate": 0.7, "gift": 1.1},
	P.ROMANTICO: {"friendly": 1.0, "intimate": 1.7, "gift": 1.2},
	P.HONORABLE: {"friendly": 1.2, "intimate": 0.9, "gift": 0.5},
}

# --- Conversaciones por actitud ---
# Actitudes: id -> nombre visible. "intima" solo con romance posible (hombre y mujer) y confianza.
const ATTITUDES := {
	"amable": "Amable", "halagador": "Halagador", "franco": "Franco",
	"amenazante": "Amenazante", "intima": "Charla íntima",
}
const ATTITUDE_HINTS := {
	"amable": "Trato cordial: seguro, sube poco la intimidad.",
	"halagador": "Elogios: depende de tu Carisma; los vanidosos lo adoran, los prudentes desconfían.",
	"franco": "Hablar claro: lo valoran los leales, honorables y prudentes; ofende a los arrogantes.",
	"amenazante": "Intimidar: baja la intimidad, pero quien te teme puede soltar oro o rumores. Requiere honor o rango.",
	"intima": "Abrir el corazón: puede nacer el romance. Depende del Carisma y de la confianza.",
}
# Reacción de cada personalidad a cada actitud (multiplicador; 1 neutral, ≤0.5 le disgusta).
const ATTITUDE_REACTIONS := {
	P.AMBICIOSO: {"amable": 1.0, "halagador": 1.5, "franco": 1.1, "amenazante": 0.8, "intima": 1.0},
	P.LEAL: {"amable": 1.3, "halagador": 0.6, "franco": 1.5, "amenazante": 0.3, "intima": 1.1},
	P.PRUDENTE: {"amable": 1.2, "halagador": 0.5, "franco": 1.4, "amenazante": 0.4, "intima": 0.8},
	P.ARROGANTE: {"amable": 0.7, "halagador": 1.7, "franco": 0.4, "amenazante": 0.3, "intima": 1.0},
	P.PIADOSO: {"amable": 1.5, "halagador": 0.7, "franco": 1.2, "amenazante": 0.2, "intima": 0.6},
	P.ASTUTO: {"amable": 0.9, "halagador": 1.2, "franco": 1.0, "amenazante": 0.9, "intima": 0.9},
	P.VALIENTE: {"amable": 1.0, "halagador": 0.8, "franco": 1.4, "amenazante": 0.5, "intima": 1.2},
	P.CRUEL: {"amable": 0.4, "halagador": 1.1, "franco": 1.2, "amenazante": 1.0, "intima": 0.8},
	P.GENEROSO: {"amable": 1.6, "halagador": 1.0, "franco": 1.1, "amenazante": 0.2, "intima": 1.1},
	P.COBARDE: {"amable": 1.4, "halagador": 1.2, "franco": 0.6, "amenazante": 1.3, "intima": 0.7},
	P.ROMANTICO: {"amable": 1.2, "halagador": 1.4, "franco": 0.6, "amenazante": 0.3, "intima": 1.7},
	P.HONORABLE: {"amable": 1.2, "halagador": 0.5, "franco": 1.6, "amenazante": 0.2, "intima": 0.9},
}

static func attitude_reaction(personality: int, attitude: String) -> float:
	return ATTITUDE_REACTIONS.get(personality, {}).get(attitude, 1.0)

const PERSONALITY_NAMES := {
	P.AMBICIOSO: "Ambicioso", P.LEAL: "Leal", P.PRUDENTE: "Prudente",
	P.ARROGANTE: "Arrogante", P.PIADOSO: "Piadoso", P.ASTUTO: "Astuto",
	P.VALIENTE: "Valiente", P.CRUEL: "Cruel", P.GENEROSO: "Generoso",
	P.COBARDE: "Cobarde", P.ROMANTICO: "Romántico", P.HONORABLE: "Honorable",
}

# Umbrales de intimidad (Relationship.affection): desconocido, conocido, amigo, confidente, íntimo.
const INTIMACY_THRESHOLDS := [0, 20, 40, 60, 80]
const GREET_TOPICS := ["greet_stranger", "greet_acquaintance", "greet_friend", "greet_close", "greet_lover"]

static var _last_used := {}   # tema+personalidad -> última frase (para no repetirla seguido)
static var _gender_regex: RegEx

## Frase de un personaje sobre un tema, según su personalidad, con el género concordado
## con quien habla (speaker) y con quien escucha (listener). Devuelve "" si el tema no existe.
## Una frase con variantes "masculina|femenina" sin marcador se resuelve por el género de quien habla.
static func line(topic: String, speaker: Character, listener: Character = null, ctx: Dictionary = {}) -> String:
	var by_personality: Dictionary = LINES.get(topic, {})
	if by_personality.is_empty():
		return ""
	var personality: int = speaker.personality if speaker != null else ANY
	var options: Array = by_personality.get(personality, by_personality.get(ANY, []))
	if options.is_empty():
		options = by_personality.values()[0]
	var key := "%s:%d" % [topic, personality]
	var pool := options.duplicate()
	if pool.size() > 1 and _last_used.has(key):
		pool.erase(_last_used[key])
	var chosen: String = pool.pick_random()
	_last_used[key] = chosen
	var values := ctx.duplicate()
	if speaker != null and not values.has("name"):
		values["name"] = speaker.full_name()
	if not values.has("rank"):
		values["rank"] = rank_address(listener)
	var text := _apply_gender(chosen, speaker, listener)
	# Frase completa en dos versiones ("...|...") fuera de los marcadores: elige la de quien habla.
	if text.contains("|"):
		var parts := text.split("|")
		var female: bool = speaker != null and speaker.gender == CharacterEnums.Gender.FEMENINO
		text = parts[1] if female and parts.size() > 1 else parts[0]
	return text.format(values)

## Saludo según la intimidad (tema greet_*).
static func greeting(speaker: Character, listener: Character, affection: int, romance: bool, ctx: Dictionary = {}) -> String:
	var tier := intimacy_tier(affection)
	if tier >= 4 and not romance:
		tier = 3   # sin romance, el máximo es la confianza de un amigo íntimo
	return line(GREET_TOPICS[tier], speaker, listener, ctx)

## Resuelve {a:masc|fem} (quien escucha) y {s:masc|fem} (quien habla).
static func _apply_gender(text: String, speaker: Character, listener: Character) -> String:
	if not text.contains("{a:") and not text.contains("{s:"):
		return text
	if _gender_regex == null:
		_gender_regex = RegEx.create_from_string("\\{([as]):([^|}]*)\\|([^}]*)\\}")
	var result := text
	for m in _gender_regex.search_all(text):
		var who := listener if m.get_string(1) == "a" else speaker
		var female: bool = who != null and who.gender == CharacterEnums.Gender.FEMENINO
		result = result.replace(m.get_string(0), m.get_string(3) if female else m.get_string(2))
	return result

## Tratamiento respetuoso hacia un personaje según su rango y género.
static func rank_address(c: Character) -> String:
	if c == null:
		return "señor"
	var female := c.gender == CharacterEnums.Gender.FEMENINO
	match c.role:
		Character.Role.CAMPESINO: return "comadre" if female else "compadre"
		Character.Role.SOLDADO: return "soldado"
		Character.Role.CABALLERO: return "dama" if female else "señor caballero"
		Character.Role.NOBLEZA_BAJA, Character.Role.NOBLEZA_ALTA: return "mi señora" if female else "mi señor"
		Character.Role.REGENTE: return "majestad"
		Character.Role.DUQUE: return "vuestra gracia"
		Character.Role.MERCENARIO: return "espada de alquiler"
		Character.Role.CAPITAN: return "capitana" if female else "capitán"
		Character.Role.CONDOTIERO: return "mi señora" if female else "mi señor"
	return "señor"

## Gusto de una personalidad por un tipo de interacción ("friendly", "intimate", "gift").
## 1.0 es neutral; 0.5 o menos significa que le disgusta.
static func interaction_like(personality: int, kind: String) -> float:
	return INTERACTION_LIKES.get(personality, {}).get(kind, 1.0)

## Compatibilidad con código anterior (gestos de cortejo).
static func romance_like(personality: int, gesture: String) -> float:
	match gesture:
		"talk": return interaction_like(personality, "friendly")
		"gift": return interaction_like(personality, "gift")
	return interaction_like(personality, "intimate")

## Nivel de intimidad: 0 desconocido, 1 conocido, 2 amigo, 3 confidente, 4 íntimo.
static func intimacy_tier(affection: int) -> int:
	var tier := 0
	for i in range(INTIMACY_THRESHOLDS.size()):
		if affection >= INTIMACY_THRESHOLDS[i]:
			tier = i
	return tier

## Nombre del nivel de intimidad, concordado con el género del personaje.
## El nivel más alto es "Íntimo/Íntima", haya romance o no (el romance se indica aparte).
## Desde ahí cualquiera puede unirse a tu séquito en las plazas de íntimos (ver RelationsData).
static func intimacy_name(affection: int, _romance: bool, gender: int) -> String:
	var female := gender == CharacterEnums.Gender.FEMENINO
	match intimacy_tier(affection):
		0: return "Desconocida" if female else "Desconocido"
		1: return "Conocida" if female else "Conocido"
		2: return "Amiga" if female else "Amigo"
		3: return "Confidente"
		4: return "Íntima" if female else "Íntimo"
	return ""

static func personality_name(personality: int) -> String:
	return PERSONALITY_NAMES.get(personality, "?")

static func personality_description(personality: int) -> String:
	return PERSONALITY_DESCRIPTIONS.get(personality, "")
