extends SceneTree
func _initialize() -> void:
	var G = load("res://scripts/resources/glossary_data.gd")
	var n := 0
	for cat in G.CATEGORIES:
		if not G.ENTRIES.has(cat) and not cat in G.DYNAMIC:
			print("FALTA categoria ", cat)
	for k in G.ENTRIES:
		n += G.ENTRIES[k].size()
	print("entradas: ", n, " categorias: ", G.CATEGORIES.size())
	quit()
