extends Node
# Autoload — registrar como "CreationState"

var pending_character: Character
var last_saved_path: String = ""   # para preseleccionarlo en Nueva Partida
var edit_character: Character         # personaje guardado que se está editando (Mis personajes)
var edit_path: String = ""            # su archivo: al guardar se actualiza en vez de crear otro

func clear_edit() -> void:
	edit_character = null
	edit_path = ""
