class_name SaveGame
extends Resource
# Foto completa de una partida en curso. Castillos, ejércitos y personaje se guardan
# como sub-recursos dentro del mismo archivo .tres.

@export var summary: String = ""          # texto corto para mostrar en el menú
@export var saved_at: String = ""

@export_group("Jugador")
@export var player: Character
@export var home_castle_id: String = ""
@export var player_kingdom: int = -1

@export_group("Tiempo")
@export var month: int = 1
@export var year: int = 1
@export var actions_remaining: int = 0
@export var actions_per_turn: int = 0
@export var pending_event: Dictionary = {}
@export var last_annual_event: String = ""

@export_group("Mundo")
@export var castles: Array[Castle] = []
@export var armies: Array[Army] = []
@export var next_army_id: int = 1
@export var turn_events: Array[Dictionary] = []
