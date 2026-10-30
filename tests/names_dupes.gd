extends SceneTree

func _initialize() -> void:
	var NC = load("res://scripts/resources/name_catalog.gd")
	for cu in NC.CULTURE_COUNT:
		var m: Array = NC.MALE[cu]
		var f: Array = NC.FEMALE[cu]
		var both := m.filter(func(n): return n in f)
		var dm := []
		for n in m:
			if m.count(n) > 1 and not n in dm:
				dm.append(n)
		var df := []
		for n in f:
			if f.count(n) > 1 and not n in df:
				df.append(n)
		var spaced := (m + f).filter(func(n: String): return " " in n)
		print(NC.culture_name(cu), " ambos=", both, " dupH=", dm, " dupM=", df, " espacios=", spaced)
	quit()
