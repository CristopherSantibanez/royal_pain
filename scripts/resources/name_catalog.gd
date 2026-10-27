extends RefCounted
# Nombres históricos europeos por cultura. Cada reino del mundo tiene una cultura (ver MapData)
# y su gente se llama según ella. Los apellidos se combinan (casas, topónimos generados,
# patronímicos, oficios, sobrenombres), así que cada cultura da miles de nombres distintos.
#   const NameCatalog = preload("res://scripts/resources/name_catalog.gd")
#   NameCatalog.first_name(NameCatalog.Culture.CASTELLANA, gender)
#   NameCatalog.surname(culture, gender, rank)   # rank = Character.rank_of(role)

# Las nuevas se añaden SIEMPRE al final: los castillos guardan el número.
enum Culture { FRANCA, INGLESA, CASTELLANA, IMPERIAL, ROMANA, PRUSIANA, ITALIANA, BORGONONA, ARAGONESA }
const CULTURE_COUNT := 9

const CULTURE_NAMES := {
	Culture.FRANCA: "franca", Culture.INGLESA: "anglonormanda", Culture.CASTELLANA: "castellanoleonesa",
	Culture.IMPERIAL: "imperial", Culture.ROMANA: "romana", Culture.PRUSIANA: "prusiana",
	Culture.ITALIANA: "italiana", Culture.BORGONONA: "borgoñona", Culture.ARAGONESA: "aragonesa y catalana",
}

# --- Reglas de combinación (ajustables) ---
const NOBLE_RANK := 2                  # desde Caballero (Character.rank_of) se usa un apellido de casa
const NOBLE_HOUSE_CHANCE := 0.4        # casa histórica de la lista; si no, topónimo generado o patronímico
const COMMON_LIST_CHANCE := 0.45       # oficio o apodo de la lista; si no, patronímico o «de» + lugar
const COMMON_PATRONYMIC_CHANCE := 0.35
const BYNAME_CHANCE := 0.1             # caballeros y nobles menores: a veces solo se les conoce por su sobrenombre
const BYNAME_RANKS := [2, 3]

const MALE := {
	Culture.FRANCA: ["Childeberto", "Clodoveo", "Pipino", "Carlomán", "Teodorico", "Gontrán", "Chilperico", "Dagoberto",
		"Arnulfo", "Berenguer", "Lotario", "Odón", "Roberto", "Eudes", "Hugo", "Raúl", "Thierry", "Gerberto",
		"Clotario", "Sigeberto", "Meroveo", "Childerico", "Teodeberto", "Grimoaldo", "Ansegiso", "Carlos", "Luis",
		"Bernardo", "Bosón", "Rotrudo", "Guillermo", "Adalberto", "Balduino", "Arnaldo", "Hincmar", "Eginardo",
		"Turpín", "Rolando", "Oliveros", "Ganelón", "Naimes", "Ogier", "Girart", "Aymerí", "Vivien", "Rainaldo",
		"Bertrán", "Fulco", "Gualterio", "Godofredo", "Hilduino", "Lamberto", "Ricardo", "Rotberto", "Sigiberto",
		"Ebroíno", "Waifre", "Chlodomer", "Gondebaldo", "Ermenrico", "Adalardo", "Wala"],
	Culture.INGLESA: ["Æthelred", "Alfredo", "Edmundo", "Edgar", "Haroldo", "Godwin", "Leofric", "Osric", "Wulfstan",
		"Guillermo", "Godofredo", "Ricardo", "Eduardo", "Athelstan", "Oswaldo", "Wulfric", "Aldric", "Cuthbert",
		"Æthelwulf", "Æthelbert", "Ecgbert", "Eadwig", "Eadred", "Offa", "Penda", "Cynewulf", "Beornwulf", "Ceolwulf",
		"Byrhtnoth", "Leofwine", "Tostig", "Gyrth", "Morcar", "Edwin", "Siward", "Waltheof", "Hereward", "Ælfric",
		"Wigstan", "Osmund", "Cenred", "Ine", "Ceawlin", "Cerdic", "Odo", "Roger", "Ranulf", "Hugh", "Walter",
		"Gilbert", "Geoffrey", "Henry", "Stephen", "Simon", "Thomas", "Robert", "Ralph", "Baldwin", "Brian",
		"Alan", "Nigel", "Payne"],
	Culture.CASTELLANA: ["Rodrigo", "Alfonso", "Fernando", "Sancho", "Ramiro", "Bermudo", "Ordoño", "García", "Nuño",
		"Pelayo", "Íñigo", "Fruela", "Gonzalo", "Diego", "Álvar", "Fadrique", "Lope", "Tello", "Martín", "Pedro",
		"Suero", "Velasco", "Munio", "Gome", "Vela", "Fortún", "Rui", "Pero", "Gutierre", "Lain", "Fáñez",
		"Ansur", "Osorio", "Vermudo", "Aurelio", "Silo", "Mauregato", "Favila", "Teodomiro", "Hermenegildo",
		"Recaredo", "Leovigildo", "Wamba", "Fáfila", "Tructino", "Assur", "Galindo", "Domingo", "Benito",
		"Esteban", "Juan", "Gil", "Blasco", "Mendo", "Arias", "Enrique", "Beltrán", "Garci", "Hernán", "Egas",
		"Alonso", "Ñuño", "Sisnando"],
	Culture.IMPERIAL: ["Konrad", "Heinrich", "Otón", "Federico", "Lotario", "Rodolfo", "Bruno", "Wilhelm",
		"Ludwig", "Albrecht", "Ekkehard", "Gerhard", "Arnold", "Berthold", "Wolfram", "Engelbert", "Gottfried",
		"Hartmann", "Hermann", "Dietrich", "Ulrich", "Rupert", "Leopold", "Welf", "Burchard", "Liudolf", "Egbert",
		"Gebhard", "Meinhard", "Adalbert", "Siegfried", "Reinhard", "Volkmar", "Eberhard", "Walther", "Hugo",
		"Hildebrand", "Ruprecht", "Wenzel", "Sigismund", "Maximilian", "Ottokar", "Poppo", "Thietmar", "Wichmann",
		"Hademar", "Bernhard", "Kuno", "Manegold", "Diepold", "Folkmar", "Gunther", "Hagen", "Ortwin", "Gernot",
		"Giselher", "Rüdiger", "Volker", "Erchanger", "Lambert", "Marquard", "Anselm", "Otto", "Hartwig"],
	Culture.ROMANA: ["Lucio", "Marco", "Cayo", "Publio", "Quinto", "Tiberio", "Aulo", "Gneo", "Décimo",
		"Sexto", "Servio", "Tito", "Espurio", "Manio", "Numerio", "Opiter", "Apio", "Mamerco", "Flavio",
		"Aecio", "Estilicón", "Boecio", "Ambrosio", "Aureliano", "Valentiniano", "Teodosio", "Honorio", "Máximo",
		"Graciano", "Constancio", "Juliano", "Majoriano", "Antemio", "Olibrio", "Avito", "Mayorino", "Casiodoro",
		"Símaco", "Ausonio", "Paulino", "Sidonio", "Ecdicio", "Siagrio", "Egidio", "Bonifacio", "Belisario",
		"Narsés", "Germano", "Justino", "Anicio", "Petronio", "Venancio", "Rutilio", "Claudiano", "Prisco",
		"Marcelino", "Severino", "Vitaliano", "Liberio", "Fausto"],
	Culture.PRUSIANA: ["Hermann", "Dietrich", "Siegfried", "Ulrich", "Burchard", "Hartmut", "Winrich", "Anno",
		"Poppo", "Heinrich", "Konrad", "Markward", "Gunther", "Ludolf", "Kuno", "Eberhard", "Helmerich", "Luther",
		"Karl", "Werner", "Friedrich", "Michael", "Paul", "Kuntz", "Ludwig", "Johann", "Albrecht", "Otto",
		"Gottfried", "Meinhard", "Volrad", "Berthold", "Wigand", "Ditmar", "Hartwig", "Bernhard", "Arnold",
		"Rudolf", "Eckhard", "Gerlach", "Hennig", "Klaus", "Lorenz", "Matthias", "Nikolaus", "Sander", "Tile",
		"Glande", "Herkus", "Diwan", "Auttume", "Sabynus", "Nalubo", "Skurdo", "Pomande", "Wissebar", "Russigen",
		"Kantegerd", "Tirsko", "Stantico", "Girdaw"],
	Culture.ITALIANA: ["Guido", "Lorenzo", "Cosimo", "Ugolino", "Castruccio", "Ezzelino", "Galeazzo", "Bernabò",
		"Cangrande", "Manfredo", "Azzo", "Obizzo", "Francesco", "Sigismondo", "Federigo", "Pandolfo", "Gian",
		"Ludovico", "Ercole", "Borso", "Niccolò", "Leonello", "Mastino", "Alboino", "Bartolomeo", "Filippo",
		"Gianni", "Iacopo", "Matteo", "Ottone", "Ranieri", "Uberto", "Uguccione", "Vieri", "Corso", "Farinata",
		"Buondelmonte", "Brunetto", "Dante", "Guelfo", "Ghino", "Tancredi", "Ruggero", "Roberto", "Malatesta",
		"Carlo", "Pietro", "Giovanni", "Antonio", "Andrea", "Battista", "Bonifacio", "Cecco", "Taddeo", "Ugo",
		"Vanni", "Zanobi", "Agnolo", "Baldo", "Rinaldo", "Astorre"],
	Culture.BORGONONA: ["Felipe", "Juan", "Carlos", "Hugo", "Otón", "Eudes", "Guigues", "Amadeo", "Gerardo",
		"Renaud", "Thibaut", "Anseau", "Guillaume", "Jacques", "Antoine", "Rolin", "Gondebaldo", "Gundioco",
		"Sigismundo", "Godomaro", "Chilperico", "Boso", "Rodolfo", "Conrado", "Gilberto", "Landri", "Manasés",
		"Ricardo", "Enrique", "Roberto", "Odón", "Esteban", "Humberto", "Aymon", "Pierre", "Jean", "Guy",
		"Gautier", "Josserand", "Hugues", "Milon", "Narjod", "Savaric", "Thierry", "Vauthier", "Arnoul",
		"Bernard", "Claude", "Denis", "Étienne", "Gaucher", "Hélie", "Imbert", "Lancelin", "Mathieu", "Nicolas",
		"Olivier", "Ponce", "Simon", "Tristan", "Yves"],
	Culture.ARAGONESA: ["Jaime", "Pedro", "Ramón", "Berenguer", "Guifré", "Borrell", "Sunyer", "Ermengol", "Miró",
		"Bernat", "Arnau", "Pere", "Jaume", "Alfons", "Ferran", "Galceran", "Guillem", "Dalmau", "Huc", "Ponç",
		"Gombau", "Bertran", "Ot", "Roger", "Simó", "Joan", "Martí", "Lluís", "Francesc", "Jofre", "Gastó", "Artal",
		"Blasco", "Fortún", "Jimeno", "Aznar", "Galindo", "Ato", "Sancho", "García", "Lope", "Íñigo", "Pero",
		"Ramiro", "Gonzalvo", "Atón", "Fortuño", "Bermón", "Gauzfred", "Seniofred", "Oliba", "Wifredo", "Udalard",
		"Mir", "Isarn", "Folc", "Guerau", "Hug", "Raimon", "Riambau", "Asbert"],
}

const FEMALE := {
	Culture.FRANCA: ["Clotilde", "Brunilda", "Fredegunda", "Radegunda", "Bertrada", "Hildegarda", "Gisela", "Rotruda",
		"Ermengarda", "Adela", "Gerberga", "Judit", "Emma", "Berta", "Ingunda", "Basina", "Clodosinda", "Galsuinda",
		"Audovera", "Nantilde", "Plectrudis", "Alpaida", "Swanahilda", "Liutgarda", "Fastrada", "Himiltruda",
		"Teodrada", "Gisla", "Regina", "Ricarda", "Adelaida", "Engelberga", "Richilda", "Ogiva", "Eadgifu", "Hedwig",
		"Rosala", "Constanza", "Anna", "Alienor", "Aude", "Belisenda", "Ermesinda", "Guiberga", "Heloísa", "Ida",
		"Mahaut", "Oda", "Petronila", "Rotrudis", "Sancia", "Teutberga", "Waldrada", "Yolanda", "Alda", "Aelis",
		"Blanchefleur", "Euriant", "Floripas", "Grimalda", "Hersent"],
	Culture.INGLESA: ["Godiva", "Æthelflæd", "Edith", "Mildred", "Hilda", "Matilde", "Leonor", "Rowena", "Ælfgifu",
		"Eadburh", "Wynflæd", "Cyneburga", "Isabel", "Juliana", "Alice", "Margery", "Æthelthryth", "Æthelburh",
		"Eadgyth", "Ælfthryth", "Ealhswith", "Cwenthryth", "Frideswide", "Werburgh", "Hereswith", "Sexburga",
		"Eormenhild", "Wihtburh", "Eanflæd", "Osthryth", "Cynethryth", "Ælfflæd", "Gytha", "Ealdgyth", "Godgifu",
		"Wulfrun", "Leofrun", "Emma", "Adeliza", "Rohese", "Avice", "Cecily", "Joan", "Agnes", "Amice", "Beatrice",
		"Constance", "Denise", "Edeline", "Ela", "Felice", "Hawise", "Idonea", "Joanna", "Lettice", "Maud",
		"Petronel", "Sibyl", "Thomasin", "Wymarc"],
	Culture.CASTELLANA: ["Urraca", "Jimena", "Sancha", "Elvira", "Toda", "Berenguela", "Mencía", "Teresa", "Aldonza",
		"Oria", "Guiomar", "Leonor", "Constanza", "Fronilde", "Mayor", "Estefanía", "Munia", "Adosinda", "Ermesinda",
		"Froiliuba", "Gontrodo", "Goto", "Justa", "Velasquita", "Onneca", "Muniadona", "Paterna", "Ilduara",
		"Aragonta", "Cixila", "Gelvira", "Egilo", "Florencia", "Columba", "Eugenia", "María", "Juana", "Inés",
		"Catalina", "Beatriz", "Blanca", "Isabel", "Violante", "Mafalda", "Marina", "Elo", "Godina", "Lambra",
		"Ofresa", "Sol", "Ximena", "Aurovita", "Brunilde", "Endrequina", "Fruilo", "Gutina", "Leodegundia",
		"Recesvinda", "Sabita", "Tegridia"],
	Culture.IMPERIAL: ["Hildegard", "Adelaida", "Gisela", "Richenza", "Beatriz", "Kunigunde", "Matilde", "Agnes",
		"Teófano", "Irmgard", "Hedwig", "Gertrudis", "Ida", "Uta", "Liutgarda", "Imma", "Adelheid", "Bertha",
		"Christina", "Eilika", "Gerberga", "Hadwig", "Judith", "Oda", "Reinhild", "Sophie", "Walburga", "Wulfhild",
		"Brunhild", "Kriemhild", "Ute", "Mechthild", "Elisabeth", "Margarete", "Anna", "Katharina", "Barbara",
		"Ottilie", "Rotraut", "Swanhild", "Theodora", "Heilwig", "Frideruna", "Godila", "Hazecha", "Ermengard",
		"Engelrada", "Friderun", "Gepa", "Hathui", "Irmintrud", "Liutburga", "Mathilde", "Petrissa", "Rikissa",
		"Salome", "Thietburga", "Willa", "Yrmgard", "Zita"],
	Culture.ROMANA: ["Livia", "Julia", "Cornelia", "Claudia", "Valeria", "Aurelia", "Octavia", "Antonia",
		"Fabia", "Flavia", "Domicia", "Sulpicia", "Calpurnia", "Junia", "Emilia", "Servilia", "Agripina", "Drusila",
		"Popea", "Mesalina", "Faustina", "Plotina", "Sabina", "Marcia", "Lucila", "Galla", "Placidia", "Honoria",
		"Eudoxia", "Pulqueria", "Justa", "Grata", "Serena", "Gala", "Licinia", "Pompeya", "Tulia", "Terencia",
		"Porcia", "Hortensia", "Sempronia", "Fulvia", "Clodia", "Lesbia", "Vipsania", "Atia", "Escribonia",
		"Valentina", "Paulina", "Marcela", "Melania", "Fabiola", "Proba", "Anicia", "Rufina", "Severa", "Vibia",
		"Albina", "Lepida", "Mucia"],
	Culture.PRUSIANA: ["Jutta", "Kunigunde", "Mechthild", "Gertrud", "Sophia", "Elisabeth", "Dorothea", "Barbara",
		"Margarete", "Adelheid", "Hedwig", "Jadwiga", "Katharina", "Anna", "Ottilie", "Ermentrud", "Agnes",
		"Christina", "Gisela", "Hildegard", "Ida", "Irmgard", "Judith", "Luitgard", "Mathilde", "Regina",
		"Ursula", "Walburga", "Benigna", "Brigitte", "Cäcilie", "Elsbeth", "Gesa", "Grete", "Hille", "Ilse",
		"Kathrein", "Lene", "Mette", "Notburga", "Ortrud", "Rixa", "Sibylle", "Trude", "Wiebke", "Adalwig",
		"Swantje", "Tekla", "Vroni", "Wendula", "Pomesa", "Aistė", "Gaile", "Jundile", "Milda", "Nida",
		"Ruta", "Skaidra", "Visa", "Zinte"],
	Culture.ITALIANA: ["Beatrice", "Bianca", "Matilde", "Costanza", "Isotta", "Caterina", "Ginevra", "Lucrezia",
		"Simonetta", "Fiammetta", "Laura", "Clarice", "Tancia", "Giovanna", "Ippolita", "Taddea", "Agnese",
		"Alda", "Bona", "Cecilia", "Contessina", "Diana", "Eleonora", "Filippa", "Gemma", "Lapa", "Lisa",
		"Lucia", "Maddalena", "Margherita", "Nannina", "Orsola", "Piccarda", "Riccarda", "Sancia", "Teodolinda",
		"Ubaldina", "Violante", "Zanobia", "Adelasia", "Bertilla", "Cunizza", "Dianora", "Emilia", "Francesca",
		"Gherardesca", "Ildegarda", "Lapina", "Mona", "Nella", "Oretta", "Pia", "Rosana", "Selvaggia", "Tessa",
		"Ughetta", "Vanna", "Zita", "Alessandra", "Brigida"],
	Culture.BORGONONA: ["Margarita", "Isabel", "Yolanda", "Juana", "Inés", "Alix", "Beatriz", "Sibila",
		"Ermesinda", "Clemencia", "Bona", "Catalina", "María", "Ana", "Guillermina", "Maud", "Clotilde", "Sedeleuba",
		"Crona", "Teudelinda", "Ermengarda", "Adelaida", "Gisela", "Berta", "Matilde", "Aremburga", "Blanca",
		"Elena", "Felicia", "Hermesenda", "Isabeau", "Jacqueline", "Marie", "Perrette", "Philippa", "Agnès",
		"Alienor", "Aveline", "Béatrix", "Colette", "Denise", "Édeline", "Emeline", "Gillette", "Guyonne",
		"Huguette", "Jehanne", "Léonor", "Mahaut", "Marguerite", "Nicole", "Oudette", "Péronne", "Renée",
		"Simone", "Thiphaine", "Ysabel", "Aude", "Bonne", "Clémence"],
	Culture.ARAGONESA: ["Ermessenda", "Elisenda", "Sança", "Peronella", "Constança", "Elionor", "Violant", "Brianda",
		"Teresa", "Guillema", "Saurina", "Blanca", "Tecla", "Agnès", "Dolça", "Adelaida", "Ava", "Riquilda",
		"Garsenda", "Estefania", "Maria", "Margarida", "Isabel", "Caterina", "Urraca", "Toda", "Oneca", "Andregoto",
		"Sancha", "Jimena", "Galindona", "Mayor", "Felicia", "Inés", "Berenguela", "Marquesa", "Alamanda",
		"Arsenda", "Belasquita", "Cecília", "Eldiarda", "Ermengarda", "Garsendis", "Guisla", "Letgarda",
		"Ledgarda", "Mafalda", "Ramona", "Sibil·la", "Tota", "Aldonça", "Bonanada", "Clara", "Eulàlia",
		"Francesca", "Gueraua", "Joana", "Llúcia", "Romia", "Valença"],
}

# Casas nobles históricas o verosímiles.
const NOBLE_HOUSES := {
	Culture.FRANCA: ["de Laon", "de Soissons", "de Herstal", "de Tours", "de Reims", "de Vermandois", "de Poitiers",
		"de Montfort", "de Blois", "de Anjou", "de Coucy", "de Meaux", "de Metz", "de Austrasia", "de Neustria",
		"de Orleans", "de Chartres", "de Troyes", "de Champaña", "de Flandes", "de Toulouse", "de Aquitania",
		"de Nevers", "de Sens", "de Cambrai", "de Arrás", "de Amiens", "de Beauvais", "de Noyon", "de Paris"],
	Culture.INGLESA: ["of Wessex", "of Mercia", "of Northumbria", "of Kent", "de Clare", "de Beaumont", "de Mowbray",
		"of Essex", "de Warenne", "Fitzalan", "de Lacy", "of Wiltshire", "de Bohun", "de Vere", "Mortimer",
		"Neville", "Percy", "de Montagu", "Despenser", "Marshal", "de Ferrers", "Bigod", "de Quincy", "Basset",
		"Mandeville", "de Braose", "of Sussex", "of East Anglia", "of Hwicce", "of Lindsey"],
	Culture.CASTELLANA: ["de Lara", "de Castro", "de Haro", "de Vivar", "de Ansúrez", "de Mendoza", "de Guzmán",
		"de Meneses", "de Traba", "Osorio", "de Azagra", "de Cameros", "de Saldaña", "de Carrión", "de Monzón",
		"de Lemos", "de Trastámara", "de Villalobos", "Manrique", "de Albornoz", "de la Cerda", "de Molina",
		"Girón", "Ponce de León", "de Zúñiga", "de Velasco", "de Quiñones", "de Benavides", "de Sarmiento",
		"de Cisneros"],
	Culture.IMPERIAL: ["von Staufen", "von Babenberg", "von Zähringen", "von Wittelsbach", "von Habsburg", "von Welf",
		"von Supplinburg", "von Nassau", "von Henneberg", "von Andechs", "von Sponheim", "von Lützelburg",
		"von Wettin", "von Askanien", "von Billung", "von Liudolfing", "von Salier", "von Hohenzollern",
		"von Württemberg", "von Görz", "von Kärnten", "von Meißen", "von Thüringen", "von Formbach",
		"von Northeim", "von Werl", "von Ballenstedt", "von Querfurt", "von Ziegenhain", "von Katzenelnbogen"],
	Culture.ROMANA: ["Cornelio Escipión", "Julio César", "Claudio Nerón", "Valerio Máximo", "Aurelio Cota",
		"Fabio Máximo", "Emilio Paulo", "Sempronio Graco", "Licinio Craso", "Domicio Enobarbo", "Sulpicio Galba",
		"Junio Bruto", "Anicio Probo", "Petronio Máximo", "Flavio Aecio", "Decio Mus", "Furio Camilo",
		"Postumio Albino", "Quintio Cincinato", "Manlio Torcuato", "Mucio Escévola", "Calpurnio Pisón",
		"Cecilio Metelo", "Hortensio Hórtalo", "Tulio Cicerón", "Porcio Catón", "Atilio Régulo", "Claudio Marcelo",
		"Lutacio Cátulo", "Servilio Cepión"],
	Culture.PRUSIANA: ["von Salza", "von Plauen", "von Jungingen", "von Kniprode", "von Feuchtwangen", "von Balk",
		"von Altenburg", "von Orseln", "von Dusemer", "von Wallenrode", "von Sangerhausen", "von Hohenlohe",
		"von Erlichshausen", "von Richtenberg", "von Tiefen", "von Brandenburg", "von Dohna", "von Eulenburg",
		"von der Groeben", "von Kalckstein", "von Lehndorff", "von Schlieben", "von Wedel", "von Kittlitz",
		"von Pomesanien", "von Samland", "von Natangen", "von Ermland", "von Kulm", "von Thorn"],
	Culture.ITALIANA: ["da Montefeltro", "Visconti", "della Scala", "d'Este", "Gonzaga", "Malatesta", "Sforza",
		"degli Albizzi", "da Carrara", "Orsini", "Colonna", "della Torre", "de' Medici", "Strozzi", "Pazzi",
		"Rucellai", "Baglioni", "Bentivoglio", "da Polenta", "Ordelaffi", "Manfredi", "Pico della Mirandola",
		"Doria", "Spinola", "Grimaldi", "Fieschi", "Dandolo", "Contarini", "Morosini", "Caetani"],
	Culture.BORGONONA: ["de Vergy", "de Chalon", "de Neufchâtel", "de Vienne", "de Saulx", "de Grancey", "de Rolin",
		"de Toulongeon", "de Châteauvillain", "de Pontailler", "de Mâcon", "de Salins", "de Beaujeu", "de Thoire",
		"de Villars", "de Montbéliard", "de Faucogney", "de Rougemont", "de Ray", "de Joux", "de Granson",
		"de La Trémoille", "de Croÿ", "de Lannoy", "de Luxembourg", "de Lalaing", "de Brimeu", "de Charny",
		"de Bauffremont", "de Ternant"],
	Culture.ARAGONESA: ["de Cardona", "de Montcada", "d'Urgell", "d'Entença", "de Luna", "de Urrea", "de Alagón",
		"de Pallars", "de Rocabertí", "de Cabrera", "de Foix", "de Cervera", "de Castellvell", "de Queralt",
		"de Ribagorza", "de Sobrarbe", "de Lizana", "de Bardaxí", "de Híjar", "de Ayerbe", "de Erill",
		"d'Empúries", "de Besalú", "de Cerdanya", "de Osona", "de Montcada", "de Pinós", "de So", "de Santcliment",
		"de Fenollet"],
}

# Topónimos generados: prefijo + sufijo («Hohen» + «stein» → «von Hohenstein»).
const PLACE_PREFIX := {
	Culture.FRANCA: ["Mont", "Beau", "Clair", "Vau", "Roche", "Château", "Ville", "Bel", "Haute", "Grand", "Val",
		"Fontaine", "Pierre", "Chaume", "Ver", "Long", "Neuf", "Mal", "Gué", "Brai", "Ar", "Cler", "Esti", "Fer"],
	Culture.INGLESA: ["Ash", "Brad", "Thorn", "Wolver", "Stan", "Bur", "Ather", "Win", "Ox", "Hart", "Wake",
		"Elm", "Black", "Red", "Wych", "Hamble", "Kings", "Brom", "Ald", "Mar", "Wes", "Nor", "Lang", "Shel", "Ever", "Hol"],
	Culture.CASTELLANA: ["Villa", "Castro", "Torre", "Fuente", "Peña", "Val", "Monte", "Navas", "Puebla", "Cerro",
		"Hoya", "Campo", "Ribera", "Quintana", "Cueva", "Vega", "Robla", "Salce", "Hiniesta", "Olmeda"],
	Culture.IMPERIAL: ["Hohen", "Falken", "Rosen", "Lichten", "Eichen", "Wolfs", "Adler", "Schwarz", "Weiß",
		"Roten", "Grün", "Linden", "Stein", "Wald", "Hirsch", "Eber", "Kron", "Sonnen", "Tann", "Hagen", "Ehren",
		"Königs", "Neu", "Alt", "Ober", "Nieder", "Kirch", "Hammer", "Löwen", "Greifen"],
	Culture.PRUSIANA: ["Marien", "Oster", "Elb", "Heil", "Preuß", "Ragni", "Tapi", "Labi", "Inster", "Gold", "Fried",
		"Wehl", "Barten", "Schippen", "Rasten", "Gerdau", "Allen", "Ortels", "Lötzen", "Anger", "Sens", "Neiden"],
	Culture.ITALIANA: ["Monte", "Castel", "Villa", "Borgo", "Rocca", "Poggio", "Sasso", "Ponte", "Valle", "Torre",
		"Colle", "Pieve", "Campo", "Serra", "Fonte", "Pietra", "Selva", "Lago", "Riva", "Capo"],
	Culture.BORGONONA: ["Châtel", "Ver", "Sau", "Mont", "Fla", "Cor", "Beaune", "Arnay", "Bour", "Grand", "Pont",
		"Saint", "Chaux", "Roche", "Bois", "Champ", "Mar", "Sem", "Vil", "Tal"],
	Culture.ARAGONESA: ["Vila", "Castell", "Mont", "Puig", "Sant", "Torre", "Coll", "Pla", "Roca", "Riu", "Font",
		"Mas", "Pont", "Vall", "Serra", "Camp", "Bell", "Bar", "Cas", "Al"],
}
const PLACE_SUFFIX := {
	Culture.FRANCA: ["fort", "mont", "ville", "court", "val", "lieu", "bois", "champ", "roche", "fleur", "pré",
		"bourg", "castel", "mesnil", "fontaine", "vaux", "rive", "lac", "pierre", "garde"],
	Culture.INGLESA: ["ford", "ham", "ton", "ley", "by", "wick", "bury", "field", "worth", "stead", "combe", "mere",
		"dale", "hurst", "brook", "wood", "thorpe", "minster", "chester", "stow"],
	Culture.CASTELLANA: ["nueva", "rubia", "verde", "alba", "fría", "seca", "llana", "honda", "real", "mayor",
		"blanca", "negra", "dorada", "alta", "baja", "vieja", "hermosa", "brava"],
	Culture.IMPERIAL: ["burg", "stein", "berg", "feld", "au", "fels", "eck", "hausen", "bach", "dorf", "heim",
		"wald", "thal", "hof", "brück", "rode", "eich", "furt"],
	Culture.PRUSIANA: ["burg", "berg", "stein", "au", "walde", "werder", "hagen", "felde", "dorf", "kirch",
		"stadt", "see", "brück", "furt", "rode", "itten"],
	Culture.ITALIANA: ["fiore", "nuovo", "alto", "bianco", "franco", "rosso", "verde", "lungo", "secco", "forte",
		"vecchio", "chiaro", "maggiore", "piano", "oscuro", "dolce", "bello", "santo"],
	Culture.BORGONONA: ["on", "ey", "ans", "ois", "eau", "ière", "ville", "court", "mont", "lieu", "y", "ange",
		"enay", "eux", "ain", "ard"],
	Culture.ARAGONESA: ["nova", "seca", "alt", "blanc", "roig", "fort", "verd", "major", "vell", "llarg", "bona",
		"ric", "clar", "sobirà", "fosc", "gran"],
}
const NOBLE_PARTICLE := {
	Culture.FRANCA: "de ", Culture.INGLESA: "of ", Culture.CASTELLANA: "de ", Culture.IMPERIAL: "von ",
	Culture.PRUSIANA: "von ", Culture.ITALIANA: "da ", Culture.BORGONONA: "de ", Culture.ARAGONESA: "de ",
}

# Apellidos de la gente llana: oficios, apodos y lugares.
const COMMON_SURNAMES := {
	Culture.FRANCA: ["le Roux", "le Fort", "le Brun", "le Bègue", "Fèvre", "Charpentier", "de la Fontaine", "Bonhomme",
		"le Grand", "Boucher", "Meunier", "Pasquier", "le Blond", "le Petit", "le Sage", "Tailleur", "Tisserand",
		"Berger", "Charron", "Couturier", "Fournier", "Fouquier", "Lebrun", "Marchand", "Pelletier", "Potier",
		"Sellier", "Taillefer", "Vacher", "Vigneron"],
	Culture.INGLESA: ["Fletcher", "Thatcher", "Cooper", "Smith", "Miller", "Baker", "Shepherd", "Wright", "Fowler",
		"Carter", "Ward", "Tanner", "Turner", "Weaver", "Fuller", "Mason", "Archer", "Bowyer", "Chandler",
		"Fisher", "Hayward", "Hunter", "Knight", "Little", "Long", "Reeve", "Short", "Webb", "White", "Young"],
	Culture.CASTELLANA: ["Herrero", "Molinero", "Pastor", "Cabrero", "Tejedor", "Zapatero", "Carretero", "Hortelano",
		"Calvo", "Delgado", "Moreno", "Rubio", "Bermejo", "Cano", "Romero", "Crespo", "Prieto", "Barbero",
		"Cantero", "Sastre", "Vaquero", "Leñador", "Montero", "Ballestero", "Alférez", "Cazador", "Escudero",
		"Tornero", "Valiente", "Bueno"],
	Culture.IMPERIAL: ["Weber", "Fischer", "Müller", "Schmidt", "Becker", "Wagner", "Zimmermann", "Bauer", "Krämer",
		"Vogt", "Hoffmann", "Schäfer", "Koch", "Richter", "Klein", "Wolf", "Schröder", "Neumann", "Schwarz",
		"Braun", "Hofmann", "Hartmann", "Lange", "Werner", "Krause", "Meier", "Lehmann", "Huber", "Mayer", "Köhler"],
	Culture.ROMANA: ["Prisco", "Rufo", "Varo", "Bruto", "Paulino", "Celer", "Galo", "Félix", "Severo", "Nasón",
		"Crispo", "Vero", "Albino", "Balbo", "Calvo", "Cato", "Dento", "Flaco", "Lento", "Longo", "Macro", "Níger",
		"Pío", "Pulcro", "Rústico", "Sabino", "Seneca", "Tácito", "Torcuato", "Urbico"],
	Culture.PRUSIANA: ["Krause", "Wendt", "Lange", "Schulz", "Kowalk", "Preuss", "Kraft", "Gerlach", "Wolff", "Thiel",
		"Rautenberg", "Pruzze", "Kuhn", "Laskowski", "Kopp", "Raabe", "Szameitat", "Gudat", "Kalweit", "Naujoks",
		"Petereit", "Schwarz", "Kischkat", "Bendig", "Pillkahn", "Matzat", "Jurgeleit", "Weitschies", "Kossak", "Lemke"],
	Culture.ITALIANA: ["Rossi", "Bianchi", "Ferraro", "Esposito", "Colombo", "Ricci", "Marino", "Greco", "Bruno",
		"Gallo", "Conti", "Fabbri", "Barbieri", "Caruso", "Fontana", "Galli", "Lombardi", "Mancini", "Moretti",
		"Pellegrini", "Rinaldi", "Russo", "Sala", "Santoro", "Testa", "Valentini", "Vitale", "Zanetti", "Ferri", "Grasso"],
	Culture.BORGONONA: ["Lefèvre", "Mercier", "Dupont", "Girard", "Moreau", "Lambert", "Bonnet", "Guyot", "Perrin",
		"Morel", "Garnier", "Chevalier", "Bernard", "Boyer", "Brunet", "Clément", "Faure", "Gautier", "Guérin",
		"Joly", "Lemoine", "Mathieu", "Michaud", "Picard", "Renard", "Roussel", "Simonin", "Thévenin", "Vincent", "Voisin"],
	Culture.ARAGONESA: ["Ferrer", "Fuster", "Sastre", "Pastor", "Moliner", "Ribes", "Vidal", "Roig", "Blanc", "Puig",
		"Soler", "Pujol", "Serra", "Mas", "Font", "Bosch", "Prat", "Vila", "Riera", "Torrent", "Ballester",
		"Mestre", "Teixidor", "Pagès", "Fornés", "Clavell", "Coll", "Bonet", "Gil", "Lluch"],
}

# Patronímicos: nombre del padre → apellido («Rodrigo» → «Rodríguez»).
const PATRONYMICS := {
	Culture.CASTELLANA: {"Rodrigo": "Rodríguez", "Fernando": "Fernández", "Sancho": "Sánchez", "Ramiro": "Ramírez",
		"Martín": "Martínez", "Nuño": "Núñez", "Gonzalo": "González", "Diego": "Díaz", "Pedro": "Pérez",
		"Álvar": "Álvarez", "Gome": "Gómez", "Munio": "Muñoz", "Vela": "Vélaz", "García": "Garcés", "Lope": "López",
		"Ordoño": "Ordóñez", "Bermudo": "Bermúdez", "Fruela": "Froilaz", "Íñigo": "Íñiguez", "Suero": "Suárez",
		"Velasco": "Velázquez", "Domingo": "Domínguez", "Benito": "Benítez", "Esteban": "Estébanez", "Juan": "Ibáñez",
		"Galindo": "Galíndez", "Mendo": "Méndez", "Gutierre": "Gutiérrez", "Hernán": "Hernández", "Alonso": "Alonso",
		"Pelayo": "Peláez", "Tello": "Téllez", "Ansur": "Ansúrez", "Osorio": "Osóriz", "Fortún": "Fortúnez"},
	Culture.ARAGONESA: {"Jimeno": "Ximénez", "García": "Garcés", "Íñigo": "Íñiguez", "Fortún": "Fortuñones",
		"Sancho": "Sánchez", "Galindo": "Galíndez", "Aznar": "Aznárez", "Lope": "López", "Blasco": "Blázquez",
		"Pero": "Pérez", "Ramón": "Ramonet", "Bernat": "Bernadí", "Martí": "Martínez", "Ato": "Atón",
		"Jaume": "Jaumà", "Arnau": "Arnaldó", "Ponç": "Poncet", "Guillem": "Guillamet"},
}
# Patronímicos por sufijo o partícula en las demás culturas («Godwin» → «Godwinson», «di Guido»).
const PATRONYMIC_PATTERN := {
	Culture.INGLESA: ["%sson", "Fitz%s"], Culture.ITALIANA: ["di %s", "de' %s"], Culture.FRANCA: ["fils de %s"],
	Culture.BORGONONA: ["fils de %s"],
}

# Cognomina romanos (el apellido romano es nomen + cognomen).
const ROMAN_NOMINA := ["Cornelio", "Julio", "Claudio", "Valerio", "Aurelio", "Fabio", "Emilio", "Sempronio", "Licinio",
	"Domicio", "Sulpicio", "Junio", "Anicio", "Petronio", "Flavio", "Decio", "Furio", "Postumio", "Quintio", "Manlio",
	"Mucio", "Calpurnio", "Cecilio", "Hortensio", "Tulio", "Porcio", "Atilio", "Lutacio", "Servilio", "Octavio",
	"Antonio", "Livio", "Marcio", "Pompeyo", "Terencio", "Vipsanio", "Fulvio", "Clodio", "Vibio", "Ulpio",
	"Elio", "Didio", "Septimio", "Pescenio", "Galerio"]
const ROMAN_COGNOMINA := ["Escipión", "César", "Nerón", "Máximo", "Cota", "Paulo", "Graco", "Craso", "Enobarbo",
	"Galba", "Bruto", "Probo", "Aecio", "Mus", "Camilo", "Albino", "Cincinato", "Torcuato", "Escévola", "Pisón",
	"Metelo", "Hórtalo", "Cicerón", "Catón", "Régulo", "Marcelo", "Cátulo", "Cepión", "Rufo", "Prisco", "Varo",
	"Severo", "Balbo", "Léntulo", "Dolabela", "Silano", "Agripa", "Druso", "Germánico", "Africano", "Asiático",
	"Magno", "Pío", "Félix", "Sabino", "Tácito", "Celso", "Frontino", "Plauto", "Lépido"]

# Sobrenombres [masculino, femenino].
const BYNAMES := [["el Bravo", "la Brava"], ["el Calvo", "la Calva"], ["el Piadoso", "la Piadosa"], ["el Sabio", "la Sabia"],
	["el Cruel", "la Cruel"], ["el Grande", "la Grande"], ["el Joven", "la Joven"], ["el Viejo", "la Vieja"],
	["el Tuerto", "la Tuerta"], ["el Martillo", "la del Martillo"], ["el Justo", "la Justa"], ["el Negro", "la Negra"],
	["el Rojo", "la Roja"], ["el Batallador", "la Batalladora"], ["el Tartamudo", "la Tartamuda"], ["el Gordo", "la Gorda"],
	["el Breve", "la Breve"], ["el Santo", "la Santa"], ["el Temerario", "la Temeraria"], ["el Bueno", "la Buena"],
	["Corazón de León", "Corazón de León"], ["Barbarroja", "Cabellos de Fuego"], ["Mano de Hierro", "Mano de Hierro"],
	["el Conquistador", "la Conquistadora"], ["el Cazador", "la Cazadora"], ["el Peregrino", "la Peregrina"],
	["el Prudente", "la Prudente"], ["el Fuerte", "la Fuerte"], ["el Leal", "la Leal"], ["el Lobo", "la Loba"],
	["Matamoros", "Matamoros"], ["el Desheredado", "la Desheredada"], ["Lanza Rota", "Lanza Rota"], ["el Escudero", "la Escudera"]]

# --- Nombres de reinos ---
# Título del territorio: casi siempre «Reino»; a veces otro propio de su cultura.
const REALM_TITLE_CHANCE := 0.65      # probabilidad de «Reino»
const REALM_TITLES := {
	Culture.FRANCA: ["Condado", "Ducado", "Marca"], Culture.INGLESA: ["Condado", "Marca", "Principado"],
	Culture.CASTELLANA: ["Condado", "Señorío", "Marca"], Culture.IMPERIAL: ["Ducado", "Principado", "Landgraviato", "Marca"],
	Culture.ROMANA: ["Imperio", "Provincia", "Prefectura"], Culture.PRUSIANA: ["Orden", "Marca", "Ducado"],
	Culture.ITALIANA: ["Señoría", "República", "Ducado", "Marquesado"], Culture.BORGONONA: ["Ducado", "Condado", "Principado"],
	Culture.ARAGONESA: ["Condado", "Principado", "Marca"],
}
# Regiones con sabor histórico; si no sale una, se inventa un topónimo con PLACE_PREFIX/SUFFIX.
const REALM_REGIONS := {
	Culture.FRANCA: ["Austrasia", "Neustria", "Septimania", "Aquitania", "Lotaringia", "Vermandois", "Francia Media", "Turena", "Rouergue", "Gothia"],
	Culture.INGLESA: ["Wessmark", "Deira", "Bernicia", "Elmet", "Lindsey", "Hwicce", "Magonsæte", "Wessex", "Anglia", "Cumbria"],
	Culture.CASTELLANA: ["Valdemora", "Tierra de Campos", "Liébana", "Bureba", "Extremadura", "Asturias", "Galicia", "Campoalto", "Vardulia", "Alava"],
	Culture.IMPERIAL: ["Franconia", "Suabia", "Sajonia", "Turingia", "Carintia", "Lusacia", "Brisgovia", "Nordgau", "Hohenstein", "Falkenburg"],
	Culture.ROMANA: ["Aurelia", "Tarraconense", "Bética", "Lusitania", "Dalmacia", "Panonia", "Nórico", "Retia", "Mesia", "Iliria"],
	Culture.PRUSIANA: ["Marienwald", "Pomesania", "Sambia", "Natangia", "Varmia", "Galindia", "Sudovia", "Nadrovia", "Kulmerland", "Pogesania"],
	Culture.ITALIANA: ["Montebello", "Lombardía", "Romaña", "Emilia", "Marca Trevisana", "Friul", "Lunigiana", "Garfagnana", "Valdelsa", "Casentino"],
	Culture.BORGONONA: ["Borgoña", "Franco Condado", "Charolais", "Auxois", "Bresse", "Bugey", "Mâconnais", "Nivernais", "Saboya", "Valais"],
	Culture.ARAGONESA: ["Ribagorza", "Sobrarbe", "Pallars", "Urgel", "Cerdaña", "Besalú", "Osona", "Ampurias", "Rosellón", "Conflent"],
}
const REALM_REGION_CHANCE := 0.5

## Nombre de un reino para la interfaz («Reino de Valdemora», «Ducado de Hohenstein»...).
static func realm_name(culture: int, rng: RandomNumberGenerator = null, island: bool = false) -> String:
	culture = valid(culture)
	var core := _pick(REALM_REGIONS[culture], rng) if _roll(rng) < REALM_REGION_CHANCE else place(culture, rng)
	if island:
		return "Isla de %s" % core
	var title := "Reino" if _roll(rng) < REALM_TITLE_CHANCE else _pick(REALM_TITLES[culture], rng)
	return "%s de %s" % [title, core]

static func culture_name(culture: int) -> String:
	return CULTURE_NAMES.get(culture, "")

static func valid(culture: int) -> int:
	return culture if culture >= 0 and culture < CULTURE_COUNT else randi() % CULTURE_COUNT

static func first_name(culture: int, gender: int, rng: RandomNumberGenerator = null) -> String:
	culture = valid(culture)
	var pool: Array = (FEMALE if gender == CharacterEnums.Gender.FEMENINO else MALE)[culture]
	return _pick(pool, rng)

## Apellido según cultura, sexo y rango: casa noble desde Caballero, apellido llano por debajo.
static func surname(culture: int, gender: int, rank: int = NOBLE_RANK, rng: RandomNumberGenerator = null) -> String:
	culture = valid(culture)
	if culture == Culture.ROMANA:
		return _roman_surname(gender, rng)
	if rank in BYNAME_RANKS and _roll(rng) < BYNAME_CHANCE:
		return byname(gender, rng)
	if rank >= NOBLE_RANK:
		if _roll(rng) < NOBLE_HOUSE_CHANCE:
			return _pick(NOBLE_HOUSES[culture], rng)
		if PATRONYMICS.has(culture) and _roll(rng) < 0.5:
			return "%s de %s" % [_patronymic(culture, rng), place(culture, rng)]   # «Rodrigo Díaz de Vivar»
		return NOBLE_PARTICLE[culture] + place(culture, rng)
	var roll := _roll(rng)
	if roll < COMMON_LIST_CHANCE:
		return _pick(COMMON_SURNAMES[culture], rng)
	if roll < COMMON_LIST_CHANCE + COMMON_PATRONYMIC_CHANCE:
		return _patronymic(culture, rng)
	return NOBLE_PARTICLE[culture] + place(culture, rng)

## Casa noble (para los señores del mapa). Puede ser histórica o un topónimo generado.
static func house(culture: int, rng: RandomNumberGenerator = null) -> String:
	culture = valid(culture)
	if culture == Culture.ROMANA:
		return _roman_surname(CharacterEnums.Gender.MASCULINO, rng)
	if _roll(rng) < NOBLE_HOUSE_CHANCE:
		return _pick(NOBLE_HOUSES[culture], rng)
	return NOBLE_PARTICLE[culture] + place(culture, rng)

## Topónimo generado (sin partícula).
static func place(culture: int, rng: RandomNumberGenerator = null) -> String:
	culture = valid(culture)
	var pre: String = _pick(PLACE_PREFIX.get(culture, PLACE_PREFIX[Culture.FRANCA]), rng)
	var suf: String = _pick(PLACE_SUFFIX.get(culture, PLACE_SUFFIX[Culture.FRANCA]), rng)
	if culture == Culture.CASTELLANA and pre in ["Torre", "Fuente", "Peña", "Puebla", "Ribera", "Cueva", "Vega", "Hoya"]:
		return "%s %s" % [pre, suf.capitalize()]   # «Torre Negra», «Peña Blanca»
	return pre + suf

static func byname(gender: int, rng: RandomNumberGenerator = null) -> String:
	var pair: Array = BYNAMES[rng.randi() % BYNAMES.size()] if rng != null else BYNAMES.pick_random()
	return pair[1] if gender == CharacterEnums.Gender.FEMENINO else pair[0]

## El apellido romano concuerda con el sexo; el resto no cambia.
static func gendered_surname(base: String, culture: int, gender: int) -> String:
	if culture != Culture.ROMANA or gender != CharacterEnums.Gender.FEMENINO:
		return base
	var words: Array = Array(base.split(" ", false)).map(func(w: String) -> String: return _feminine_latin(w))
	# Como en _roman_surname: el nombre de una romana ya es el nomen («Mucia»), así que de
	# «Mucio Marcelo» solo queda el cognomen («Marcela»), sin repetir «Mucia Mucia».
	if words.size() >= 2:
		words = words.slice(1)
	return " ".join(words)

static func full_name(culture: int, gender: int, rank: int = NOBLE_RANK) -> String:
	return "%s %s" % [first_name(culture, gender), surname(culture, gender, rank)]

static func _patronymic(culture: int, rng: RandomNumberGenerator) -> String:
	if PATRONYMICS.has(culture):
		return _pick(PATRONYMICS[culture].values(), rng)
	if not PATRONYMIC_PATTERN.has(culture):   # alemanes y prusianos: oficio o apodo
		return _pick(COMMON_SURNAMES[culture], rng)
	var father := first_name(culture, CharacterEnums.Gender.MASCULINO, rng)
	var patterns: Array = PATRONYMIC_PATTERN.get(culture, ["de %s"])
	return (_pick(patterns, rng)) % father

# Varones: nomen + cognomen (con el praenomen delante, «Lucio Cornelio Escipión»). Mujeres: su nombre ya es
# el nomen de la familia, así que el apellido es solo el cognomen en femenino («Livia Drusa»).
static func _roman_surname(gender: int, rng: RandomNumberGenerator) -> String:
	if gender == CharacterEnums.Gender.FEMENINO:
		return _feminine_latin(_pick(ROMAN_COGNOMINA, rng))
	return "%s %s" % [_pick(ROMAN_NOMINA, rng), _pick(ROMAN_COGNOMINA, rng)]

# «Cornelio» → «Cornelia», «Máximo» → «Máxima»; los que no acaban en -o no cambian (César, Escipión).
static func _feminine_latin(word: String) -> String:
	if word.ends_with("o"):
		return word.substr(0, word.length() - 1) + "a"
	return word

static func _roll(rng: RandomNumberGenerator) -> float:
	return rng.randf() if rng != null else randf()

static func _pick(pool: Array, rng: RandomNumberGenerator) -> String:
	if pool.is_empty():
		return ""
	return pool[rng.randi() % pool.size()] if rng != null else pool.pick_random()
