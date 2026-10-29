extends SceneTree
# Compara el recorte automático (en el juego) con el de la herramienta para todos los retratos.

func _initialize() -> void:
	var FD = load("res://scripts/resources/face_detector.gd")
	var FR = load("res://scripts/resources/face_rects.gd")
	var worst := 0.0
	var worst_path := ""
	var sum := 0.0
	var n := 0
	var t0 := Time.get_ticks_msec()
	for path in FR.RECTS:
		var tex: Texture2D = load(path)
		var auto: Array = FD._compute(tex)
		var ref: Array = FR.RECTS[path]
		if auto.size() != 3:
			print("  SIN RESULTADO: ", path)
			continue
		# Error en proporción al lado del recorte: desplazamiento del centro + diferencia de tamaño.
		var c_auto := Vector2(auto[0] + auto[2] / 2.0, auto[1] + auto[2] / 2.0)
		var c_ref := Vector2(ref[0] + ref[2] / 2.0, ref[1] + ref[2] / 2.0)
		var err: float = (c_auto.distance_to(c_ref) + absf(auto[2] - ref[2])) / float(ref[2])
		sum += err
		n += 1
		if err > worst:
			worst = err
			worst_path = "%s auto=%s ref=%s" % [path.get_file(), auto, ref]
	var ms := Time.get_ticks_msec() - t0
	print("retratos: %d · %.0f ms cada uno" % [n, float(ms) / maxi(1, n)])
	print("error medio: %.1f%% del lado · peor: %.1f%% (%s)" % [100.0 * sum / maxi(1, n), 100.0 * worst, worst_path])
	# Caché: segunda llamada instantánea y guardada en la carpeta de pruebas.
	var tex2: Texture2D = load(FR.RECTS.keys()[0])
	FD.face_rect(tex2)
	var t1 := Time.get_ticks_usec()
	FD.face_rect(tex2)
	print("segunda vez (caché): %.2f ms · archivo: %s" % [(Time.get_ticks_usec() - t1) / 1000.0, FileAccess.file_exists(DataPaths.path(FD.CACHE_FILE))])
	quit()
