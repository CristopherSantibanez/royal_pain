extends RefCounted
# Lugares del mapa para explorar: aparecen cerca de un castillo, duran unos meses y desaparecen.
# Visitar uno gasta una acción y plantea una decisión con el mismo formato que los eventos
# (ver EventCatalog: options con requires/chance/fight; efectos extra "xp", "item" = calidad 1..3
# y "unique" = % de probabilidad de una pieza única).
# Uso: const SiteCatalog = preload("res://scripts/resources/site_catalog.gd")

const R := Character.Role

const SITES := {
	"ruinas": {"name": "Ruinas antiguas", "color": "b9a37a", "months": [3, 5],
		"text": "Entre zarzas asoman los muros de una fortaleza olvidada. Los pastores dicen que de noche se ven luces en la torre.",
		"options": [
			{"label": "Registrar las ruinas con cuidado", "chance": 0.6, "chance_stat": "strategy",
				"success": {"effects": {"gold": 70, "item": 2, "unique": 8}, "result": "Bajo una losa suelta encuentras un cofre olvidado."},
				"failure": {"effects": {"health": -15}, "result": "Un muro cede y sales magullado y con las manos vacías."}},
		]},
	"campamento_bandido": {"name": "Campamento bandido", "color": "a84a3a", "months": [2, 4],
		"text": "Humo entre los árboles: una banda de forajidos ha levantado su campamento junto al camino real y cobra peaje a quien pasa.",
		"options": [
			{"label": "Asaltar el campamento con tus hombres (escaramuza)", "requires": {"garrison": 25}, "effects": {},
				"result": "Reúnes a una partida de la guarnición y caéis sobre el campamento al alba.",
				"fight": {"type": "battle", "no_rival": true, "enemy_name": "Los forajidos", "enemy_ratio": 0.9, "garrison_share": 0.2,
					"foe": {"name": "Jefe de los forajidos", "role": R.SOLDADO, "power": 0, "personality": "CRUEL"},
					"win": {"effects": {"gold": 90, "honor": 5, "fame": 6, "xp": 20}, "result": "El campamento arde y el camino vuelve a ser seguro. Su botín es tuyo."},
					"lose": {"effects": {"honor": -3}, "result": "Los forajidos os rechazan y se burlan desde la empalizada."}}},
			{"label": "Retar al jefe en duelo singular", "requires": {"healthy": true}, "effects": {},
				"result": "Entras solo en el campamento y exiges ver al jefe.",
				"fight": {"type": "duel", "no_rival": true, "foe": {"name": "Jefe de los forajidos", "role": R.SOLDADO, "power": 0, "personality": "CRUEL"},
					"win": {"effects": {"gold": 60, "honor": 6, "fame": 5, "unique": 5}, "result": "El jefe cae y su banda se dispersa por los montes."},
					"lose": {"effects": {"honor": -3, "gold": -20}, "result": "Te arrojan al barro del camino con la bolsa más ligera."}}},
			{"label": "Pagar el peaje y seguir", "requires": {"gold": 20}, "effects": {"gold": -20, "honor": -2}, "result": "Pagas. Los bandidos ríen a tu espalda."},
		]},
	"cueva": {"name": "Cueva del lobo", "color": "6f6a62", "months": [3, 6],
		"text": "Una cueva honda en la ladera. Los aldeanos juran que una bestia se lleva el ganado, y que dentro guarda los huesos de quienes fueron a cazarla.",
		"options": [
			{"label": "Entrar con antorcha y espada", "requires": {"healthy": true}, "chance": 0.55, "chance_stat": "combat",
				"success": {"effects": {"fame": 8, "honor": 4, "item": 1, "gold": 30, "unique": 6}, "result": "Abates a la bestia. Entre los huesos brilla el equipo de un cazador desafortunado."},
				"failure": {"effects": {"health": -30, "honor": 1}, "result": "La bestia te hiere y huyes a la luz. Al menos lo intentaste."}},
			{"label": "Tapiar la entrada", "effects": {"honor": 1}, "result": "Los aldeanos te agradecen el gesto, aunque nadie duerme tranquilo."},
		]},
	"monasterio": {"name": "Monasterio en el monte", "color": "d8cfae", "months": [4, 6],
		"text": "Unos monjes han abierto su hospedería en lo alto del monte. Ofrecen pan, cura y consejo a quien sube la cuesta.",
		"options": [
			{"label": "Descansar y orar con los monjes", "effects": {"health": 40, "honor": 3}, "result": "Sales del monasterio con el cuerpo y el alma en paz."},
			{"label": "Estudiar sus crónicas de guerra", "effects": {"strategy": 1}, "result": "Los viejos pergaminos guardan lecciones que ningún maestro te dio."},
			{"label": "Donar a la hospedería", "requires": {"gold": 50}, "effects": {"gold": -50, "honor": 6, "fame": 3}, "result": "Los monjes rezarán por tu nombre en cada misa."},
		]},
	"mina": {"name": "Mina abandonada", "color": "8a6d4a", "months": [3, 5],
		"text": "Una vieja mina de plata, cerrada desde la última peste. Dicen que aún quedan vetas para quien se atreva a bajar.",
		"options": [
			{"label": "Bajar a buscar plata", "chance": 0.5, "chance_stat": "defense",
				"success": {"effects": {"gold": 120}, "result": "Encuentras una veta que los mineros dejaron atrás. Sales cargado de plata."},
				"failure": {"effects": {"health": -20, "gold": 15}, "result": "Un derrumbe te atrapa media jornada. Solo sacas unas pepitas."}},
			{"label": "Enviar a unos soldados a trabajarla", "requires": {"garrison": 30}, "effects": {"castle_gold": 80, "garrison": -3},
				"result": "Tus hombres sacan plata para el castillo, aunque no todos vuelven."},
		]},
	"torre_negra": {"name": "Torre del Caballero Negro", "color": "3a3540", "months": [2, 3],
		"text": "En una torre en ruinas aguarda un caballero de armadura negra. No da su nombre ni acepta rescate: solo se bate a muerte. Junto a él, los escudos de los que cayeron.",
		"options": [
			{"label": "Aceptar el duelo a muerte", "requires": {"healthy": true}, "effects": {},
				"result": "Desenvainas. El Caballero Negro inclina el yelmo: esto solo termina con uno de los dos en el suelo para siempre.",
				"fight": {"type": "duel", "no_rival": true, "to_death": true,
					"foe": {"name": "El Caballero Negro", "role": R.CABALLERO, "power": 2, "personality": "HONORABLE"},
					"win": {"effects": {"fame": 15, "honor": 8, "gold": 100, "unique": 100, "xp": 40}, "result": "El Caballero Negro cae. Bajo el yelmo no hay nombre que recordar, pero su reliquia legendaria y su fama son ahora tuyas."},
					"lose": {"effects": {}, "result": "El Caballero Negro limpia su espada y vuelve a esperar."}}},
		]},
}

const ORDER := ["ruinas", "campamento_bandido", "cueva", "monasterio", "mina", "torre_negra"]

static func site_def(type: String) -> Dictionary:
	return SITES.get(type, {})

## El lugar visto como un evento (para EventCatalog.apply_option, can_choose...).
static func as_event(type: String) -> Dictionary:
	var d := site_def(type)
	return {"id": type, "title": d.get("name", type), "text": d.get("text", ""), "options": d.get("options", [])}
