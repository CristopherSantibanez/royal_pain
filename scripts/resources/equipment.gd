class_name Equipment
extends Resource

@export var equipment_name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var slot: String = "Accesorio"   # Arma, Armadura, Escudo, Montura o Accesorio (una pieza por ranura)
@export_range(1, 4) var tier: int = 1    # calidad: 1 común, 2 buena, 3 excepcional, 4 única (habilidad propia)
@export var price: int = 0               # precio orientativo en oro (tiendas, recompensas)

# Bonos de combate
@export var combat_mod: int = 0
@export var defense_mod: int = 0

# Bonos políticos (usa el mismo objeto tanto en duelo como en mapa/diplomacia)
@export var leadership_mod: int = 0
@export var charisma_mod: int = 0
@export var strategy_mod: int = 0
