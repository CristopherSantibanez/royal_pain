class_name Equipment
extends Resource

@export var equipment_name: String = ""
@export var description: String = ""
@export var icon: Texture2D

# Bonos de combate
@export var combat_mod: int = 0
@export var defense_mod: int = 0

# Bonos políticos (usa el mismo objeto tanto en duelo como en mapa/diplomacia)
@export var leadership_mod: int = 0
@export var charisma_mod: int = 0
@export var strategy_mod: int = 0
