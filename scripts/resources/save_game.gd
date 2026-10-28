class_name SaveGame
extends Resource
# Foto completa de una partida en curso. Castillos, ejércitos y personaje se guardan
# como sub-recursos dentro del mismo archivo .tres.

@export var version: int = 1              # versión del formato (ver SaveSystem.SAVE_VERSION y _migrate)
@export var summary: String = ""          # texto corto para mostrar en el menú
@export var saved_at: String = ""

@export_group("Jugador")
@export var player: Character
@export var home_castle_id: String = ""
@export var player_kingdom: int = -1
@export var starting_role: int = -1
@export var victory_achieved: bool = false
@export var active_edict: String = ""
@export var last_tournament_year: int = 0

@export_group("Tiempo")
@export var month: int = 1
@export var year: int = 1
@export var actions_remaining: int = 0
@export var actions_per_turn: int = 0
@export var pending_event: Dictionary = {}
@export var event_queue: Array = []   # eventos esperando turno (ver GameManager.queue_event)
@export var last_annual_event: String = ""

@export_group("Mundo")
@export var castles: Array[Castle] = []
@export var armies: Array[Army] = []
@export var next_army_id: int = 1
@export var turn_events: Array[Dictionary] = []
@export var relations: Array[Relationship] = []
@export var used_portraits: Array[String] = []
@export var kingdom_wars: Dictionary = {}
@export var kingdom_alliances: Dictionary = {}
@export var liege_name: String = ""
@export var spouse_name: String = ""
@export var spouse_family: String = ""

@export_group("Módulos")
## Estado de los sistemas que se guardan solos (misiones, eventos del mundo, séquito...):
## nombre del autoload -> Dictionary con datos planos (sin objetos). Ver SaveSystem.MODULES.
@export var modules: Dictionary = {}
