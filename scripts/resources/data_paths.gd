class_name DataPaths
extends RefCounted
# Dónde se guardan los datos del jugador (partidas, personajes, opciones).
# Cuando el juego se ejecuta desde un script de pruebas (godot --script ...), todo va a una
# carpeta aparte para que las pruebas automáticas nunca toquen las partidas reales.

const TEST_ROOT := "user://_pruebas/"

static func root() -> String:
	return TEST_ROOT if is_test_run() else "user://"

static func is_test_run() -> bool:
	return "--script" in OS.get_cmdline_args() or "-s" in OS.get_cmdline_args()

## Ruta dentro de la carpeta de datos, p. ej. path("saves") -> "user://saves".
static func path(relative: String) -> String:
	return root() + relative
