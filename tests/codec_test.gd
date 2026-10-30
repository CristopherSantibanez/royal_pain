extends SceneTree
# Seguridad y fidelidad del DataCodec, más la migración de un personaje .tres antiguo.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var DC = load("res://scripts/resources/data_codec.gd")
	var CL = load("res://scripts/resources/character_loader.gd")
	var CH = load("res://scripts/resources/character.gd")
	# 1. Tipos no permitidos y texturas de fuera del juego se ignoran.
	print("Tipo desconocido -> ", DC.decode({"_type": "Node", "name": "x"}))
	print("Script inyectado -> ", DC.decode({"_type": "Character", "script": "res://evil.gd", "first_name": "Ana"}).get_script().resource_path)
	var bad_tex: Character = DC.decode({"_type": "Character", "portrait": {"_tex": "user://malo.png"}, "first_name": "Eva"})
	print("Textura de fuera -> ", bad_tex.portrait, " · nombre ", bad_tex.first_name)
	print("JSON roto -> ", DC.from_json("{no es json"))

	# 2. Ida y vuelta de un PNJ completo.
	var npc: Character = CL.make_random_character(CH.Role.CABALLERO, 1, "res://assets/portraits/characters/female/woman3.png")
	var back: Character = DC.from_json(DC.to_json(npc))
	var same := back.full_name() == npc.full_name() and back.combat == npc.combat and back.personality == npc.personality \
		and back.portrait == npc.portrait and back.combat_skills.size() == npc.combat_skills.size() \
		and back.equipment.size() == npc.equipment.size() and back.advantages.size() == npc.advantages.size()
	print("Ida y vuelta igual: ", same, " (", back.full_name(), ", habilidades ", back.combat_skills.size(), ", equipo ", back.equipment.size(), ")")
	print("Tipos tras cargar: skill=", back.combat_skills[0].get_script() == load("res://scripts/resources/skill.gd") if not back.combat_skills.is_empty() else "sin habilidades")

	# 3. Migración de un .tres antiguo en la carpeta de personajes (de pruebas).
	DirAccess.make_dir_recursive_absolute(CL.characters_dir())
	var legacy: String = CL.characters_dir() + "/antiguo.tres"
	ResourceSaver.save(npc, legacy)
	var paths: Array = CL.get_saved_character_paths()
	print("Migrado: ", paths.any(func(p): return p.ends_with("antiguo.json")), " · .tres renombrado: ", FileAccess.file_exists(legacy + ".migrado"))
	print("Carpeta usada: ", CL.characters_dir())
	quit()
