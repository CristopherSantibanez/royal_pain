extends RefCounted
# Catálogo de contenido: habilidades, ventajas, desventajas y equipo, como datos.
# GameData construye los recursos a partir de aquí y SkillEffects suma sus efectos por nombre
# (así también funcionan los personajes guardados antes de que existieran los efectos).
#
# Cada entrada: {name, desc, mods: {stat: n}, fx: {efecto: valor}}; el equipo añade slot, tier y price.
# Efectos (fx) disponibles — se suman entre todas las fuentes del personaje:
#   Duelo:    dmg, dmg_taken, crit, crit_mult, parry, dodge, guard, stamina_cost, stamina_regen,
#             morale_resist, disarm, push, low_hp_dmg, riposte, initiative, intimidate
#   Batalla:  unit_power, inf_power, arch_power, cav_power, cav_move, arch_range, morale_start,
#             morale_loss, terrain_def, retaliation, rally, wall_assault, fatigue, loyalty
#   Mundo:    income, recruit, upkeep, social, gift, event_luck, fame_gain, honor_gain, heal,
#             wound_resist, vision
#   Ficha:    max_health (se aplica al crear el personaje)
# Las habilidades con lógica propia (Paso Invernal, Viajero, Desarme Fulminante...) se tratan por nombre en SkillEffects.

const SLOT_ARMA := "Arma"
const SLOT_ARMADURA := "Armadura"
const SLOT_ESCUDO := "Escudo"
const SLOT_MONTURA := "Montura"
const SLOT_ACCESORIO := "Accesorio"
const SLOTS := [SLOT_ARMA, SLOT_ARMADURA, SLOT_ESCUDO, SLOT_MONTURA, SLOT_ACCESORIO]

const GENERAL_SKILLS := [
	{"name": "Paso Invernal", "desc": "Tus ejércitos marchan en 1 turno también en invierno (dic–feb), cuando los demás tardan 2.", "fx": {}},
	{"name": "Reclutador Nato", "desc": "La milicia cuesta un tercio menos y suma un 50% más de soldados; movilizas un 10% más de la guarnición.", "fx": {"recruit": -0.15}},
	{"name": "Administrador", "desc": "+25% de oro en impuestos, gobierno, impuestos reales y el edicto de impuestos.", "fx": {}},
	{"name": "Viajero", "desc": "Tus ejércitos pueden marchar a castillos a 2 saltos de distancia en un solo turno.", "fx": {}},
	{"name": "Diplomático Nato", "desc": "Tus conversaciones y regalos causan un 25% más de efecto.", "fx": {"social": 0.25, "gift": 0.2}},
	{"name": "Mecenas", "desc": "Patrocinas juglares que cantan tus hazañas: +30% de fama ganada.", "fx": {"fame_gain": 0.3}},
	{"name": "Intendente", "desc": "Tus castillos gastan un 25% menos en pagar y alimentar a la tropa.", "fx": {"upkeep": -0.25}},
	{"name": "Red de Espías", "desc": "Ves un castillo más lejos en el mapa.", "fx": {"vision": 1}},
	{"name": "Curandero", "desc": "Recuperas 15 de vida más cada mes y tus heridas graves duran un mes menos.", "fx": {"heal": 15, "wound_resist": 1}},
	{"name": "Mercader Astuto", "desc": "+15% de oro en tus ingresos y un 10% de descuento al contratar tropas.", "fx": {"income": 0.15, "recruit": -0.1}},
	{"name": "Orador", "desc": "Tu palabra convence: +20% de efecto al conversar y +20% de honor ganado.", "fx": {"social": 0.2, "honor_gain": 0.2}},
	{"name": "Cazador", "desc": "Conoces los bosques: +5% de éxito en los eventos con riesgo.", "fx": {"event_luck": 0.05}},
	{"name": "Juglar de Corte", "desc": "Cantas y recitas en la corte: +20% de fama y +10% de efecto social.", "fx": {"fame_gain": 0.2, "social": 0.1}},
	{"name": "Devoto", "desc": "Tu piedad es conocida: +30% de honor ganado.", "fx": {"honor_gain": 0.3}},
	{"name": "Afortunado", "desc": "La suerte te sonríe: +10% de éxito en los eventos con riesgo.", "fx": {"event_luck": 0.1}},
	{"name": "Recaudador Implacable", "desc": "+25% de oro en tus ingresos, pero el pueblo te aprecia menos (−20% de honor ganado).", "fx": {"income": 0.25, "honor_gain": -0.2}},
]

const COMBAT_SKILLS := [
	{"name": "Desarme Fulminante", "desc": "Al desarmar al enemigo, aprovechas para golpearlo de inmediato (turno extra).", "fx": {}},
	{"name": "Piel de Hierro", "desc": "Recibes un 30% menos de daño mientras estás herido (vida bajo el 30%).", "fx": {}},
	{"name": "Golpe Certero", "desc": "20% de probabilidad de golpe crítico, frente al 10% normal.", "fx": {}},
	{"name": "Maestro de Parada", "desc": "+12% de probabilidad de parar un golpe con Contraatacar.", "fx": {"parry": 0.12}},
	{"name": "Danza de Espadas", "desc": "+10% de probabilidad de esquivar.", "fx": {"dodge": 0.1}},
	{"name": "Fuerza Bruta", "desc": "Tus golpes causan un 12% más de daño.", "fx": {"dmg": 0.12}},
	{"name": "Resistencia", "desc": "Tus acciones gastan un 25% menos de aliento.", "fx": {"stamina_cost": -0.25}},
	{"name": "Segundo Aliento", "desc": "Recuperas 5 de aliento más al comienzo de cada turno.", "fx": {"stamina_regen": 5}},
	{"name": "Furia del Herido", "desc": "Con la vida bajo el 30%, causas un 35% más de daño.", "fx": {"low_hp_dmg": 0.35}},
	{"name": "Contragolpe Letal", "desc": "Tus respuestas tras una parada hacen un 35% más de daño.", "fx": {"riposte": 0.35}},
	{"name": "Ojo de Halcón", "desc": "+6% de crítico y los críticos hacen ×0,25 más de daño.", "fx": {"crit": 0.06, "crit_mult": 0.25}},
	{"name": "Guardia Férrea", "desc": "Defender reduce todavía más el próximo golpe (÷2,5 en vez de ÷2).", "fx": {"guard": 0.5}},
	{"name": "Zancadilla", "desc": "+15% de probabilidad de éxito al empujar.", "fx": {"push": 0.15}},
	{"name": "Mano Rápida", "desc": "+12% de probabilidad de desarmar.", "fx": {"disarm": 0.12}},
	{"name": "Iniciativa", "desc": "+15% de probabilidad de atacar primero.", "fx": {"initiative": 0.15}},
	{"name": "Temple", "desc": "Los golpes apenas te desmoralizan (−50% de moral perdida).", "fx": {"morale_resist": 0.5}},
	{"name": "Intimidación", "desc": "Tu rival empieza el duelo con 15 de moral menos.", "fx": {"intimidate": 15}},
]

const BATTLE_SKILLS := [
	{"name": "Grito de Guerra", "desc": "Tus pelotones empiezan la batalla con +5 de moral.", "fx": {}},
	{"name": "Táctica Defensiva", "desc": "Tus pelotones en colina o muralla reciben un 30% menos de daño.", "fx": {}},
	{"name": "Carga Letal", "desc": "Tu caballería causa un 40% más de daño y, si carga 2 casillas o más, no recibe respuesta.", "fx": {}},
	{"name": "Lluvia de Flechas", "desc": "Tus arqueros causan un 25% más de bajas.", "fx": {"arch_power": 0.25}},
	{"name": "Muro de Escudos", "desc": "Tu infantería causa un 15% más de bajas y responde con más fuerza.", "fx": {"inf_power": 0.15, "retaliation": 0.15}},
	{"name": "Jinete Experto", "desc": "Tu caballería avanza una casilla más.", "fx": {"cav_move": 1}},
	{"name": "Arqueros de Élite", "desc": "Tus arqueros disparan una casilla más lejos.", "fx": {"arch_range": 1}},
	{"name": "Disciplina de Hierro", "desc": "Tus tropas pierden un 30% menos de moral.", "fx": {"morale_loss": -0.3}},
	{"name": "Reagrupar", "desc": "Tus pelotones que descansan recuperan 6 de moral más.", "fx": {"rally": 6}},
	{"name": "Maestro de Asedio", "desc": "+30% de bajas contra pelotones sobre la muralla.", "fx": {"wall_assault": 0.3}},
	{"name": "Emboscada", "desc": "Tus pelotones en bosque, colina o muralla reciben un 15% menos de daño.", "fx": {"terrain_def": 0.15}},
	{"name": "Logística", "desc": "Tus tropas se cansan un 30% menos.", "fx": {"fatigue": -0.3}},
	{"name": "Represalia", "desc": "Tus pelotones responden a los ataques con un 30% más de fuerza.", "fx": {"retaliation": 0.3}},
	{"name": "Estandarte Sagrado", "desc": "Tus pelotones empiezan la batalla con +8 de moral.", "fx": {"morale_start": 8}},
	{"name": "Ataque Coordinado", "desc": "Todas tus tropas causan un 8% más de bajas.", "fx": {"unit_power": 0.08}},
]

const ADVANTAGES := [
	{"name": "Sangre Noble", "desc": "Naciste con ventaja social.", "mods": {"charisma": 2}},
	{"name": "Veterano de Guerra", "desc": "Años de batalla te curtieron.", "mods": {"combat": 2}},
	{"name": "Mente Fría", "desc": "Piensas con claridad bajo presión.", "mods": {"strategy": 2}},
	{"name": "Presencia Imponente", "desc": "Inspiras respeto al instante.", "mods": {"leadership": 2}},
	{"name": "Reflejos de Acero", "desc": "Reaccionas antes que la mayoría.", "mods": {"defense": 2}},
	{"name": "Robusto", "desc": "Tu cuerpo aguanta lo que otros no: +20 de vida máxima.", "fx": {"max_health": 20}},
	{"name": "Incansable", "desc": "Recuperas 3 de aliento más cada turno de duelo.", "fx": {"stamina_regen": 3}},
	{"name": "Mano Firme", "desc": "+3% de golpe crítico.", "fx": {"crit": 0.03}},
	{"name": "Buena Estrella", "desc": "+5% de éxito en los eventos con riesgo.", "fx": {"event_luck": 0.05}},
	{"name": "Don de Gentes", "desc": "Caes bien a todo el mundo.", "mods": {"charisma": 1}, "fx": {"social": 0.15}},
	{"name": "Erudito", "desc": "Has leído a los clásicos de la guerra.", "mods": {"strategy": 1}, "fx": {"fame_gain": 0.1}},
	{"name": "Sanador Natural", "desc": "Te curas rápido: +10 de vida cada mes.", "fx": {"heal": 10}},
	{"name": "Ambidiestro", "desc": "+5% de parada y +3% de esquiva.", "fx": {"parry": 0.05, "dodge": 0.03}},
	{"name": "Comerciante Nato", "desc": "+10% de oro en tus ingresos.", "fx": {"income": 0.1}},
	{"name": "Querido por el Pueblo", "desc": "+15% de honor ganado y tropas un 10% más baratas.", "fx": {"honor_gain": 0.15, "recruit": -0.1}},
	{"name": "Instinto de Supervivencia", "desc": "Recibes un 8% menos de daño en duelo.", "fx": {"dmg_taken": -0.08}},
	{"name": "Jinete Nato", "desc": "Tu caballería causa un 10% más de bajas.", "fx": {"cav_power": 0.1}},
	{"name": "Ojo Certero", "desc": "Tus arqueros causan un 10% más de bajas.", "fx": {"arch_power": 0.1}},
	{"name": "Voluntad de Hierro", "desc": "Te desmoralizas menos en duelo y tus tropas pierden menos moral.", "fx": {"morale_resist": 0.3, "morale_loss": -0.1}},
	{"name": "Fama Precoz", "desc": "Tu nombre ya suena en las tabernas: +20% de fama ganada.", "fx": {"fame_gain": 0.2}},
	{"name": "Lealtad Inquebrantable", "desc": "Tus compañeros de séquito luchan con +10 de moral.", "fx": {"loyalty": 10}},
	{"name": "Belleza Legendaria", "desc": "Tu aspecto abre puertas y corazones.", "mods": {"charisma": 1}, "fx": {"social": 0.25}},
]

const DISADVANTAGES := [
	{"name": "Temperamento Volátil", "desc": "Te cuesta controlar la ira.", "mods": {"charisma": -2}},
	{"name": "Cuerpo Frágil", "desc": "Más vulnerable en combate.", "mods": {"defense": -2}},
	{"name": "Ingenuo", "desc": "Fácil de engañar en negociaciones.", "mods": {"strategy": -2}},
	{"name": "Mal Líder", "desc": "Cuesta que tus tropas te sigan con convicción.", "mods": {"leadership": -2}},
	{"name": "Torpe en Combate", "desc": "Menos preciso al luchar.", "mods": {"combat": -2}},
	{"name": "Viejas Heridas", "desc": "Cicatrices que no terminan de cerrar: −15 de vida máxima.", "fx": {"max_health": -15}},
	{"name": "Pulmones Débiles", "desc": "Recuperas 3 de aliento menos cada turno de duelo.", "fx": {"stamina_regen": -3}},
	{"name": "Pusilánime", "desc": "Los golpes te desmoralizan más, aunque esquivas por instinto.", "fx": {"morale_resist": -0.3, "dodge": 0.03}},
	{"name": "Codicioso", "desc": "El oro te pierde: −20% de honor ganado, +5% de ingresos.", "fx": {"honor_gain": -0.2, "income": 0.05}},
	{"name": "Mala Fama", "desc": "Las malas lenguas te persiguen: −30% de fama ganada.", "fx": {"fame_gain": -0.3}},
	{"name": "Enfermizo", "desc": "Te curas despacio: −10 de vida recuperada cada mes.", "fx": {"heal": -10}},
	{"name": "Impetuoso", "desc": "Golpeas con fuerza (+5%) pero paras peor (−8%).", "fx": {"dmg": 0.05, "parry": -0.08}},
	{"name": "Lento", "desc": "−6% de esquiva y −15% de iniciativa.", "fx": {"dodge": -0.06, "initiative": -0.15}},
	{"name": "Supersticioso", "desc": "Los presagios te paralizan: −5% de éxito en eventos con riesgo.", "fx": {"event_luck": -0.05}},
	{"name": "Soberbia", "desc": "Tu arrogancia aleja a la gente: −15% de efecto social.", "fx": {"social": -0.15}},
	{"name": "Derrochador", "desc": "El oro se te escapa entre los dedos: −15% de ingresos.", "fx": {"income": -0.15}},
	{"name": "Enemigos Poderosos", "desc": "Alguien poderoso conspira contra ti: −10% de efecto social.", "fx": {"social": -0.1}},
	{"name": "Miope", "desc": "Ves mal de lejos: tus arqueros pierden un 15% de eficacia y tu crítico baja.", "fx": {"arch_power": -0.15, "crit": -0.02}},
	{"name": "Mal Jinete", "desc": "Te mareas a caballo: tu caballería pierde un 15% de eficacia.", "fx": {"cav_power": -0.15}},
	{"name": "Rencoroso", "desc": "No olvidas una ofensa: −10% de efecto social y de honor ganado.", "fx": {"social": -0.1, "honor_gain": -0.1}},
	{"name": "Cicatriz Visible", "desc": "Una cicatriz que asusta tanto como afea.", "mods": {"charisma": -1}, "fx": {"intimidate": 5}},
	{"name": "Insomne", "desc": "Duermes mal: tus acciones de duelo gastan un 15% más de aliento.", "fx": {"stamina_cost": 0.15}},
]

const EQUIPMENT := [
	# Armas
	{"name": "Espada Corta", "slot": SLOT_ARMA, "tier": 1, "price": 40, "desc": "Sencilla y fiable.", "mods": {"combat": 1}},
	{"name": "Espada Larga", "slot": SLOT_ARMA, "tier": 2, "price": 120, "desc": "Arma equilibrada, favorece el ataque.", "mods": {"combat": 3}},
	{"name": "Mandoble", "slot": SLOT_ARMA, "tier": 3, "price": 300, "desc": "Golpes devastadores (+10% de daño) que cansan (+15% de aliento).", "mods": {"combat": 4}, "fx": {"dmg": 0.1, "stamina_cost": 0.15}},
	{"name": "Hacha de Guerra", "slot": SLOT_ARMA, "tier": 2, "price": 150, "desc": "Abre escudos y cráneos: +5% de crítico.", "mods": {"combat": 2}, "fx": {"crit": 0.05}},
	{"name": "Lanza", "slot": SLOT_ARMA, "tier": 1, "price": 50, "desc": "Mantiene al rival a distancia: +10% de iniciativa.", "mods": {"combat": 1}, "fx": {"initiative": 0.1, "cav_power": 0.05}},
	{"name": "Estoque", "slot": SLOT_ARMA, "tier": 2, "price": 160, "desc": "Hoja de esgrimista: respuestas un 20% más letales.", "mods": {"combat": 2}, "fx": {"riposte": 0.2}},
	{"name": "Maza de Armas", "slot": SLOT_ARMA, "tier": 2, "price": 130, "desc": "Derriba guardias: +10% al empujar.", "mods": {"combat": 2}, "fx": {"push": 0.1}},
	{"name": "Arco Largo", "slot": SLOT_ARMA, "tier": 2, "price": 140, "desc": "Para quien manda arqueros: +10% de bajas a distancia.", "mods": {"strategy": 1}, "fx": {"arch_power": 0.1}},
	{"name": "Daga de Misericordia", "slot": SLOT_ARMA, "tier": 1, "price": 35, "desc": "Busca el hueco de la armadura: +4% de crítico.", "fx": {"crit": 0.04}},
	# Armaduras
	{"name": "Gambesón", "slot": SLOT_ARMADURA, "tier": 1, "price": 40, "desc": "Acolchado de tela, ligero.", "mods": {"defense": 1}},
	{"name": "Cuero Endurecido", "slot": SLOT_ARMADURA, "tier": 1, "price": 60, "desc": "Protege sin estorbar: +3% de esquiva.", "mods": {"defense": 1}, "fx": {"dodge": 0.03}},
	{"name": "Cota de Malla", "slot": SLOT_ARMADURA, "tier": 2, "price": 150, "desc": "La protección del caballero.", "mods": {"defense": 2}},
	{"name": "Brigantina", "slot": SLOT_ARMADURA, "tier": 2, "price": 170, "desc": "Placas cosidas en tela: +2% de esquiva.", "mods": {"defense": 2}, "fx": {"dodge": 0.02}},
	{"name": "Armadura Completa", "slot": SLOT_ARMADURA, "tier": 3, "price": 320, "desc": "Protección superior a costa de aliento (+10% de gasto).", "mods": {"defense": 3}, "fx": {"stamina_cost": 0.1, "dmg_taken": -0.05}},
	# Escudos
	{"name": "Rodela", "slot": SLOT_ESCUDO, "tier": 1, "price": 30, "desc": "Escudo pequeño para desviar golpes: +5% de parada.", "fx": {"parry": 0.05}},
	{"name": "Escudo de Cometa", "slot": SLOT_ESCUDO, "tier": 2, "price": 90, "desc": "Cubre medio cuerpo: Defender protege más.", "mods": {"defense": 1}, "fx": {"guard": 0.3}},
	{"name": "Pavés", "slot": SLOT_ESCUDO, "tier": 3, "price": 160, "desc": "Una muralla portátil: guardia muy fuerte, esquiva peor.", "mods": {"defense": 2}, "fx": {"guard": 0.6, "dodge": -0.05}},
	# Monturas
	{"name": "Rocín", "slot": SLOT_MONTURA, "tier": 1, "price": 60, "desc": "Un caballo de trabajo: +5% a tu caballería.", "fx": {"cav_power": 0.05}},
	{"name": "Corcel de Guerra", "slot": SLOT_MONTURA, "tier": 2, "price": 250, "desc": "Rápido y valiente: +15% a tu caballería, +5% de iniciativa.", "fx": {"cav_power": 0.15, "initiative": 0.05}},
	{"name": "Destrero", "slot": SLOT_MONTURA, "tier": 3, "price": 500, "desc": "El caballo de los grandes señores: +25% a tu caballería y +3 de moral a tus tropas.", "mods": {"leadership": 1}, "fx": {"cav_power": 0.25, "morale_start": 3}},
	# Accesorios
	{"name": "Sello Familiar", "slot": SLOT_ACCESORIO, "tier": 2, "price": 150, "desc": "Un símbolo de linaje que abre puertas.", "mods": {"charisma": 2, "leadership": 1}},
	{"name": "Mapa Táctico", "slot": SLOT_ACCESORIO, "tier": 2, "price": 120, "desc": "Herramienta de planificación militar.", "mods": {"strategy": 3}},
	{"name": "Capa de Viajero", "slot": SLOT_ACCESORIO, "tier": 1, "price": 50, "desc": "Ligera, favorece la agilidad en duelo.", "mods": {"defense": 1, "combat": 1}},
	{"name": "Amuleto de la Suerte", "slot": SLOT_ACCESORIO, "tier": 1, "price": 50, "desc": "+5% de éxito en los eventos con riesgo.", "fx": {"event_luck": 0.05}},
	{"name": "Estandarte Familiar", "slot": SLOT_ACCESORIO, "tier": 2, "price": 120, "desc": "Tus tropas empiezan con +5 de moral.", "mods": {"leadership": 1}, "fx": {"morale_start": 5}},
	{"name": "Anillo de Oro", "slot": SLOT_ACCESORIO, "tier": 3, "price": 300, "desc": "Riqueza a la vista: +10% de efecto social.", "mods": {"charisma": 2}, "fx": {"social": 0.1}},
	{"name": "Cuerno de Guerra", "slot": SLOT_ACCESORIO, "tier": 1, "price": 80, "desc": "Reúne a los que flaquean: +4 de moral al descansar.", "fx": {"rally": 4}},
	{"name": "Reliquia Sagrada", "slot": SLOT_ACCESORIO, "tier": 3, "price": 200, "desc": "+10% de honor ganado y más templanza en duelo.", "fx": {"honor_gain": 0.1, "morale_resist": 0.2}},
	{"name": "Libro de Tácticas", "slot": SLOT_ACCESORIO, "tier": 2, "price": 150, "desc": "Las enseñanzas de los grandes generales.", "mods": {"strategy": 2}},
	{"name": "Bolsa de Hierbas", "slot": SLOT_ACCESORIO, "tier": 1, "price": 40, "desc": "Ungüentos y vendas: +8 de vida al mes.", "fx": {"heal": 8}},
]

# Calidad del equipo inicial de los PNJ según su rango: niveles permitidos y piezas.
const NPC_EQUIPMENT_BY_ROLE := {
	0: {"tiers": [1], "pieces": [0, 1]},          # Campesino
	1: {"tiers": [1], "pieces": [1, 2]},          # Soldado
	2: {"tiers": [1, 2], "pieces": [2, 3]},       # Caballero
	3: {"tiers": [1, 2, 3], "pieces": [2, 3]},    # Nobleza Baja
	4: {"tiers": [2, 3], "pieces": [3, 4]},       # Nobleza Alta
	5: {"tiers": [2, 3], "pieces": [3, 5]},       # Regente
}
