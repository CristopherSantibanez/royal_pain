extends RefCounted
# Encuentros en el camino al viajar entre castillos (ver TravelData). Mismo formato que los eventos
# (EventCatalog: options con requires/chance/fight; efectos extra "xp" e "item").
# En los textos: {place} = castillo al que llegas, {kingdom} = reino enemigo de la zona.
# Uso: const RoadEncounterCatalog = preload("res://scripts/resources/road_encounter_catalog.gd")

const R := Character.Role

## when: "any", "war" (solo en zona de guerra), "winter" (solo en invierno). weight: peso al elegir.
const ENCOUNTERS := {
	"salteadores": {"title": "Salteadores de caminos", "when": "any", "weight": 3,
		"text": "A media jornada de {place}, unos salteadores salen de entre los árboles y te cortan el paso. El cabecilla exige tu bolsa.",
		"options": [
			{"label": "Desenvainar y retar al cabecilla", "requires": {"healthy": true}, "effects": {},
				"result": "Desmontas y señalas al cabecilla con la espada.",
				"fight": {"type": "duel", "no_rival": true, "foe": {"name": "El cabecilla", "role": R.SOLDADO, "power": 0, "personality": "CRUEL"},
					"win": {"effects": {"gold": 40, "honor": 3, "fame": 3, "xp": 15}, "result": "El cabecilla huye sangrando y deja atrás lo que había robado a otros viajeros."},
					"lose": {"effects": {"gold": -30, "honor": -2}, "result": "Te dejan en la cuneta con la bolsa vacía."}}},
			{"label": "Pagarles y seguir", "requires": {"gold": 25}, "effects": {"gold": -25, "honor": -2}, "result": "Pagas el peaje de los cobardes y sigues tu camino."},
			{"label": "Espolear al caballo y huir", "chance": 0.55, "chance_stat": "strategy",
				"success": {"effects": {}, "result": "Atajas por un barranco y los dejas atrás."},
				"failure": {"effects": {"health": -15, "gold": -15}, "result": "Te alcanza una pedrada y pierdes parte de tu bolsa en la huida."}},
		]},
	"mercader": {"title": "Un mercader ambulante", "when": "any", "weight": 2,
		"text": "Un mercader con una mula cargada te saluda junto a una fuente. Dice traer piezas de la mejor forja del sur.",
		"options": [
			{"label": "Comprarle una pieza (60 de oro)", "requires": {"gold": 60}, "effects": {"gold": -60, "item": 2}, "result": "Regateas un rato y te llevas una buena pieza."},
			{"label": "Escoltarle hasta {place}", "effects": {"gold": 25, "fame": 1}, "result": "Llegáis juntos y sin percances. El mercader paga bien y habla bien de ti."},
			{"label": "Seguir tu camino", "effects": {}, "result": "Le deseas buena venta y continúas."},
		]},
	"peregrinos": {"title": "Peregrinos", "when": "any", "weight": 2,
		"text": "Una fila de peregrinos camina hacia el santuario más cercano. Una anciana te pide una limosna para el viaje.",
		"options": [
			{"label": "Darles una limosna (10 de oro)", "requires": {"gold": 10}, "effects": {"gold": -10, "honor": 3}, "result": "Los peregrinos rezarán por ti en el santuario."},
			{"label": "Acompañarlos un trecho", "effects": {"honor": 2, "xp": 10}, "result": "Escuchas sus historias de tierras lejanas. El camino se hace corto."},
			{"label": "Pasar de largo", "effects": {}, "result": "Sigues adelante sin detenerte."},
		]},
	"caballero_errante": {"title": "Un caballero errante", "when": "any", "weight": 2,
		"text": "Un caballero errante guarda el puente antes de {place} y reta a todo el que quiera cruzar: «Por el honor de mi dama, nadie pasa sin justar».",
		"options": [
			{"label": "Aceptar el reto", "requires": {"healthy": true}, "effects": {},
				"result": "Aceptas. El caballero baja la visera.",
				"fight": {"type": "duel", "no_rival": true, "foe": {"name": "El caballero errante", "role": R.CABALLERO, "power": 1, "personality": "HONORABLE"},
					"win": {"effects": {"fame": 6, "honor": 4, "gold": 30, "xp": 20}, "result": "El caballero se rinde con elegancia y proclama tu nombre en cada posada."},
					"lose": {"effects": {"honor": -2}, "result": "El caballero te deja pasar por cortesía, pero la historia correrá."}}},
			{"label": "Dar un rodeo por el vado", "effects": {"honor": -2}, "result": "Cruzas con el agua por la cintura mientras el caballero se ríe."},
		]},
	"patrulla": {"title": "Patrulla enemiga", "when": "war", "weight": 4,
		"text": "Una patrulla de {kingdom} vigila el camino de {place}. Te han visto: sus jinetes se abren para rodearte.",
		"options": [
			{"label": "Luchar con tu escolta (escaramuza)", "effects": {},
				"result": "Formas a tu escolta y cargas antes de que cierren el cerco.",
				"fight": {"type": "battle", "no_rival": true, "enemy_name": "La patrulla", "enemy_ratio": 0.8, "garrison_share": 0.1,
					"foe": {"name": "Capitán de la patrulla", "role": R.SOLDADO, "power": 1, "personality": "VALIENTE"},
					"win": {"effects": {"fame": 5, "honor": 3, "gold": 30, "xp": 25}, "result": "La patrulla se dispersa. En sus alforjas hay paga para un mes."},
					"lose": {"effects": {"health": -20, "gold": -25}, "result": "Escapas a duras penas, herido y sin parte del equipaje."}}},
			{"label": "Sobornar al capitán (40 de oro)", "requires": {"gold": 40}, "effects": {"gold": -40, "honor": -3}, "result": "El capitán guarda el oro y mira hacia otro lado."},
			{"label": "Esconderte en el bosque", "chance": 0.5, "chance_stat": "strategy",
				"success": {"effects": {}, "result": "Esperas a que pasen agazapado entre los helechos."},
				"failure": {"effects": {"health": -25}, "result": "Te descubren y huyes bajo una lluvia de flechas."}},
		]},
	"desertores": {"title": "Desertores", "when": "war", "weight": 2,
		"text": "Junto al camino, unos desertores de {kingdom} se calientan en una hoguera. Están hambrientos y desesperados.",
		"options": [
			{"label": "Ofrecerles pan y un puesto en tu guarnición", "requires": {"gold": 20}, "effects": {"gold": -20, "garrison": 6, "honor": 1},
				"result": "Seis hombres juran servirte y parten hacia tu castillo."},
			{"label": "Echarlos del camino", "effects": {"honor": -1}, "result": "Se marchan maldiciendo tu nombre."},
		]},
	"lobos": {"title": "Lobos", "when": "winter", "weight": 3,
		"text": "La nieve cubre el camino. Al anochecer, unos ojos brillan entre los pinos: una manada de lobos hambrientos te sigue.",
		"options": [
			{"label": "Plantarles cara", "chance": 0.6, "chance_stat": "combat",
				"success": {"effects": {"fame": 2, "xp": 10}, "result": "Abates al jefe de la manada y el resto huye aullando."},
				"failure": {"effects": {"health": -25}, "result": "Los ahuyentas, pero no sin mordiscos."}},
			{"label": "Encender una hoguera y aguantar la noche", "effects": {"health": -5}, "result": "No pegas ojo, pero los lobos no se acercan al fuego."},
		]},
	"ventisca": {"title": "Ventisca", "when": "winter", "weight": 2,
		"text": "Una ventisca te sorprende en el paso de montaña. Apenas ves las orejas de tu caballo.",
		"options": [
			{"label": "Refugiarte en una cabaña de pastores", "effects": {"gold": -5}, "result": "Los pastores te dan cobijo a cambio de unas monedas."},
			{"label": "Seguir adelante", "chance": 0.6, "chance_stat": "defense",
				"success": {"effects": {"fame": 1}, "result": "Cruzas el paso a pura voluntad."},
				"failure": {"effects": {"health": -20}, "result": "Llegas a {place} helado y con fiebre."}},
		]},
}

static func encounter_def(id: String) -> Dictionary:
	return ENCOUNTERS.get(id, {})

## Elige un encuentro según el contexto {winter: bool, war: bool}. "" si ninguno encaja.
static func pick(context: Dictionary) -> String:
	var pool: Array[String] = []
	var weights: Array[int] = []
	for id: String in ENCOUNTERS:
		var d: Dictionary = ENCOUNTERS[id]
		match str(d.when):
			"war":
				if not context.get("war", false):
					continue
			"winter":
				if not context.get("winter", false):
					continue
		pool.append(id)
		weights.append(int(d.get("weight", 1)))
	if pool.is_empty():
		return ""
	var total := 0
	for w in weights:
		total += w
	var roll := randi() % total
	for i in pool.size():
		roll -= weights[i]
		if roll < 0:
			return pool[i]
	return pool[-1]

## El encuentro como evento, con sus textos completados ({place}, {kingdom}).
static func as_event(id: String, context: Dictionary) -> Dictionary:
	var d := encounter_def(id)
	if d.is_empty():
		return {}
	var subs := {"place": str(context.get("place", "el camino")), "kingdom": str(context.get("kingdom", ""))}
	var options: Array = []
	for o: Dictionary in d.options:
		var copy := o.duplicate(true)
		copy.label = str(copy.label).format(subs)
		for key in ["result"]:
			if copy.has(key):
				copy[key] = str(copy[key]).format(subs)
		for branch in ["success", "failure"]:
			if copy.has(branch):
				copy[branch].result = str(copy[branch].result).format(subs)
		options.append(copy)
	return {"id": id, "title": d.title, "text": str(d.text).format(subs), "options": options}
