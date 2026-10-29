extends RefCounted
# Catálogo de sucesos sociales (ver SocialEvents): lazos según la intimidad, rivalidades, señores y facción.
# Uso: const SocialEventCatalog = preload("res://scripts/resources/social_event_catalog.gd")
#
# Mismo formato que EventCatalog (id, title, text, options) más:
#   min_tier  — nivel de intimidad mínimo (0 Desconocido … 4 Íntimo; ver DialogueCatalog.intimacy_tier)
#   kinds     — clases de lazo a las que sirve ([] = cualquiera): spouse, lover, friend, courtier, serf, prisoner, retinue
#   stages    — etapas de rivalidad en las que puede ocurrir (Relationship.RivalryStage)
#   deed      — hazaña del jugador a la que reacciona un señor: victoria, deshonra, boda ("" = ninguna)
#   bias      — {Personality: peso} del protagonista
# Marcadores: {name} protagonista, {player}, {lord}, {comrade}, {third}, {castle}; {a:m|f} concuerda con el
# jugador y {s:m|f} con el protagonista. "social" en una opción: efectos que no caben en EventCatalog
# (group: intimidad con toda la facción, adjust: {marcador: n}, schedule_duel, third_grudge) — los aplica SocialEvents.

const P := Character.Personality
const ST := Relationship.RivalryStage

# --- 1) Lazos personales, de menos a más intimidad ---
const BOND := [
	{"id": "soc_pide_ayuda", "title": "Una mano tendida", "min_tier": 1, "kinds": [], "bias": {P.COBARDE: 1.5, P.ROMANTICO: 1.2},
		"text": "{name} llega con la mirada baja: unas deudas de juego le quitan el sueño. No pide mucho, solo que alguien {s:le|la} saque del apuro antes de que sus acreedores pierdan la paciencia.",
		"options": [
			{"label": "Prestarle 30", "requires": {"gold": 30}, "effects": {"gold": -30, "affection": 10, "honor": 2}, "result": "{name} jura que no lo olvidará."},
			{"label": "Negarte", "effects": {"affection": -5}, "result": "{name} se marcha sin decir palabra."},
		]},
	{"id": "soc_rina", "title": "Palabras gruesas", "min_tier": 1, "kinds": [], "bias": {P.ARROGANTE: 2.0, P.CRUEL: 1.5, P.PRUDENTE: 0.5},
		"text": "Una discusión por una minucia se enciende delante de los criados. {name} alza la voz y te reprocha tu orgullo. El salón entero espera tu respuesta.",
		"options": [
			{"label": "Disculparte", "effects": {"affection": 5, "honor": -1}, "result": "La tormenta pasa. {name} acepta tu mano."},
			{"label": "Sostenerle la mirada", "chance": 0.5, "chance_stat": "charisma",
				"success": {"effects": {"affection": 3, "honor": 2}, "result": "{name} acaba riéndose: tenías razón."},
				"failure": {"effects": {"affection": -10}, "result": "La herida tardará en cerrarse."}},
		]},
	{"id": "soc_favor_cortesano", "title": "Una recomendación", "min_tier": 1, "kinds": ["courtier", "friend"], "bias": {P.AMBICIOSO: 2.0},
		"text": "{name} aspira a un cargo en la corte y te pide que hables en su favor. Si sale bien, te deberá el puesto; si sale mal, tu palabra valdrá un poco menos.",
		"options": [
			{"label": "Avalarle", "chance": 0.6, "chance_stat": "charisma",
				"success": {"effects": {"affection": 10, "fame": 2}, "result": "{name} obtiene el cargo y lo pregona con tu nombre."},
				"failure": {"effects": {"affection": 4, "honor": -2}, "result": "Rechazan la petición. {name} agradece el intento."}},
			{"label": "No meterte", "effects": {"affection": -3}, "result": "{name} buscará otro valedor."},
		]},
	{"id": "soc_siervo_tierra", "title": "Un pedazo de tierra", "min_tier": 1, "kinds": ["serf"], "bias": {},
		"text": "{name}, que te sirve sin paga ni libertad, te pide un rincón de huerta para cultivar lo suyo. Promete que nunca descuidará su trabajo.",
		"options": [
			{"label": "Concedérselo", "effects": {"castle_food": -10, "affection": 10, "honor": 2}, "result": "{name} besa la tierra que le das."},
			{"label": "Denegarlo", "effects": {"affection": -6}, "result": "{name} vuelve al trabajo, más callad{s:o|a} que nunca."},
		]},
	{"id": "soc_preso_habla", "title": "Lo que sabe un preso", "min_tier": 1, "kinds": ["prisoner"], "bias": {P.ASTUTO: 1.5},
		"text": "Entre los barrotes, {name} te ofrece lo que sabe de los caminos y las guardias de su antiguo señor. A cambio solo pide mejor pan y una manta.",
		"options": [
			{"label": "Aceptar el trato", "effects": {"gold": -5, "affection": 6, "xp": 15}, "result": "Lo que cuenta {name} vale cada migaja."},
			{"label": "No negociar", "effects": {"affection": -4}, "result": "{name} se encoge en su rincón."},
		]},
	{"id": "soc_regalo", "title": "Un regalo sin motivo", "min_tier": 2, "kinds": [], "bias": {P.GENEROSO: 2.5, P.ROMANTICO: 1.5, P.CRUEL: 0.4},
		"text": "{name} te sorprende con un presente envuelto en paño fino. «No es nada», dice, aunque se nota que lo ha elegido con cuidado.",
		"options": [
			{"label": "Aceptarlo", "effects": {"item": 1, "affection": 3}, "result": "Un regalo digno y un lazo más fuerte."},
			{"label": "Devolver el gesto", "requires": {"gold": 20}, "effects": {"gold": -20, "affection": 8, "honor": 1}, "result": "{name} sonríe: no esperaba nada a cambio."},
		]},
	{"id": "soc_celebracion", "title": "Día de fiesta", "min_tier": 2, "kinds": [], "bias": {P.GENEROSO: 1.5, P.PIADOSO: 1.3},
		"text": "Es el día del santo de {name}, y la gente de la casa espera ver qué haces. Una fiesta cuesta dinero; un olvido cuesta más.",
		"options": [
			{"label": "Dar un banquete", "requires": {"gold": 25}, "effects": {"gold": -25, "affection": 8, "fame": 2}, "result": "Se canta hasta el alba en honor de {name}."},
			{"label": "Un brindis sencillo", "effects": {"affection": 3}, "result": "Basta con el gesto."},
		]},
	{"id": "soc_celos", "title": "Celos", "min_tier": 2, "kinds": ["spouse", "lover"], "bias": {P.ROMANTICO: 2.0, P.ARROGANTE: 1.5, P.LEAL: 1.3},
		"text": "{name} te ha visto reír demasiado con alguien en el banquete. Esa noche no te habla, y al alba te pregunta si aún significa algo para ti.",
		"options": [
			{"label": "Tranquilizarl{s:o|a}", "chance": 0.6, "chance_stat": "charisma",
				"success": {"effects": {"affection": 6}, "result": "{name} se deja convencer, y te abraza."},
				"failure": {"effects": {"affection": -8}, "result": "Tus palabras suenan huecas."}},
			{"label": "Reprochar sus celos", "effects": {"affection": -10, "honor": 1}, "result": "{name} calla, herid{s:o|a}."},
		]},
	{"id": "soc_confidencia", "title": "Una confidencia", "min_tier": 3, "kinds": [], "bias": {P.LEAL: 1.5, P.ASTUTO: 1.2},
		"text": "A solas, {name} te cuenta un secreto que podría arruinar a una familia de la corte. Te lo dice porque confía en ti más que en nadie.",
		"options": [
			{"label": "Guardarlo", "effects": {"affection": 8, "honor": 2}, "result": "El secreto queda entre los dos. {name} no lo olvidará."},
			{"label": "Venderlo", "effects": {"gold": 50, "affection": -15, "honor": -4}, "result": "El oro tintinea; {name} sabrá de dónde salió."},
		]},
	{"id": "soc_consejo_sequito", "title": "Consejo de armas", "min_tier": 3, "kinds": ["retinue", "spouse"], "bias": {P.VALIENTE: 1.5, P.PRUDENTE: 1.5},
		"text": "{name} lleva días observándote entrenar y por fin se atreve: «Bajas la guardia al girar». Propone corregirlo juntos cada mañana.",
		"options": [
			{"label": "Entrenar juntos", "chance": 0.55, "chance_stat": "combat",
				"success": {"effects": {"combat": 1, "affection": 5}, "result": "Al final de la semana ya no bajas la guardia."},
				"failure": {"effects": {"affection": 4, "xp": 10}, "result": "Buenas mañanas, aunque la costumbre es terca."}},
			{"label": "Agradecerlo", "effects": {"affection": 2}, "result": "Quizá en otra ocasión."},
		]},
	{"id": "soc_cuentas", "title": "Las cuentas de la casa", "min_tier": 3, "kinds": ["spouse"], "bias": {P.PRUDENTE: 2.0, P.ASTUTO: 1.5},
		"text": "{name} ha revisado los libros del castillo y ha encontrado a un mayordomo que se queda con lo que no es suyo. Pregunta qué quieres hacer.",
		"options": [
			{"label": "Recuperarlo todo", "effects": {"castle_gold": 40, "affection": 4, "honor": 1}, "result": "El mayordomo devuelve hasta la última moneda."},
			{"label": "Dejarlo en sus manos", "effects": {"castle_gold": 25, "affection": 8}, "result": "{name} lo resuelve con discreción."},
		]},
	{"id": "soc_juramento", "title": "Un juramento", "min_tier": 4, "kinds": ["retinue", "friend", "lover"], "bias": {P.LEAL: 2.5, P.HONORABLE: 1.5},
		"text": "{name} se arrodilla sin que nadie lo pida y jura seguirte hasta donde vayas, en la guerra y en la desgracia. Lo dice ante testigos.",
		"options": [
			{"label": "Aceptarlo", "effects": {"affection": 6, "honor": 3, "fame": 1}, "result": "La corte habla de esa lealtad durante semanas."},
			{"label": "Levantarl{s:o|a}", "effects": {"affection": 4, "honor": 1}, "result": "«Entre nosotros no hacen falta juramentos.»"},
		]},
	{"id": "soc_momento_intimo", "title": "Una noche en vela", "min_tier": 4, "kinds": [], "bias": {P.ROMANTICO: 2.5},
		"text": "La tormenta corta los caminos y os quedáis junto al fuego hasta tarde. {name} te habla de su infancia, de sus miedos y de lo que espera de ti.",
		"options": [
			{"label": "Abrirte también", "effects": {"affection": 10, "xp": 10}, "result": "Al alba, algo ha cambiado entre los dos."},
			{"label": "Escuchar en silencio", "effects": {"affection": 4}, "result": "{name} agradece que la escuches."},
		]},
]

# --- 2) Rivalidades (el protagonista es un rival de duelo) ---
const RIVALRY := [
	{"id": "soc_apuesta", "title": "Una apuesta", "stages": [ST.CONOCIDO, ST.RIVAL, ST.RESPETO], "bias": {P.AMBICIOSO: 1.5, P.ARROGANTE: 1.5},
		"text": "{name} te propone una apuesta delante de la corte: tres flechas al blanco, cincuenta monedas al que acierte más. Los cortesanos ya cruzan sus propias apuestas.",
		"options": [
			{"label": "Apostar 50", "requires": {"gold": 50}, "chance": 0.5, "chance_stat": "combat",
				"success": {"effects": {"gold": 50, "fame": 2, "grudge": 5}, "result": "Tu última flecha parte la de {name}."},
				"failure": {"effects": {"gold": -50, "grudge": -3}, "result": "{name} cobra con una sonrisa."}},
			{"label": "Declinar", "effects": {}, "result": "No todo se resuelve apostando."},
		]},
	{"id": "soc_humillacion", "title": "Humillación pública", "stages": [ST.RIVAL, ST.NEMESIS], "bias": {P.ARROGANTE: 2.0, P.CRUEL: 1.5, P.HONORABLE: 0.4},
		"text": "En pleno banquete, {name} brinda «por {player}, que lucha mejor con la lengua que con la espada». Las risas recorren las mesas.",
		"options": [
			{"label": "Responder con ingenio", "chance": 0.5, "chance_stat": "charisma",
				"success": {"effects": {"honor": 4, "fame": 1, "grudge": 5}, "result": "Tu réplica deja a {name} sin palabras."},
				"failure": {"effects": {"honor": -4}, "result": "Tu réplica muere en un silencio incómodo."}},
			{"label": "Retarl{s:o|a} ahora", "requires": {"healthy": true}, "start_duel": true, "effects": {}, "result": "Te levantas y arrojas el guante."},
			{"label": "Aguantar", "effects": {"honor": -3, "grudge": -3}, "result": "Tragas saliva. Hay quien lo llama templanza."},
		]},
	{"id": "soc_sabotaje", "title": "Un cortejo saboteado", "stages": [ST.RIVAL, ST.NEMESIS], "needs": "beloved", "bias": {P.ASTUTO: 2.0, P.AMBICIOSO: 1.5},
		"text": "{name} ha empezado a rondar a {third} con regalos y mentiras sobre ti. Sabes que no lo hace por amor, sino para quitártelo todo.",
		"options": [
			{"label": "Redoblar el cortejo", "requires": {"gold": 30}, "effects": {"gold": -30, "affection": 8}, "result": "{third} aprecia el gesto y se ríe de los cuentos."},
			{"label": "Retar a {name}", "requires": {"healthy": true}, "start_duel": true, "effects": {}, "result": "Que la espada decida quién miente."},
			{"label": "Dejarlo estar", "effects": {"affection": -8}, "result": "{third} empieza a dudar de ti."},
		]},
	{"id": "soc_duelo_concertado", "title": "Un duelo de honor", "stages": [ST.RIVAL, ST.NEMESIS], "bias": {P.HONORABLE: 2.0, P.VALIENTE: 1.5, P.COBARDE: 0.2},
		"text": "Un heraldo trae el cartel de {name}: te emplaza a un duelo de honor ante testigos, en el palenque y dentro de dos meses. Rechazarlo se sabrá en todo el reino.",
		"options": [
			{"label": "Aceptar la cita", "social": {"schedule_duel": true}, "effects": {"fame": 1}, "result": "Fijas la fecha. La corte ya cuenta los días."},
			{"label": "Rechazar el cartel", "effects": {"honor": -5, "grudge": 5}, "result": "El heraldo se marcha con tu negativa."},
		]},
	{"id": "soc_reconciliacion", "title": "Una tregua", "stages": [ST.RIVAL, ST.RESPETO], "bias": {P.PIADOSO: 2.0, P.GENEROSO: 1.5, P.LEAL: 1.3, P.CRUEL: 0.3},
		"text": "{name} se presenta sin armas y te ofrece la mano. Dice que ya ha habido bastante rencor entre los dos y que el reino necesita a ambos.",
		"options": [
			{"label": "Estrecharla", "effects": {"grudge": -25, "honor": 2}, "result": "La corte respira: la vieja rivalidad se apaga."},
			{"label": "Rechazarla", "effects": {"grudge": 5}, "result": "{name} baja la mano despacio."},
		]},
	{"id": "soc_alianza_rival", "title": "El enemigo de mi enemigo", "stages": [ST.RIVAL, ST.RESPETO, ST.NEMESIS], "needs": "third", "bias": {P.ASTUTO: 1.5, P.AMBICIOSO: 1.5},
		"text": "{name} te propone olvidar vuestras cuentas por un tiempo: {third} os ha ofendido a ambos y juntos podéis bajarle los humos en la corte.",
		"options": [
			{"label": "Unir fuerzas", "social": {"third_grudge": 10}, "effects": {"grudge": -15, "fame": 2}, "result": "{third} pronto nota que tiene dos enemigos."},
			{"label": "Avisar a {third}", "social": {"third_grudge": -10}, "effects": {"grudge": 10, "honor": 2}, "result": "{third} te lo agradece; {name} no."},
		]},
]

# El duelo concertado llega a su fecha.
const DUEL_DAY := {"id": "soc_dia_duelo", "title": "El día del duelo",
	"text": "Ha llegado el día fijado. {name} te espera en el palenque, y la corte entera se ha reunido para ver quién tiene razón.",
	"options": [
		{"label": "Batirte", "requires": {"healthy": true}, "start_duel": true, "effects": {}, "result": "Entras en el palenque."},
		{"label": "No presentarte", "effects": {"honor": -8, "fame": -2, "grudge": 10}, "result": "Tu ausencia dice más que cualquier derrota."},
	]}

# --- 3) Señores: tu señor y los vecinos reaccionan a lo que haces ---
const LORD := [
	{"id": "soc_elogio", "title": "Carta de tu señor", "deed": "victoria", "liege": true,
		"text": "Un mensajero trae una carta sellada de {name}: ha sabido de tu victoria y quiere que todo el reino sepa que sirves bien. Al final añade que espera más.",
		"options": [
			{"label": "Responder con humildad", "effects": {"honor": 2, "affinity": 5}, "result": "{name} guarda tu carta."},
			{"label": "Pedir una recompensa", "chance": 0.5, "chance_stat": "charisma",
				"success": {"effects": {"gold": 60, "affinity": 2}, "result": "{name} envía una bolsa con el siguiente correo."},
				"failure": {"effects": {"affinity": -5}, "result": "{name} no responde."}},
		]},
	{"id": "soc_envidia_vecino", "title": "Un vecino receloso", "deed": "victoria", "liege": false,
		"text": "{name} escribe felicitándote por tu victoria, pero entre líneas se lee el miedo: pregunta qué piensas hacer con tantos hombres armados cerca de sus tierras.",
		"options": [
			{"label": "Tranquilizarl{s:o|a}", "effects": {"affinity": 6}, "result": "{name} duerme más tranquil{s:o|a}."},
			{"label": "Dejarle con la duda", "effects": {"affinity": -4, "fame": 1}, "result": "Que tema. El miedo también es respeto."},
		]},
	{"id": "soc_reproche", "title": "Un reproche", "deed": "deshonra", "liege": true,
		"text": "{name} te escribe con dureza: las historias sobre tu conducta llegan hasta su mesa y manchan su casa. Exige reparación antes de que la vergüenza crezca.",
		"options": [
			{"label": "Pagar una multa", "requires": {"gold": 40}, "effects": {"gold": -40, "affinity": 6, "honor": 2}, "result": "La multa calma a {name}."},
			{"label": "Pedir perdón", "effects": {"affinity": 2, "honor": 1}, "result": "{name} acepta, sin entusiasmo."},
			{"label": "Ignorar la carta", "effects": {"affinity": -10}, "result": "{name} no olvidará el desplante."},
		]},
	{"id": "soc_boda_regalo", "title": "Regalo de bodas", "deed": "boda", "liege": false,
		"text": "Llega un carro con el emblema de {name}: telas, vino y una carta que felicita tu matrimonio. Es cortesía, pero también un mensaje: quiere tenerte de amigo.",
		"options": [
			{"label": "Agradecerlo", "effects": {"gold": 30, "affinity": 6}, "result": "Un vecino amigo vale más que el vino."},
			{"label": "Devolver el presente", "effects": {"honor": 2, "affinity": -6}, "result": "Prefieres no deber nada a nadie."},
		]},
	{"id": "soc_orden", "title": "Órdenes de tu señor", "deed": "", "liege": true,
		"text": "{name} ordena que patrulles los caminos del norte, donde han visto jinetes extraños. No es una petición, aunque la carta sea cortés.",
		"options": [
			{"label": "Obedecer", "effects": {"affinity": 8, "fame": 2, "health": -5}, "result": "Dos semanas de barro, pero el camino queda limpio."},
			{"label": "Excusarte", "effects": {"affinity": -6}, "result": "{name} toma nota de tu excusa."},
		]},
	{"id": "soc_peticion_grano", "title": "Petición de grano", "deed": "", "liege": false,
		"text": "{name} pide ayuda: una plaga ha arruinado sus cosechas y su gente pasa hambre. Ofrece pagar el grano en cuanto pueda, aunque ambos sabéis que tardará.",
		"options": [
			{"label": "Enviar grano", "effects": {"castle_food": -30, "affinity": 10, "honor": 2}, "result": "{name} no olvidará quién le ayudó."},
			{"label": "Negarte", "effects": {"affinity": -5}, "result": "Cada cual cuida de los suyos."},
		]},
	{"id": "soc_visita", "title": "Una visita de alcurnia", "deed": "", "liege": false,
		"text": "{name} se presenta en tu castillo con su séquito, de paso hacia otras tierras. Cómo le recibas se comentará en todas las cortes vecinas.",
		"options": [
			{"label": "Agasajarl{s:o|a}", "requires": {"gold": 30}, "effects": {"gold": -30, "affinity": 10, "fame": 3}, "result": "{name} parte hablando bien de tu casa."},
			{"label": "Recibirl{s:o|a} con sencillez", "effects": {"affinity": 2}, "result": "Una visita correcta, sin más."},
		]},
	{"id": "soc_banquete", "title": "Banquete en la corte", "deed": "", "liege": true,
		"text": "{name} celebra un gran banquete y te sienta cerca de su mesa. Es un honor y una prueba: todos miran quién habla con quién.",
		"options": [
			{"label": "Lucirte", "chance": 0.55, "chance_stat": "charisma",
				"success": {"effects": {"affinity": 8, "fame": 3}, "result": "Tu brindis es el más aplaudido."},
				"failure": {"effects": {"affinity": -2, "honor": -1}, "result": "Un comentario desafortunado enfría la mesa."}},
			{"label": "Mantenerte discret{a:o|a}", "effects": {"affinity": 3}, "result": "Nadie te recuerda, nadie te reprocha."},
		]},
]

# --- 4) Facción: la gente de tu reino como un solo ejército ---
const FACTION := [
	{"id": "soc_brindis", "title": "Brindis tras la victoria", "after_battle": true,
		"text": "Esa noche, quienes lucharon a tu lado alzan las copas. {name} brinda por ti y por los que no volvieron, y el campamento entero responde con un rugido.",
		"options": [
			{"label": "Pagar otra ronda", "requires": {"gold": 10}, "social": {"group": 4}, "effects": {"gold": -10, "affection": 4, "fame": 1}, "result": "La noche es larga y la hermandad, más."},
			{"label": "Brindar por los caídos", "social": {"group": 2}, "effects": {"honor": 2}, "result": "Un silencio solemne, y luego las canciones."},
		]},
	{"id": "soc_camaraderia", "title": "Junto al fuego", "after_battle": false,
		"text": "Los de tu reino comparten fuego y cuentos: viejas batallas, señores tacaños y amores perdidos. {name} te hace sitio en el banco.",
		"options": [
			{"label": "Contar tus hazañas", "social": {"group": 3}, "effects": {"xp": 10}, "result": "Ríen, discuten y beben. Sois uno."},
			{"label": "Retirarte pronto", "effects": {}, "result": "Mañana hay trabajo."},
		]},
	{"id": "soc_rivalidad_interna", "title": "Disputa entre camaradas", "after_battle": false,
		"text": "{name} y {comrade} se disputan el mando de la vanguardia y ya han llegado a las manos. Ambos esperan que les des la razón.",
		"options": [
			{"label": "Apoyar a {name}", "social": {"adjust": {"comrade": -6}}, "effects": {"affection": 6}, "result": "{comrade} acata, de mala gana."},
			{"label": "Mediar", "chance": 0.5, "chance_stat": "charisma",
				"success": {"social": {}, "effects": {"affection": 3, "honor": 2}, "result": "Los dos acaban dándose la mano."},
				"failure": {"effects": {"affection": -3, "honor": -1}, "result": "Ninguno queda content{a:o|a} contigo."}},
		]},
	{"id": "soc_camarada_apuros", "title": "Un camarada en apuros", "after_battle": false,
		"text": "{name} ha caído en manos de un usurero que amenaza con quedarse su caballo y sus armas. Sin ellos no podrá volver a filas. Pide ayuda a quien lucha a su lado.",
		"options": [
			{"label": "Pagar su deuda", "requires": {"gold": 40}, "social": {"group": 2}, "effects": {"gold": -40, "affection": 12, "honor": 3}, "result": "{name} vuelve a filas gracias a ti."},
			{"label": "No es asunto tuyo", "effects": {"affection": -8}, "result": "{name} vende su caballo."},
		]},
	{"id": "soc_honor_grupo", "title": "El señor honra a los suyos", "after_battle": true, "liege": true,
		"text": "{name} reúne a quienes defendieron el reino y nombra a cada uno ante la corte. Cuando llega tu turno, te entrega una copa de plata.",
		"options": [
			{"label": "Aceptar con orgullo", "social": {"group": 2}, "effects": {"fame": 3, "honor": 2, "affinity": 3}, "result": "La copa pasa de mano en mano."},
			{"label": "Cederla a los caídos", "social": {"group": 4}, "effects": {"honor": 4}, "result": "Tus camaradas no lo olvidan."},
		]},
]

## Plantilla rellena: textos con nombres y género, sin claves de catálogo que el mapa no entiende.
static func build(t: Dictionary, speaker: Character, player: Character, names: Dictionary) -> Dictionary:
	var e: Dictionary = _fill(t.duplicate(true), speaker, player, names)
	for k in ["min_tier", "kinds", "stages", "deed", "bias", "liege", "after_battle", "needs"]:
		e.erase(k)
	return e

static func _fill(v: Variant, speaker: Character, player: Character, names: Dictionary) -> Variant:
	if v is String:
		var s: String = v
		for k: String in names:
			s = s.replace("{%s}" % k, str(names[k]))
		return DialogueCatalog._apply_gender(s, speaker, player)
	if v is Array:
		return v.map(func(x: Variant) -> Variant: return _fill(x, speaker, player, names))
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = v[k] if str(k) == "social" else _fill(v[k], speaker, player, names)
		return d
	return v

static func by_id(id: String) -> Dictionary:
	for list in [BOND, RIVALRY, LORD, FACTION]:
		for t: Dictionary in list:
			if t.id == id:
				return t
	return DUEL_DAY if id == DUEL_DAY.id else {}
