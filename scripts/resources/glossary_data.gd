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
	"Victoria y derrota", "Interfaz y atajos",
]

const DYNAMIC := ["Personalidades", "Habilidades", "Rasgos y desventajas", "Equipamiento"]

const ENTRIES := {
	"Duelo": [
		["Cómo funciona un turno", "Cada turno eliges una postura (opcional, se mantiene) y una acción. Luego actúa tu rival. Quién empieza se decide al azar, con ventaja para quien tiene más Combate."],
		["Daño", "Un golpe hace 24 × A / (A + D), con ±20% de azar. A es tu Combate más la bonificación ofensiva de tu postura (×1,5) y D la Defensa del rival más su bonificación defensiva (×1,5). Con atributos iguales cada golpe quita unos 12 puntos de vida."],
		["Posturas", "Ofensiva: +4 ataque, −1 defensa.\nDefensiva: −1 ataque, +3 defensa.\nEsgrima: +1 ataque y un 15% de esquivar sola cada golpe.\nMuro: −2 ataque, +6 defensa (pero cuesta parar).\nDesesperada: +6 ataque, −3 defensa."],
		["Atacar", "Golpea al rival y gasta 15 de aliento. Puede ser esquivado, parado o amortiguado por la guardia del rival. Un 10% de los golpes son críticos (×1,75)."],
		["Defender", "Recuperas 25 de aliento y el próximo golpe que recibas se reduce a la mitad. Es la forma de recobrar el aliento sin quedar indefenso."],
		["Esquivar", "Recuperas 10 de aliento y tienes un 35% (± diferencia de Combate) de evitar por completo el próximo golpe. Si estás fatigado, la mitad."],
		["Contraatacar (parada)", "Esperas el golpe para pararlo: 55% (± diferencia de Combate) de no recibir nada y devolver un golpe ×1,25. Si falla, recibes el golpe normal. Es la respuesta a un rival que solo ataca."],
		["Empujar", "Rompe la guardia del rival (anula su Defender, Esquivar o parada) y le quita 20 de aliento y algo de moral. Gasta 12 de aliento. Es la respuesta a un rival que se esconde."],
		["Desarmar", "Gasta 15 de aliento. Si sale bien, el rival no puede atacar durante 2 turnos. La probabilidad depende de tu Combate frente a su Defensa."],
		["Aliento y fatiga", "Recuperas 5 de aliento al comienzo de cada turno. Por debajo del 20% estás Fatigado: tu daño baja un 30%, esquivas la mitad y no puedes desarmar ni empujar."],
		["Moral y estados", "Herido (menos del 30% de vida), Fatigado, Desmoralizado (moral baja: −20% daño), Inspirado (moral alta: +20% daño) y Desarmado. Cada golpe recibido baja la moral."],
		["Rendirse y huir", "Rendirse termina el duelo como derrota, pero evitas la herida de caer: pierdes 3 de honor extra y pagas 25 de oro de rescate. Huir puede fallar; si sale bien pierdes 3 de honor."],
		["Personalidad del rival", "Cada rival pelea según su carácter (un arrogante ataca sin pausa, un prudente se cubre y para, un astuto desarma y empuja...) y se adapta: si solo atacas, aprenderá a esperarte con una parada."],
		["Campeones", "Puedes nombrar a un miembro de tu séquito (o un compañero de tu facción) para que luche en tu lugar. Lo controlas tú; sus atributos y habilidades son los suyos."],
		["Heridas", "Quien termina un duelo con poca vida queda herido de gravedad y no podrá batirse durante unos meses. La vida se recupera poco a poco cada mes."],
	],
	"Batalla": [
		["El campo", "Un tablero de 12 × 8 casillas. El atacante despliega a la izquierda y el defensor a la derecha, normalmente tras su muralla."],
		["Tipos de pelotón", "Infantería: fuerte en el cuerpo a cuerpo, se mueve 2 casillas.\nArqueros: atacan a 3 casillas y nadie les responde a distancia, pero sufren en el cuerpo a cuerpo.\nCaballería: se mueve 4 casillas y golpea fuerte a los arqueros."],
		["Terreno", "Llano: sin efecto. Bosque: +25% de defensa. Colina: +20% de defensa y los arqueros alcanzan 1 casilla más. Muralla: +50% de defensa."],
		["Respuesta", "Si atacas cuerpo a cuerpo y el pelotón enemigo sigue en pie, responde con parte de su fuerza (40%). Los arqueros nunca responden."],
		["Moral y huida", "Cada baja baja la moral. Un pelotón con moral por debajo de 25 rompe filas y huye; ver huir a los compañeros desmoraliza al resto del bando."],
		["Fatiga", "Moverse y atacar cansa. Un pelotón que descansa un turno (sin moverse ni atacar) recupera fatiga y algo de moral."],
		["Turnos", "La batalla dura como mucho 12 turnos. Si el atacante no ha tomado el castillo, gana el defensor."],
		["Comandantes y compañeros", "El comandante de cada bando mejora a sus tropas según su Liderazgo y Estrategia, y sus habilidades de batalla. Los compañeros de tu séquito pueden encabezar pelotones."],
		["Bajas previstas", "Al pasar el ratón sobre un objetivo ves las bajas que causarías y las que recibirías en respuesta."],
	],
	"Personaje y roles": [
		["Roles", "Campesino → Soldado → Caballero → Nobleza Baja → Nobleza Alta → Regente. Cada rol tiene sus propias acciones en el castillo y más acciones por mes."],
		["Alistarse (Soldado)", "Pagar 60 de oro por las armas, o demostrar Combate 9."],
		["Caballero", "Requiere 3 duelos ganados y 60 de honor."],
		["Nobleza Baja", "Requiere 75 de honor y 500 de oro."],
		["Nobleza Alta", "Requiere Liderazgo 12 y 2000 de oro. «Ejercer el Mando» y ganar batallas al mando suben el Liderazgo."],
		["Regente", "Requiere honor 80 y heredar la corona por matrimonio con la casa de tu soberano, o controlar 4 castillos de tu reino para usurparla."],
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
		["Equipo", "Cada personaje lleva hasta 2 piezas de equipo que modifican sus atributos."],
	],
	"Economía y castillo": [
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
		["Afinidad", "Lo que un señor piensa de ti (−100 a 100). Sube con presentes (50 de oro) y favores; baja con agresiones. Con los señores se trata por diplomacia."],
		["Intimidad", "Lo cercano que es alguien contigo (0 a 100): Desconocido (0–19), Conocido (20–39), Amigo (40–59), Confidente (60–79) e Íntimo o Amante (80+). Cambia cómo te habla y lo que está dispuesto a hacer por ti."],
		["Conversar", "Trato amistoso: sube la intimidad (6 + Carisma/3, según su carácter). A veces sale mal. Una vez al mes por persona; gasta una acción."],
		["Regalo", "30 de oro: sube la intimidad 12 según su carácter; a algunos (piadosos, prudentes) los regalos caros les sientan mal."],
		["Enfriamiento", "Si pasan más de 2 meses sin trato, la amistad baja 1 al mes y el amor 3 (5 con los leales)."],
		["Tu zona y el pueblo", "La pestaña «Tu zona» reúne a la gente de tu reino: cortesanos, campesinos y soldados. Puedes tratar con todos, no solo con la corte."],
		["Perfiles", "Pulsa el retrato de cualquier personaje conocido para ver su ficha: carácter, atributos, habilidades, rasgos, equipo y vuestra relación. Puedes guardarlo en el editor de personajes."],
		["Retar a duelo", "Puedes retar a quien esté en tu zona. Los campesinos no se baten; quien te supera en 2 rangos o más solo acepta si tienes 20 de fama por rango de diferencia; quien te teme (4+ puntos de combate y defensa por debajo) puede negarse, salvo los arrogantes. Ganar da fama: 3, más 3 por cada rango que te supere el rival."],
	],
	"Rivalidad": [
		["Rencor", "Cada duelo deja huella: vencer a alguien aumenta su rencor (más si es arrogante o ambicioso); perder lo calma."],
		["Etapas", "Conocido → Rival (40 de rencor) → Némesis (70). Los leales y piadosos vencidos dos veces pueden acabar respetándote."],
		["Iniciativas", "Los rivales te retan en público, difunden rumores, roban (los astutos) o reaccionan a tus victorias. Rechazar un reto cuesta honor."],
		["Revanchas", "Vencer de nuevo a un rival da honor extra: +3 (conocido), +6 (rival), +10 (némesis)."],
	],
	"Romance y matrimonio": [
		["Romance", "Solo entre un hombre y una mujer, y nace de la confianza: el «Gesto íntimo» solo se puede intentar con 40 de intimidad. Si sale bien, la relación pasa a ser amorosa; si no, se enfría (−8)."],
		["Pretendientes rivales", "Otra persona puede cortejar a quien amas. Puedes retarla a duelo, superarla en regalos o dejarlo estar."],
		["Boda por amor", "Con un romance y 80 de intimidad puedes pedir la mano (50 de oro). Si te precipitas, puede decir que aún no."],
		["Matrimonio político", "Con un señor amistoso (60 de afinidad, Caballero o más) puedes casarte con alguien de su casa: su familia se vuelve aliada. Como Caballero, tu señor también puede ofrecértelo."],
		["Cónyuge", "Tu cónyuge tiene ficha y carácter propios y te propondrá asuntos cada cierto tiempo."],
		["Sucesión", "Casarte con la casa de tu soberano te pone en la línea de sucesión al trono."],
	],
	"Séquito y compañeros": [
		["Séquito", "Personajes que te siguen por lealtad: Soldado 1 plaza, Caballero 2, Nobleza Baja 3, Nobleza Alta 4, Regente 5. Piden 50 de intimidad y la fama y el honor que exige su rango (un caballero, 15 de fama y 40 de honor; un noble, 35 y 60). Cada uno cobra 5 de oro al mes: si no le pagas, se aleja y puede marcharse."],
		["En batalla", "Los miembros del séquito encabezan pelotones y los mejoran con sus atributos y habilidades. Si su pelotón huye, pueden salir heridos."],
		["Compañeros de facción", "Si no tienes séquito, tu señor te presta a los mejores combatientes de tu reino. Son menos leales (menos moral) y no te presta a nadie si tu afinidad con él es muy baja."],
		["Campeones", "En los duelos de campaña (no en torneos) puedes elegir a un miembro sano del séquito para que luche por ti y controlarlo tú. Si vence, ganas 3 de honor y 2 de fama; si cae, pierdes 2 de honor, y las heridas son suyas."],
	],
	"Encargos": [
		["Encargos", "Según tu rol recibirás tareas (de tu señor, del pueblo o de tu reino) con un plazo en meses. Cumplirlas a tiempo da recompensas; fallarlas tiene consecuencias."],
		["Duelos de exhibición", "Como Caballero pueden asignarte duelos de exhibición contra caballeros de otros reinos."],
	],
	"Eventos y noticias": [
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
	"Victoria y derrota": [
		["Tu destino", "La meta depende del rol con el que empiezas: Campesino (llegar a Nobleza Baja), Soldado (ser Caballero y ganar duelos), Caballero (conquistar y llegar a Nobleza Baja), Nobleza Baja (gobernar castillos y llegar a Nobleza Alta), Nobleza Alta (la Corona)."],
		["Derrota", "Pierdes si te quedas sin castillos o si tu honor llega a 0."],
		["Seguir jugando", "Al cumplir tu destino puedes seguir jugando la misma partida."],
	],
	"Interfaz y atajos": [
		["Duelo", "Teclas 1–8: acciones. Q, W, E, R, T: posturas. Pasa el ratón sobre una orden para ver su efecto y sus probabilidades."],
		["Mapa", "Rueda del ratón: zoom. Botón derecho: arrastrar. Clic en un castillo o ejército para ver sus datos."],
		["Opciones", "Volumen por separado de música, ambiente y efectos, y pantalla completa."],
		["Guardado", "La partida se guarda sola cada mes (autoguardado) y puedes usar tres ranuras manuales."],
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
